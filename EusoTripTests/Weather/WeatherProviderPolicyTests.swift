import XCTest
@testable import EusoTrip

final class WeatherProviderPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func segment(
        loadId: String = "LD-2042",
        source: String? = "here",
        sourceLoadId: String? = "2042",
        computedAt: Date? = Date(timeIntervalSince1970: 1_999_999_940),
        drivers: [WeatherSnapshot.Driver] = [
            .init(field: "VISIBILITY", value: "8 mi")
        ]
    ) -> WeatherSnapshot.LaneImpactSegment {
        WeatherSnapshot.LaneImpactSegment(
            loadId: loadId,
            mode: .truck,
            riskTier: .watch,
            headline: "Weather risk",
            peakLeg: nil,
            drivers: drivers,
            recommendation: nil,
            computedAt: computedAt,
            source: source,
            sourceLoadId: sourceLoadId,
            route: "Austin, TX -> Dallas, TX",
            pickupTime: nil,
            etaDelayMin: nil,
            esangSuggestion: nil
        )
    }

    private func snapshot() -> WeatherSnapshot {
        WeatherSnapshot(
            city: "Austin, TX",
            tempF: 80,
            windMph: 8,
            visibilityMi: 10,
            condition: "Clear",
            symbol: "sun.max.fill",
            nextAlert: nil,
            accent: .calm
        )
    }

    func testFreshHERECustomerRouteCanRenderAndGroundESANG() {
        let value = segment()

        XCTAssertTrue(value.isRenderableRouteWeather(at: now))
        XCTAssertTrue(value.canRequestGroundedESang(at: now))
        XCTAssertEqual(value.routeWeatherAuthority, .here)
    }

    func testAmbientProvidersCannotBecomeRouteIntelligence() {
        let weatherKit = segment(source: "weatherkit")
        let openWeather = segment(source: "openweather")

        XCTAssertEqual(weatherKit.routeWeatherAuthority, .weatherKitFallback)
        XCTAssertFalse(weatherKit.isRenderableRouteWeather(at: now))
        XCTAssertFalse(weatherKit.canRequestGroundedESang(at: now))
        XCTAssertEqual(openWeather.routeWeatherAuthority, .rejected)
        XCTAssertFalse(openWeather.isRenderableRouteWeather(at: now))
    }

    func testStaleFutureAndInternalTestRowsStayOffLiveSurfaces() {
        XCTAssertFalse(segment(computedAt: now.addingTimeInterval(-31 * 60))
            .isRenderableRouteWeather(at: now))
        XCTAssertFalse(segment(computedAt: now.addingTimeInterval(6 * 60))
            .isRenderableRouteWeather(at: now))
        XCTAssertFalse(segment(loadId: "AP-TEST-0020")
            .isRenderableRouteWeather(at: now))
    }

    func testESANGGroundingKeyChangesWithProviderReduction() {
        let earlier = segment(computedAt: now.addingTimeInterval(-120))
        let newer = segment(computedAt: now.addingTimeInterval(-60))

        XCTAssertNotEqual(earlier.esangGroundingKey, newer.esangGroundingKey)
    }

    func testESANGRequiresAuthenticatedSourceIdentifier() {
        let displayOnly = segment(sourceLoadId: nil)

        XCTAssertTrue(displayOnly.isRenderableRouteWeather(at: now))
        XCTAssertFalse(displayOnly.canRequestGroundedESang(at: now))
        XCTAssertNil(displayOnly.analysisLoadId)
    }

    func testLaneEndpointsRequireFreshHEREObservations() {
        var liveHERE = snapshot()
        liveHERE.dataSource = .here
        liveHERE.observedAt = now.addingTimeInterval(-60)

        var ambient = snapshot()
        ambient.dataSource = .openWeather
        ambient.observedAt = now.addingTimeInterval(-60)

        let lane = LaneWeather(
            origin: .init(role: "PICKUP", city: "Austin, TX", snapshot: liveHERE),
            destination: .init(role: "DELIVERY", city: "Dallas, TX", snapshot: ambient),
            isTempControlled: false
        )

        let filtered = lane.live(at: now)
        XCTAssertNotNil(filtered?.origin)
        XCTAssertNil(filtered?.destination)

        liveHERE.observedAt = now.addingTimeInterval(-31 * 60)
        let staleLane = LaneWeather(
            origin: .init(role: "PICKUP", city: "Austin, TX", snapshot: liveHERE),
            destination: nil,
            isTempControlled: false
        )
        XCTAssertNil(staleLane.live(at: now))
    }

    func testStaleDaylightHintCannotPaintSunAtAustinNight() throws {
        let displayDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-14T06:57:00Z")
        )
        var value = snapshot()
        value.latitude = 30.2672
        value.longitude = -97.7431
        value.timezoneId = "America/Chicago"
        value.observedAt = displayDate.addingTimeInterval(-3600)
        value.isNightHint = false

        XCTAssertEqual(value.displaySolarState(at: displayDate), .night)
    }

    func testFreshProviderNightConditionWinsAtTheObservationInstant() {
        var value = snapshot()
        value.latitude = 30.2672
        value.longitude = -97.7431
        value.timezoneId = "America/Chicago"
        value.observedAt = now
        value.isNightHint = true

        XCTAssertEqual(value.displaySolarState(at: now), .night)
    }

    func testProviderSunWindowUsesTheLocationTimezoneOnLaterDays() throws {
        let formatter = ISO8601DateFormatter()
        let providerDay = try XCTUnwrap(formatter.date(from: "2026-08-14T00:00:00Z"))
        let nextNight = try XCTUnwrap(formatter.date(from: "2026-08-15T06:30:00Z"))
        var value = snapshot()
        value.timezoneId = "America/Chicago"
        value.sunriseAt = providerDay.addingTimeInterval(11.5 * 3600)
        value.sunsetAt = providerDay.addingTimeInterval(25 * 3600)

        XCTAssertEqual(value.solarState(at: nextNight), .night)
    }

    func testMissingSolarEvidenceRemainsUnknown() {
        let value = snapshot()
        XCTAssertEqual(value.solarState(at: now), .unknown)
        XCTAssertEqual(value.dayPart(at: now), .night)
    }

    func testUnsafeProviderNumericsNeverCrossIntegerBoundary() {
        XCTAssertNil(WeatherNumeric.roundedInt(.nan))
        XCTAssertNil(WeatherNumeric.roundedInt(.infinity))
        XCTAssertNil(WeatherNumeric.roundedInt(-.infinity))
        XCTAssertNil(WeatherNumeric.roundedInt(Double.greatestFiniteMagnitude))
        XCTAssertNil(WeatherNumeric.roundedInt(700, allowed: WeatherNumeric.windMph))
        XCTAssertNil(WeatherNumeric.finite(.nan))
        XCTAssertNil(WeatherNumeric.nonnegativeFinite(-0.01))
    }

    func testInvalidSnapshotMetricsRenderAsUnknown() {
        var value = WeatherSnapshot(
            city: "Austin, TX",
            tempF: 999,
            windMph: 601,
            visibilityMi: -1,
            condition: "Unknown",
            symbol: "cloud.fill",
            nextAlert: nil,
            accent: .calm
        )
        value.feelsLikeF = -201
        value.humidityPct = 101
        value.uvIndex = -1
        value.precipChancePct = 101

        XCTAssertEqual(value.tempDisplay, "—")
        XCTAssertEqual(value.feelsLikeDisplay, "—")
        XCTAssertEqual(value.humidityDisplay, "—")
        XCTAssertEqual(value.windDisplay, "—")
        XCTAssertEqual(value.visibilityDisplay, "—")
        XCTAssertEqual(value.uvDisplay, "—")
        XCTAssertEqual(value.precipChanceDisplay, "—")
    }

    func testNonFiniteMinuteAndDailyPrecipitationRemainUnknown() {
        let minuteForecast = WeatherSnapshot.NextHourPrecip(
            forecastStart: now,
            forecastEnd: now.addingTimeInterval(3600),
            minutes: [
                .init(
                    date: now.addingTimeInterval(300),
                    precipChancePct: nil,
                    intensityMmPerHour: .nan
                )
            ],
            summaries: []
        )
        let day = WeatherSnapshot.DailyForecast(
            date: now,
            weekdayLabel: "Today",
            highF: 80,
            lowF: 70,
            symbol: "cloud.fill",
            condition: "Unknown",
            precipChance: .infinity
        )

        XCTAssertNil(minuteForecast.displayLine)
        XCTAssertNil(day.precipDisplay)
    }

    func testMissingModeAndRiskRemainUnknown() {
        XCTAssertEqual(WeatherMode(server: nil), .unknown)
        XCTAssertEqual(WeatherMode(server: "air"), .unknown)
        XCTAssertEqual(LaneRiskTier(server: nil), .unknown)
        XCTAssertEqual(LaneRiskTier(server: "unrated"), .unknown)
        XCTAssertFalse(LaneRiskTier.unknown.isActionable)
    }

    func testInvalidTimelineRowsAreDroppedInsteadOfDefaulted() {
        let timeline = WeatherTimelines(
            source: "weatherkit",
            available: true,
            fetchedAt: nil,
            hourly: [
                .init(
                    t: "2026-08-23T12:00:00Z",
                    temp: .nan,
                    precipPct: 50,
                    weatherCode: 1000,
                    condition: "Clear"
                ),
                .init(
                    t: "2026-08-23T13:00:00Z",
                    temp: 82,
                    precipPct: 150,
                    weatherCode: nil,
                    condition: nil
                )
            ],
            daily: [
                .init(
                    d: "2026-08-23T00:00:00Z",
                    hi: .infinity,
                    lo: 70,
                    weatherCode: 1000,
                    condition: "Clear"
                )
            ]
        )

        XCTAssertTrue(timeline.hourPoints.isEmpty)
        XCTAssertTrue(timeline.dayPoints.isEmpty)
    }

    func testUnknownWeatherCodeKeepsSkyConditionUnknown() {
        XCTAssertEqual(SkyConditionV2(weatherCode: 0), .unknown)
        XCTAssertEqual(SkyConditionV2(weatherCode: 999_999), .unknown)
    }
}
