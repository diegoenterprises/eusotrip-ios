//
//  WeatherCardStore.swift
//  EusoTrip — the ObservableObject that feeds the v3 bespoke weather widget
//  (collapsed dashboard card + expanded view + Lane Impact) for ONE load.
//
//  Primary call: `weather.forLoad` (envelope + origin/destination realtime +
//  §3 LaneImpact). To complete the v3 widget it also pulls `weather.timelines`
//  (hourly ribbon + 7-day chips) and `weather.getAlerts` (the alert bar) at
//  the load's origin coordinates.
//
//  Honesty doctrine (matches WeatherSnapshot): on failure we keep the last
//  good payload and mark it stale — we never blank the card or fabricate.
//
//  TARGET: EusoTrip/ViewModels/WeatherCardStore.swift
//
//  Usage:
//    @StateObject private var wx = WeatherCardStore()
//    .task { await wx.load(loadId: load.id) }      // one-shot
//    .onAppear { wx.startAutoRefresh(loadId: load.id, inProgress: load.isActive) }
//    .onDisappear { wx.stop() }
//

import Foundation
import SwiftUI

private enum AmbientWeatherSourcePolicy {
    static func attribution(for raw: String?) -> String? {
        switch (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "weatherkit":
            return "Apple WeatherKit"
        case "openweather":
            return "OpenWeather fallback"
        default:
            return nil
        }
    }
}

@MainActor
final class WeatherCardStore: ObservableObject {

    enum Phase: Equatable { case idle, loading, loaded, failed }

    // MARK: Published state (the widget binds to these)
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var card: WeatherForLoad?          // last good per-load card
    @Published private(set) var hourly: [HourPoint] = []        // ribbon
    @Published private(set) var daily: [DayPoint] = []          // 7-day chips
    @Published private(set) var alert: AlertBar?                // hero alert bar
    @Published private(set) var forecastSourceAttribution: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isStale: Bool = false           // last refresh failed → show staleness chip
    @Published private(set) var errorText: String?

    private var pollTask: Task<Void, Never>?

    // MARK: One-shot load
    func load(loadId: String) async {
        if card == nil { phase = .loading }
        do {
            // 1) Canonical per-load card.
            struct In: Encodable { let loadId: String }
            let forLoad: WeatherForLoad = try await EusoTripAPI.shared.query(
                "weather.forLoad", input: In(loadId: loadId)
            )
            self.card = forLoad
            self.errorText = nil
            self.isStale = false

            // 2) Complete the v3 widget from the origin coords (best-effort —
            //    a timelines/alerts miss must NOT fail the card). The origin
            //    STATE + country ride along so the server's stateCodes filter
            //    scopes the DB alert fallback to this lane — without them a
            //    nationwide max-severity alert could paint the hero bar as if
            //    local to the load's origin.
            if let lat = forLoad.origin?.lat, let lon = forLoad.origin?.lon {
                let state = Self.stateCode(from: forLoad.origin?.name)
                async let tl: WeatherTimelines? = Self.fetchTimelines(lat: lat, lon: lon)
                async let al: [WeatherAlertRow] = Self.fetchAlerts(
                    lat: lat, lon: lon, state: state, country: Self.country(forState: state))
                let (timelines, alerts) = await (tl, al)
                if let timelines {
                    self.hourly = timelines.hourPoints
                    self.daily = timelines.dayPoints
                    self.forecastSourceAttribution = timelines.sourceAttribution
                }
                self.alert = alerts.compactMap(AlertBar.init).max(by: { $0.severityRank < $1.severityRank })
            }

            self.lastUpdated = Date()
            self.phase = .loaded
        } catch {
            // Keep last good; surface staleness honestly.
            self.errorText = (error as NSError).localizedDescription
            if self.card == nil {
                self.phase = .failed
            } else {
                self.isStale = true
                self.phase = .loaded
            }
        }
    }

    // MARK: Auto-refresh
    /// In-progress routing refreshes faster (live tracking, ~30s per the
    /// surface map); idle loads refresh on the realtime cache tier (~10 min).
    func startAutoRefresh(loadId: String, inProgress: Bool) {
        stop()
        let interval: UInt64 = inProgress ? 30 : 600   // seconds
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.load(loadId: loadId)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { break }
                await self.load(loadId: loadId)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }
    deinit { pollTask?.cancel() }

    // MARK: - Secondary fetches (feed the rest of the v3 widget)

    private static func fetchTimelines(lat: Double, lon: Double) async -> WeatherTimelines? {
        struct In: Encodable { let lat: Double; let lon: Double }
        guard let result: WeatherTimelines = try? await EusoTripAPI.shared.query(
            "weather.timelines",
            input: In(lat: lat, lon: lon)
        ), result.available != false, result.sourceAttribution != nil else {
            return nil
        }
        return result
    }

    /// `state` + `country` scope the server read: the state applies the
    /// stateCodes DB filter (no nationwide leak onto a per-load card) and
    /// the country feeds the WeatherKit weatherAlerts dataset (tri-country
    /// platform — US/CA/MX). Nil keys are omitted from the wire payload.
    private static func fetchAlerts(lat: Double, lon: Double,
                                    state: String?, country: String?) async -> [WeatherAlertRow] {
        struct In: Encodable {
            let lat: Double; let lon: Double
            let state: String?; let country: String?
        }
        let rows: [WeatherAlertRow] = (try? await EusoTripAPI.shared.query(
            "weather.getAlerts",
            input: In(lat: lat, lon: lon, state: state, country: country))) ?? []
        return rows.filter { AmbientWeatherSourcePolicy.attribution(for: $0.source) != nil }
    }

    /// "Laredo, TX" → "TX". Nil when the endpoint name carries no trailing
    /// 2-letter region code — the fetch then stays point-scoped only.
    private static func stateCode(from name: String?) -> String? {
        guard let name else { return nil }
        let parts = name.components(separatedBy: ",")
        guard parts.count >= 2,
              let last = parts.last?.trimmingCharacters(in: .whitespaces).uppercased(),
              last.count == 2, last.allSatisfy(\.isLetter) else { return nil }
        return last
    }

    private static let caProvinces: Set<String> = [
        "ON", "QC", "BC", "AB", "MB", "SK", "NS", "NB", "NL", "PE", "NT", "YT", "NU",
    ]

    /// Region code → the server's country enum ("US" | "CA"). Mexican state
    /// codes are 3 letters, so a 2-letter non-province code is a US state.
    private static func country(forState state: String?) -> String? {
        guard let state else { return nil }
        return caProvinces.contains(state) ? "CA" : "US"
    }
}

// MARK: - Ribbon / chip view-models

struct HourPoint: Identifiable, Hashable {
    let id = UUID()
    let time: Date?
    let tempF: Int?
    let weatherCode: Int        // → WeatherIcons glyph
    let precipPct: Int?
    var hourLabel: String {
        guard let time else { return "—" }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("ha"); return f.string(from: time)
    }
}

struct DayPoint: Identifiable, Hashable {
    let id = UUID()
    let day: Date?
    let highF: Int?
    let lowF: Int?
    let weatherCode: Int
    var dayLabel: String {
        guard let day else { return "—" }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE"); return f.string(from: day)
    }
}

struct AlertBar: Hashable {
    let title: String
    let severity: String   // "severe" | "extreme" | ...
    let untilDisplay: String?
    let issuingSource: String?
    let detailsURL: URL?
    var severityRank: Int {
        switch severity.lowercased() { case "extreme": return 4; case "severe": return 3; case "moderate": return 2; case "minor": return 1; default: return 0 }
    }
    init?(_ row: WeatherAlertRow) {
        guard let t = row.headline ?? row.eventType else { return nil }
        self.title = t
        self.severity = row.severity ?? "unknown"
        self.issuingSource = row.issuingSource
        self.detailsURL = row.detailsUrl.flatMap(URL.init(string:))
        if let iso = row.expiresAt, let d = ISO8601DateFormatter().date(from: iso) {
            let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("ha")
            self.untilDisplay = "until \(f.string(from: d))"
        } else { self.untilDisplay = nil }
    }
}

// MARK: - Secondary Decodables (confirm field names vs weather.timelines /
// weather.getAlerts; modeled tolerant so a shape drift degrades to empty,
// never crashes the card).

struct WeatherTimelines: Decodable {
    // VERIFIED against weather.timelines (weather.ts:766). The proc emits
    // SHORT keys + an envelope { source, available, fetchedAt, units, hourly,
    // daily }; we decode only hourly/daily. precipPct is already a rounded Int;
    // temp/hi/lo are Fahrenheit Doubles (units:"imperial").
    //   hourly: [{ t, temp, precipPct, weatherCode, condition }]
    //   daily:  [{ d, hi, lo, weatherCode, condition }]
    struct Hour: Decodable { let t: String?; let temp: Double?; let precipPct: Int?; let weatherCode: Int?; let condition: String? }
    struct Day: Decodable { let d: String?; let hi: Double?; let lo: Double?; let weatherCode: Int?; let condition: String? }
    let source: String?
    let available: Bool?
    let fetchedAt: String?
    let hourly: [Hour]?
    let daily: [Day]?

    var sourceAttribution: String? {
        AmbientWeatherSourcePolicy.attribution(for: source)
    }

    private static let iso = ISO8601DateFormatter()
    var hourPoints: [HourPoint] {
        (hourly ?? []).map {
            HourPoint(time: $0.t.flatMap(Self.iso.date(from:)),
                      tempF: WeatherNumeric.roundedInt($0.temp, allowed: WeatherNumeric.temperatureF),
                      weatherCode: $0.weatherCode ?? 0,
                      precipPct: $0.precipPct)
        }
    }
    var dayPoints: [DayPoint] {
        (daily ?? []).map {
            DayPoint(day: $0.d.flatMap(Self.iso.date(from:)),
                     highF: WeatherNumeric.roundedInt($0.hi, allowed: WeatherNumeric.temperatureF),
                     lowF: WeatherNumeric.roundedInt($0.lo, allowed: WeatherNumeric.temperatureF),
                     weatherCode: $0.weatherCode ?? 0)
        }
    }
}

/// Mirrors the weather.getAlerts `AlertOut` row (weather.ts).
struct WeatherAlertRow: Decodable {
    let id: String?
    let source: String?
    let eventType: String?
    let severity: String?
    let headline: String?
    let description: String?
    let onsetAt: String?
    let expiresAt: String?
    let detailsUrl: String?
    let issuingSource: String?
    let responseActions: [String]?
    let govFeedGap: Bool?
}
