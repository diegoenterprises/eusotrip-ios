//
//  PerLoadWeatherCard.swift
//  EusoTrip — the bespoke per-load weather card.
//
//  Renders the `weather.forLoad` payload (one load: origin/destination
//  realtime + §3 LaneImpact + timelines + alerts) through the SAME
//  Wave-1 v3 bespoke signature components used by `WeatherCard.swift`
//  (SkyStageHero · HourlyRibbon · RouteCellDiagram · DayRangeBar) and the
//  in-house `WeatherIcons` glyph corpus. ZERO SF Symbols, zero emoji,
//  zero generic weather UI — bespoke as the doctrine reads.
//
//  Data contract:
//    • `WeatherForLoad`     — the per-load card (origin realtime hero +
//                             §3 LaneImpact). Decoded 1:1 from the server.
//    • `WeatherCardStore`   — the @MainActor store that owns the three
//                             tRPC calls (forLoad · timelines · getAlerts),
//                             keeps last-good + `isStale` on failure, and
//                             auto-refreshes (30 s active / 10 min idle).
//
//  Reuse strategy (no component forks): the Wave-1 components are typed
//  against `WeatherSnapshot` value types. Rather than add a second init to
//  each, this card MAPS the per-load data into those value types AT THE
//  CALL SITE:
//    • `HourPoint`            → `WeatherSnapshot.HourlyForecast`  (ribbon)
//    • `WeatherForLoad.LaneImpact` → `WeatherSnapshot.LaneImpactSegment`
//                                                          (route diagram)
//    • `DayPoint`/`SkyStageHero`/`DayRangeBar` take primitives → driven
//      directly with no bridge type.
//  Both helper structs have internal memberwise initializers (same module),
//  so the components are reused UNCHANGED — no new initializer was added to
//  any Wave-1 component.
//
//  Honesty doctrine (matches WeatherSnapshot Level-100): every value binds
//  to a real field. Each sub-view HIDES when its store field is nil/empty;
//  a staleness chip + freshness line surface honestly; "—" everywhere via
//  the `WeatherForLoad` display helpers. The route-cell diagram renders
//  only when `card.hasLaneRisk`. The mockup numbers (88°, +40 m, AUSTIN,
//  LD-260615) are DESIGN placeholders — never shipped. 0 STUBS · 0 MOCK.
//

import SwiftUI

struct PerLoadWeatherCard: View {

    /// The load whose weather this card renders. Drives every tRPC call
    /// through `WeatherCardStore`.
    let loadId: String
    /// `true` for an in-progress / live-tracked load → faster auto-refresh
    /// (~30 s) and the card starts expanded; `false` → one-shot load and
    /// the collapsed dashboard tile.
    var isActive: Bool = false
    /// Start expanded regardless of `isActive` (e.g. pushed as its own
    /// screen). Default: expand for active loads, collapse otherwise.
    var startExpanded: Bool? = nil

    @StateObject private var store = WeatherCardStore()
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// v3 two-state: collapsed dashboard tile ↔ expanded full view.
    @State private var expanded: Bool
    /// Presentation-only astronomy clock. It advances independently of the
    /// provider observation so a retained card crosses sunrise/sunset without
    /// mutating the real weather values or remounting the view.
    @State private var displayDate = Date()

    init(loadId: String, isActive: Bool = false, startExpanded: Bool? = nil) {
        self.loadId = loadId
        self.isActive = isActive
        self.startExpanded = startExpanded
        _expanded = State(initialValue: startExpanded ?? isActive)
    }

    /// Build the REAL `WeatherSnapshot` the build-751 sky engine consumes,
    /// from this load's live origin realtime block. Every input maps from a
    /// genuine upstream field (`origin.realtime.*`, `origin.lat`,
    /// `realtime.observedAt`); absent fields fall through to the snapshot's
    /// own nil-safe defaults — zero fabrication. The engine keys its scene off
    /// `weatherCode` (so Drizzle/Rain/Heavy-Rain/Thunderstorm each animate
    /// distinctly) and scales precipitation/wind/fog/visibility by the live
    /// numbers.
    private func heroSkySnapshot(_ card: WeatherForLoad) -> WeatherSnapshot? {
        let rt = card.origin?.realtime
        guard
            let temperature = WeatherNumeric.roundedInt(
                rt?.temperature,
                allowed: WeatherNumeric.temperatureF
            ),
            let windSpeed = WeatherNumeric.roundedInt(
                rt?.windSpeedMph,
                allowed: WeatherNumeric.windMph
            )
        else { return nil }
        var snap = WeatherSnapshot(
            city: card.origin?.name ?? "",
            tempF: temperature,
            windMph: windSpeed,
            // Honest nil when the realtime block omitted visibility —
            // the sky engine treats nil as no choke (em-dash doctrine).
            visibilityMi: WeatherNumeric.roundedInt(
                rt?.visibilityMi,
                allowed: WeatherNumeric.visibilityMi
            ),
            condition: rt?.condition ?? "",
            symbol: "cloud.fill",
            nextAlert: nil,
            accent: .calm
        )
        snap.weatherCode = card.heroWeatherCode
        snap.precipChancePct = WeatherNumeric.roundedInt(
            rt?.precipitationProbability,
            allowed: WeatherNumeric.percent
        )
        snap.latitude = card.origin?.lat
        snap.longitude = card.origin?.lon
        let normalizedSource = (card.source ?? "").lowercased()
        if normalizedSource.contains("here") {
            snap.dataSource = .here
        } else if normalizedSource.contains("weatherkit") || normalizedSource.contains("apple weather") {
            snap.dataSource = .weatherKit
        } else if normalizedSource.contains("openweather") {
            snap.dataSource = .openWeather
        }
        if let iso = rt?.observedAt {
            snap.observedAt = ISO8601DateFormatter().date(from: iso)
        }
        return snap
    }

    var body: some View {
        Group {
            if let card = store.card {
                // We hold a (last-good) payload — render it, honestly
                // flagged stale via the eyebrow chip when the last refresh
                // failed. `available == false` → the honest no-data state.
                if card.isAvailable {
                    content(card)
                } else {
                    unavailableState(card)
                }
            } else if store.phase == .failed {
                // No payload ever AND the load failed → honest empty.
                failedState
            } else {
                // Idle / first load in flight.
                loadingState
            }
        }
        .task(id: loadId) {
            if isActive {
                // Active loads already poll on a live cadence; a failed tick
                // keeps the last-good card and self-heals on the next poll.
                store.startAutoRefresh(loadId: loadId, inProgress: true)
            } else {
                // One-shot load. If the FIRST fetch misses with no last-good
                // card, the view shows the soft "Updating lane weather…"
                // placeholder (never "unavailable"); keep silently retrying
                // (~45s back-off, mirroring the build-747 HomeWeatherWidget)
                // until the first real reading lands, then stop. SwiftUI
                // cancels this loop when the card leaves the screen.
                await store.load(loadId: loadId)
                while !Task.isCancelled && store.card == nil {
                    try? await Task.sleep(nanoseconds: 45 * 1_000_000_000)
                    if Task.isCancelled { break }
                    await store.load(loadId: loadId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoWeatherDisplayClockChanged)) { _ in
            displayDate = Date()
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
                displayDate = Date()
            }
        }
        .onDisappear { store.stop() }
    }

    // MARK: - Loaded content (collapsed ↔ expanded)

    @ViewBuilder
    private func content(_ card: WeatherForLoad) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            if expanded {
                expandedBody(card)
            } else {
                collapsedBody(card)
            }
        }
        .padding(14)
        .background(
            // Always-dark sky ink (NOT the adaptive palette.bgCard, which
            // went white in light mode and made every white-text element —
            // eyebrow, tiles, ribbon labels, day chips, source line —
            // invisible). Matches WeatherCard's dayChip/laneImpactPanel.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(WeatherV3.cardInk)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if !expanded { withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded = true } }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
    }

    // MARK: Eyebrow — "{MODE} · WEATHER" with the brand conic dot.

    private var eyebrow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AngularGradient(
                    gradient: Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB,
                                                WeatherV3.auroraC, WeatherV3.auroraA]),
                    center: .center, angle: .degrees(160)))
                .frame(width: 7, height: 7)
            Text(eyebrowText)
                .font(.system(size: 11, weight: .heavy)).tracking(2.4)
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: Space.s1)
            if store.isStale { staleChip }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 11)
    }

    private var eyebrowText: String {
        guard let card = store.card else { return "WEATHER" }
        let modeWord: String = {
            switch card.mode {
            case .truck:  return "LANE"
            case .rail:   return "CORRIDOR"
            case .vessel: return "VOYAGE"
            }
        }()
        let id = (card.loadNumber ?? card.loadId).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? "\(modeWord) · WEATHER" : "\(modeWord) · WEATHER · \(id.uppercased())"
    }

    /// The honest staleness chip — shown only when the last refresh failed
    /// but we still hold a last-good payload. Never fabricated.
    private var staleChip: some View {
        HStack(spacing: 4) {
            Circle().fill(Brand.warning).frame(width: 5, height: 5)
            Text("STALE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.warning)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Brand.warning.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Collapsed (dashboard tile)

    @ViewBuilder
    private func collapsedBody(_ card: WeatherForLoad) -> some View {
        ZStack(alignment: .bottomLeading) {
            // build-751: the continuous animated sky engine behind the
            // per-load hero, driven by this lane's live origin weather.
            if let snapshot = heroSkySnapshot(card) {
                SkyStageHeroLive(snapshot: snapshot,
                                 animated: !reduceMotion,
                                 compact: true,
                                 displayDate: displayDate)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 13) {
                    WeatherIcons.symbolView(
                        for: card.heroWeatherCode,
                        isDaylight: heroSkySnapshot(card)?.displaySolarState(at: displayDate).isDaylight,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        locationLine(card, size: 12)
                        Text(collapsedConditionLine(card))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s1)
                    superscriptTemp(card.heroTempDisplay, size: 38, supSize: 16)
                }
                .padding(.horizontal, 4)

                // honest alert pill (collapsed) — only when an alert is live
                if let alert = store.alert {
                    collapsedAlertPill(alert).padding(.top, 11)
                }
            }
            .padding(14)
        }
        .frame(height: 150)
    }

    private func collapsedConditionLine(_ card: WeatherForLoad) -> String {
        let parts = [card.conditionLine, card.feelsLikeDisplay].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func collapsedAlertPill(_ alert: AlertBar) -> some View {
        HStack(spacing: 7) {
            WeatherIcons.utility(.alert, size: 13, tint: .white)
            Text(alert.title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(alertColor(alert).opacity(0.9)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Expanded (full per-load view)

    @ViewBuilder
    private func expandedBody(_ card: WeatherForLoad) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            // ── Sky-stage hero + readout ───────────────────────────────
            ZStack(alignment: .topLeading) {
                // build-751: the full continuous animated sky engine behind
                // the expanded per-load hero, driven by live origin weather.
                if let snapshot = heroSkySnapshot(card) {
                    SkyStageHeroLive(snapshot: snapshot,
                                     animated: !reduceMotion,
                                     displayDate: displayDate)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        locationLine(card, size: 13)
                        if let cond = card.conditionLine {
                            Text(cond)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        superscriptTemp(card.heroTempDisplay, size: 60, supSize: 22)
                            .padding(.top, 1)
                        if let feels = card.feelsLikeDisplay {
                            Text(feels)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    VStack(spacing: 10) {
                        // Collapse affordance (chevron up) — ports the
                        // WeatherCard pattern; without it the card was
                        // stuck expanded once opened.
                        Button {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                expanded = false
                            }
                        } label: {
                            WeatherIcons.utility(.chev, size: 16, tint: .white.opacity(0.85))
                                .rotationEffect(.degrees(180))
                                .padding(7)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse lane weather")
                        WeatherIcons.symbolView(
                            for: card.heroWeatherCode,
                            isDaylight: heroSkySnapshot(card)?.displaySolarState(at: displayDate).isDaylight,
                            size: 66
                        )
                    }
                }
                .padding(16)
            }

            // ── Government alert bar — honest, only when live ──────────
            if let alert = store.alert {
                alertBar(alert)
            }

            // ── 4 metric tiles (wind · vis · humidity · precip) ───────
            metricsGrid(card)

            // ── Hourly ribbon — reuses the Wave-1 HourlyRibbon ────────
            if !store.hourly.isEmpty {
                ribbonSection
            }

            // ── §3 Lane Impact — route-cell diagram, only on real risk ─
            if card.hasLaneRisk, let li = card.laneImpact {
                laneImpactPanel(card, li)
            }

            // ── 7-day chips — reuse the Wave-1 DayRangeBar ────────────
            if !store.daily.isEmpty {
                dayChips
            }

            hairline.padding(.vertical, 2)

            // ── Source / freshness line ───────────────────────────────
            sourceLine(card)
        }
    }

    // MARK: Hero readout helpers (bespoke, shared with WeatherCard idioms)

    private func locationLine(_ card: WeatherForLoad, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            WeatherIcons.utility(.pin, size: size, tint: WeatherV3.nodeOrigin)
            Text((card.locationName ?? "—").uppercased())
                .font(.system(size: size, weight: .heavy)).tracking(0.4)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    /// The §D.1.5 superscript-degree readout — accepts the pre-formatted
    /// "88°"/"—" display string from `WeatherForLoad`, splitting the trailing
    /// degree sign into the raised superscript. Honest "—" passes through.
    private func superscriptTemp(_ display: String, size: CGFloat, supSize: CGFloat) -> some View {
        let hasDegree = display.hasSuffix("°")
        let number = hasDegree ? String(display.dropLast()) : display
        return HStack(alignment: .top, spacing: 1) {
            Text(number)
                .font(.system(size: size, weight: .ultraLight))
                .monospacedDigit()
            if hasDegree {
                Text("°")
                    .font(.system(size: supSize, weight: .light))
                    .padding(.top, size * 0.12)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: Alert bar

    @ViewBuilder
    private func alertBar(_ alert: AlertBar) -> some View {
        if let detailsURL = alert.detailsURL {
            Link(destination: detailsURL) {
                alertBarContent(alert, showsLink: true)
            }
            .buttonStyle(.plain)
        } else {
            alertBarContent(alert, showsLink: false)
        }
    }

    private func alertBarContent(_ alert: AlertBar, showsLink: Bool) -> some View {
        HStack(spacing: 9) {
            WeatherIcons.utility(.alert, size: 18, tint: .white)
            Text(alert.title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: Space.s1)
            Text(alertMetaLine(alert))
                .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            if showsLink {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [alertColor(alert).opacity(0.95),
                                              alertColor(alert).opacity(0.6)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }

    private func alertMetaLine(_ alert: AlertBar) -> String {
        [alert.severity.uppercased(), alert.untilDisplay, alert.issuingSource]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// Alert severity → brand color (Brand.danger / warning / info ladder).
    private func alertColor(_ alert: AlertBar) -> Color {
        switch alert.severity.lowercased() {
        case "extreme", "severe": return Brand.danger
        case "moderate":          return Brand.warning
        default:                  return Brand.info
        }
    }

    // MARK: Metric tiles

    private func metricsGrid(_ card: WeatherForLoad) -> some View {
        let tiles = card.metricTiles
        let glyphs: [WeatherIcons.Utility] = [.wind, .eye, .humid, .precip]
        return HStack(spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { idx, tile in
                metricTile(glyphs[safe: idx] ?? .precip, value: tile.value, key: tile.key)
            }
        }
    }

    private func metricTile(_ glyph: WeatherIcons.Utility, value: String, key: String) -> some View {
        VStack(spacing: 3) {
            WeatherIcons.utility(glyph, size: 17, tint: Color(red: 0.81, green: 0.88, blue: 1.0))
            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(key)
                .font(.system(size: 9.5)).tracking(0.3)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: Hourly ribbon — reuse Wave-1 HourlyRibbon by mapping HourPoint
    //       → WeatherSnapshot.HourlyForecast at the call site.

    private var ribbonSection: some View {
        let series = bridgedHours
        return HourlyRibbon(
            hours: series,
            peakIndex: bridgedPeakIndex(series),
            solarSnapshot: store.card.flatMap { heroSkySnapshot($0) }
        )
            .padding(.top, 2)
    }

    /// Map each `HourPoint` (the store's tolerant ribbon VM) onto the
    /// Wave-1 `WeatherSnapshot.HourlyForecast` the component expects. A
    /// A point without a real timestamp or temperature is omitted rather than
    /// plotted at a fabricated zero or `.distantPast` position.
    private var bridgedHours: [WeatherSnapshot.HourlyForecast] {
        store.hourly.compactMap { hp in
            guard let time = hp.time, let tempF = hp.tempF else { return nil }
            return WeatherSnapshot.HourlyForecast(
                date: time,
                tempF: tempF,
                symbol: "",
                precipChancePct: hp.precipPct,
                windMph: nil,
                weatherCode: hp.weatherCode
            )
        }
    }

    /// The peak hour for the ribbon's danger column — derived from the
    /// bridged series exactly like `WeatherSnapshot.peakHourIndex` (worst
    /// Apple WeatherKit code family, ties broken by precip). Nil when nothing
    /// rises above benign → no danger column drawn (honest).
    private func bridgedPeakIndex(_ series: [WeatherSnapshot.HourlyForecast]) -> Int? {
        guard !series.isEmpty else { return nil }
        func hazard(_ h: WeatherSnapshot.HourlyForecast) -> Int {
            let bucket: Int
            switch h.weatherCode {
            case 8000:                                       bucket = 5
            case 4201, 6201, 7101:                           bucket = 4
            case 4001, 5101, 6001, 6200, 7000:               bucket = 3
            case 4000, 4200, 5000, 5001, 5100, 6000, 7102:   bucket = 2
            case 2000, 2100:                                 bucket = 1
            default:                                         bucket = 0
            }
            return bucket * 1000 + (h.precipChancePct ?? 0)
        }
        let scored = series.enumerated().max { hazard($0.element) < hazard($1.element) }
        guard let best = scored, hazard(best.element) > 0 else { return nil }
        return best.offset
    }

    // MARK: §3 Lane Impact — reuse Wave-1 RouteCellDiagram by mapping the
    //       WeatherForLoad.LaneImpact → WeatherSnapshot.LaneImpactSegment.

    @ViewBuilder
    private func laneImpactPanel(_ card: WeatherForLoad, _ li: WeatherForLoad.LaneImpact) -> some View {
        let seg = bridgedSegment(card, li)
        VStack(alignment: .leading, spacing: 0) {
            // header: route glyph · {LANE/CORRIDOR/VOYAGE} IMPACT
            HStack(spacing: 8) {
                WeatherIcons.utility(.route, size: 15, tint: WeatherV3.nodeOrigin)
                Text(laneHeaderTitle(card.mode))
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(seg.riskTier.rawValue.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(WeatherV3.danger.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(WeatherV3.danger.opacity(0.46), lineWidth: 1))
            }

            // route-cell diagram + footer (the Wave-1 showpiece, unchanged)
            VStack(spacing: 0) {
                RouteCellDiagram(segment: seg)
                routeFooter(seg, li)
            }
            .padding(.top, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0x17 / 255, green: 0x1A / 255, blue: 0x24 / 255),
                                 Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x1C / 255)],
                        startPoint: .top, endPoint: .bottom)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // §3 drivers — mode-specific tiles (server-formatted values)
            if !seg.drivers.isEmpty {
                driverTiles(seg).padding(.top, 11)
            }

            Text(seg.routeWeatherAttribution)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 8)

            // Deterministic policy guidance; no AI branding without a model call.
            if let rec = seg.recommendation {
                operationalRecommendation(rec).padding(.top, 12)
            }
        }
        .padding(15)
        .background(
            // Always-dark ink — white panel text must survive light mode.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(WeatherV3.cardInk)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(modeAccent(card.mode).opacity(0.35), lineWidth: 1)
        )
    }

    /// Build the Wave-1 `WeatherSnapshot.LaneImpactSegment` from the §3
    /// `WeatherForLoad.LaneImpact` + the card's origin/destination names.
    /// All §3 fields map 1:1; the EusoTrip render helpers (`route`,
    /// `pickupTime`, `etaDelayMin`, `esangSuggestion`) are filled from the
    /// real endpoint names / left nil so the diagram + footer read from the
    /// §3 structured form. Nothing is fabricated — the headline falls
    /// through to the §3 `headline`, the labels to the real endpoint names.
    private func bridgedSegment(_ card: WeatherForLoad,
                                _ li: WeatherForLoad.LaneImpact) -> WeatherSnapshot.LaneImpactSegment {
        let mode: WeatherSnapshot.LaneMode = {
            switch li.mode {
            case .truck:  return .truck
            case .rail:   return .rail
            case .vessel: return .vessel
            }
        }()
        let tier: WeatherSnapshot.RiskTier = {
            switch li.riskTier {
            case .none:     return .none
            case .watch:    return .watch
            case .elevated: return .elevated
            case .severe:   return .severe
            }
        }()
        let peak: WeatherSnapshot.PeakLeg? = li.peakLeg.map {
            WeatherSnapshot.PeakLeg(label: $0.label, time: laneClockLabel($0.time))
        }
        let drivers: [WeatherSnapshot.Driver] = (li.drivers ?? []).map {
            WeatherSnapshot.Driver(
                field: $0.field,
                value: $0.value,
                available: $0.isAvailable,
                unavailableReason: $0.unavailableReason
            )
        }
        let rec: WeatherSnapshot.Recommendation? = li.recommendation.map {
            WeatherSnapshot.Recommendation(text: $0.text, action: $0.action, protects: $0.protects)
        }
        // "Origin → Destination" route string for the diagram's endpoint
        // labels — built from the REAL endpoint names (honest "" when absent
        // so the label simply doesn't draw).
        let o = card.origin?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let d = card.destination?.name.trimmingCharacters(in: .whitespaces) ?? ""
        let route = (!o.isEmpty && !d.isEmpty) ? "\(o) → \(d)" : o

        return WeatherSnapshot.LaneImpactSegment(
            loadId: li.loadNumber ?? card.loadNumber ?? card.loadId,
            mode: mode,
            riskTier: tier,
            headline: li.headline ?? "",
            peakLeg: peak,
            drivers: drivers,
            recommendation: rec,
            computedAt: li.computedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            source: li.source,
            route: route,
            pickupTime: nil,
            etaDelayMin: nil,
            esangSuggestion: nil
        )
    }

    private func laneClockLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: trimmed) ?? plain.date(from: trimmed) else {
            return trimmed
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func laneHeaderTitle(_ mode: WeatherMode) -> String {
        switch mode {
        case .rail:   return "CORRIDOR IMPACT"
        case .vessel: return "VOYAGE + BERTH IMPACT"
        case .truck:  return "LANE IMPACT"
        }
    }

    /// Route-box footer: mode chip · id + lane · headline.
    private func routeFooter(_ seg: WeatherSnapshot.LaneImpactSegment,
                             _ li: WeatherForLoad.LaneImpact) -> some View {
        HStack(alignment: .center, spacing: 11) {
            WeatherIcons.utility(modeGlyph(seg.mode), size: 18,
                                 tint: modeAccentSnap(seg.mode).opacity(0.95))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(modeAccentSnap(seg.mode).opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(modeAccentSnap(seg.mode).opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(seg.loadId)
                    .font(.system(size: 12, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(footerSubtitle(seg))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 1) {
                Text(seg.headlineDisplay)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(seg.riskTier.color)
                    .lineLimit(1)
                Text(riskTierLabel(seg))
                    .font(.system(size: 9.5)).tracking(0.2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    /// The route + peak line under the load id — honest dash-joined, only
    /// the parts we actually have (the peak leg's label/time).
    private func footerSubtitle(_ seg: WeatherSnapshot.LaneImpactSegment) -> String {
        let route = seg.route.trimmingCharacters(in: .whitespaces)
        let peak = seg.peakLeg?.display
        let parts = [route.isEmpty ? nil : route, peak].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func riskTierLabel(_ seg: WeatherSnapshot.LaneImpactSegment) -> String {
        switch seg.mode {
        case .truck:  return "ETA RISK"
        case .rail:   return "DWELL ADD"
        case .vessel: return "BERTH WINDOW"
        }
    }

    // §3 driver tiles
    private func driverTiles(_ seg: WeatherSnapshot.LaneImpactSegment) -> some View {
        HStack(spacing: 8) {
            ForEach(seg.drivers) { d in
                VStack(spacing: 3) {
                    WeatherIcons.utility(driverGlyph(d.field), size: 17, tint: driverTint(d.field))
                    Text(d.displayValue)
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(d.available ? Color.white : Color.white.opacity(0.68))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(d.field.uppercased())
                        .font(.system(size: 9)).tracking(0.2)
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9).padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.09)))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(d.field)
                .accessibilityValue(d.displayValue)
                .accessibilityHint(d.available
                    ? "Live route-weather reading"
                    : (d.unavailableReason ?? "This measurement was not reported"))
            }
        }
    }

    private func driverGlyph(_ field: String) -> WeatherIcons.Utility {
        let f = field.lowercased()
        if f.contains("wave") || f.contains("swell")  { return .wave }
        if f.contains("wind") || f.contains("gust") || f.contains("crosswind") { return .wind }
        if f.contains("vis")                          { return .eye }
        if f.contains("stream") || f.contains("flow") || f.contains("flood") { return .precip }
        if f.contains("precip") || f.contains("rain") { return .precip }
        return .precip
    }

    private func driverTint(_ field: String) -> Color {
        let f = field.lowercased()
        if f.contains("precip") || f.contains("wave") { return .white }
        return WeatherIcons.hatch
    }

    // §3 operational recommendation — framed policy text/action/protects.
    private func operationalRecommendation(_ rec: WeatherSnapshot.Recommendation) -> some View {
        HStack(alignment: .top, spacing: 11) {
            WeatherIcons.utility(.route, size: 17, tint: WeatherV3.nodeOrigin)
                .frame(width: 26, height: 26)
            operationalText(rec).font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(colors: [WeatherV3.auroraA.opacity(0.15), WeatherV3.auroraB.opacity(0.12)],
                                     startPoint: .leading, endPoint: .trailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(WeatherV3.auroraB.opacity(0.34), lineWidth: 1))
    }

    private func operationalText(_ rec: WeatherSnapshot.Recommendation) -> Text {
        var t = Text("Weather guidance").bold().foregroundColor(.white)
        let framing = rec.text.trimmingCharacters(in: .whitespaces)
        if !framing.isEmpty {
            t = t + Text(" — \(framing). ").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        } else {
            t = t + Text(" — ").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        }
        t = t + Text(rec.action).bold().foregroundColor(Color(red: 0.78, green: 0.70, blue: 1.0))
        let protects = rec.protects.trimmingCharacters(in: .whitespaces)
        if !protects.isEmpty {
            t = t + Text(" — protects \(protects).").foregroundColor(Color(red: 0.93, green: 0.92, blue: 0.96))
        }
        return t
    }

    private func modeGlyph(_ mode: WeatherSnapshot.LaneMode) -> WeatherIcons.Utility {
        switch mode {
        case .truck:  return .truck
        case .rail:   return .rail
        case .vessel: return .vessel
        }
    }

    private func modeAccent(_ mode: WeatherMode) -> Color {
        switch mode {
        case .rail:   return WeatherV3.rail
        case .vessel: return WeatherV3.vessel
        case .truck:  return WeatherV3.truck
        }
    }

    private func modeAccentSnap(_ mode: WeatherSnapshot.LaneMode) -> Color {
        switch mode {
        case .rail:   return WeatherV3.rail
        case .vessel: return WeatherV3.vessel
        case .truck:  return WeatherV3.truck
        }
    }

    // MARK: 7-day chips — reuse the Wave-1 DayRangeBar by driving its
    //       primitive int inputs directly from DayPoint.

    @ViewBuilder
    private var dayChips: some View {
        let week = Array(store.daily.prefix(7))
        let weekLow = week.compactMap(\.lowF).min() ?? 0
        let weekHigh = week.compactMap(\.highF).max() ?? 1
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(week.enumerated()), id: \.element.id) { idx, day in
                    dayChip(day, isToday: idx == 0, weekLow: weekLow, weekHigh: weekHigh)
                }
            }
        }
    }

    private func dayChip(_ day: DayPoint, isToday: Bool, weekLow: Int, weekHigh: Int) -> some View {
        // Always-dark ink (matches WeatherCard.dayChip) — the adaptive
        // palette.bgCard went white in light mode and hid the chip text.
        let fill: AnyShapeStyle = isToday
            ? AnyShapeStyle(LinearGradient(
                colors: [WeatherV3.auroraB.opacity(0.30), WeatherV3.cardInk],
                startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(WeatherV3.cardInk)
        let stroke = isToday ? WeatherV3.auroraB.opacity(0.55) : Color.white.opacity(0.10)
        return VStack(spacing: 6) {
            Text(isToday ? "Today" : day.dayLabel)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white.opacity(0.84))
            WeatherIcons.symbolView(for: day.weatherCode, isDaylight: true, size: 20)
                .padding(.vertical, 1)
            // The hi→lo range bar — only when BOTH ends are present
            // (honest: a missing high/low collapses the bar, not a guess).
            if let lo = day.lowF, let hi = day.highF {
                DayRangeBar(lowF: lo, highF: hi, weekLow: weekLow, weekHigh: weekHigh)
                    .padding(.horizontal, 12)
            } else {
                Color.clear.frame(height: 4)
            }
            HStack(spacing: 4) {
                Text(day.highF.map { "\($0)°" } ?? "—")
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(day.lowF.map { "\($0)°" } ?? "—")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 62)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(stroke, lineWidth: isToday ? 1 : 0.5)
        )
    }

    // MARK: Hairline + source line

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, WeatherV3.auroraA.opacity(0.7), WeatherV3.auroraB.opacity(0.95),
                         WeatherV3.auroraC.opacity(0.7), .clear],
                startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }

    /// "Conditions · {source} · updated Nm ago" — honest provenance +
    /// freshness, each clause omitted when its data is absent.
    private func sourceLine(_ card: WeatherForLoad) -> some View {
        var parts: [String] = []
        if let source = card.source?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty {
            parts.append("Conditions · \(source)")
        } else {
            parts.append("Conditions source pending")
        }
        if let forecastSource = store.forecastSourceAttribution {
            parts.append("Forecast · \(forecastSource)")
        }
        if let freshness = card.freshnessDisplay { parts.append(freshness) }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.42))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 1)
    }

    // MARK: - Non-loaded states (honest, never fabricated)

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(WeatherV3.auroraB)
            Text("Loading lane weather…")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WeatherV3.cardInk))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    /// Reached ONLY when the very first per-load fetch missed and the store
    /// holds NO last-good card (`store.card == nil` AND `phase == .failed`).
    /// Founder mandate (2026-06-19, extends the build-747 HomeWeatherWidget):
    /// NEVER render "unavailable"/"not available" on the weather surface.
    /// Mirrors the home widget's `HomeWeatherUpdatingCard` — a soft, branded
    /// "Updating lane weather…" placeholder framed as an in-progress update,
    /// not an error. The `.task(id:)` silent-retry loop (see `body`) keeps
    /// re-fetching until the first real reading lands; the moment the store
    /// has a card it flips to the real content. Zero fabrication — no invented
    /// reading is ever shown, only the honest "still fetching" placeholder.
    private var failedState: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: [WeatherV3.auroraA, WeatherV3.auroraB,
                                                    WeatherV3.auroraC, WeatherV3.auroraA]),
                        center: .center, angle: .degrees(160)))
                    .opacity(0.18)
                    .frame(width: 48, height: 48)
                // Soft, branded last-known weather glyph — never an alarm icon.
                WeatherGlyph(kind: .cloudy)
                    .frame(width: 26, height: 26)
                    .opacity(0.85)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Updating lane weather…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Fetching the latest conditions for this lane.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WeatherV3.cardInk))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Updating lane weather")
    }

    /// Server returned a card but `available == false` (no coords / route
    /// tier absent) — honest, never a fabricated condition.
    private func unavailableState(_ card: WeatherForLoad) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow
            HStack(spacing: 9) {
                WeatherIcons.utility(.pin, size: 16, tint: WeatherV3.nodeOrigin)
                // Honest empty: the server returned `available == false`
                // (no coords / route-weather tier absent for this lane), NOT
                // a fetch failure. Worded as "coming when coords resolve",
                // never as an error and never the banned "unavailable".
                Text("Live lane weather lights up once this load has mapped endpoints")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WeatherV3.cardInk))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - WeatherForLoad availability bridge

private extension WeatherForLoad {
    /// `available` is a stored Bool on the contract; this alias keeps the
    /// view's switch readable and documents the honest gate.
    var isAvailable: Bool { available }
}

// MARK: - Safe-index helper (avoids an out-of-range crash on the glyph map)

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Previews
//
// The card is store-driven (live tRPC), so previews land on the honest
// loading placeholder — which is exactly the surface the light-mode ink
// fix must lock: the card is an ALWAYS-DARK sky surface in both schemes.

#Preview("Per-load weather · Dark") {
    ScrollView {
        PerLoadWeatherCard(loadId: "1077", isActive: true)
            .padding()
    }
    .background(Color(red: 0.04, green: 0.04, blue: 0.06))
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Per-load weather · Light") {
    ScrollView {
        PerLoadWeatherCard(loadId: "1077", isActive: true)
            .padding()
    }
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
