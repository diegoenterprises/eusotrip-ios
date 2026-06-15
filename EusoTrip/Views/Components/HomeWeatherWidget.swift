//
//  HomeWeatherWidget.swift
//  EusoTrip — shared, always-visible home weather surface.
//
//  Founder report 2026-06-14: "and dont see the new weather widget … every
//  user role type." The v2/v3 bespoke `WeatherCard` was mounted behind a
//  `if let weather` gate on each home, so whenever the snapshot was nil —
//  location not yet granted (.notDetermined), a simulator with no fix, or a
//  momentary fetch miss — the entire widget vanished. Seven role homes had
//  no weather surface at all.
//
//  This is the single drop-in fix: `HomeWeatherWidget()` owns its own fetch
//  and renders an HONEST state for every outcome, so the weather surface is
//  ALWAYS present on every role home:
//
//    • data         → the shared `WeatherCard` (the real bespoke widget)
//    • loading      → a bespoke skeleton, so the slot is occupied instantly
//    • needsLocation→ an "Enable location" CTA that fires the system prompt
//    • unavailable  → an honest "Weather unavailable · Tap to retry" card
//
//  Zero fabrication (no invented readings — nil stays honest) and zero SF
//  Symbols (bespoke-weather doctrine: every glyph via WeatherIcons / shapes).
//
import SwiftUI
import CoreLocation
import UIKit

struct HomeWeatherWidget: View {
    /// Optional route-aware lane weather for an active load (driver
    /// dashboard passes this through); nil on every other role.
    var lane: LaneWeather? = nil

    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase {
        case loading
        case data(WeatherSnapshot)
        case needsLocation
        case unavailable
    }
    @State private var phase: Phase = .loading
    /// True once the first fetch resolves — gates the skeleton so a
    /// periodic/foreground refresh updates the card IN PLACE instead of
    /// flashing back to the loading state under the user.
    @State private var hasLoadedOnce = false

    /// Live auto-refresh cadence. Current conditions don't change
    /// second-to-second and the upstream sources (Tomorrow.io / WeatherKit
    /// / NWS) are rate-limited, so a 10-minute live tick — plus an instant
    /// refresh whenever the app returns to the foreground — is the right
    /// "real-time" behavior for a home weather surface.
    private let refreshInterval: UInt64 = 600 * 1_000_000_000

    /// Hard ceiling on the FIRST load (no cache). If the upstream chain
    /// (location + Tomorrow.io + WeatherKit/NWS/Open-Meteo fallbacks)
    /// stalls, the widget resolves to an honest state instead of sitting on
    /// the skeleton — no multi-minute lingering loads.
    private let firstLoadCeiling: UInt64 = 9 * 1_000_000_000

    init(lane: LaneWeather? = nil) {
        self.lane = lane
        // Seed from the last-good cache so the widget is NEVER blank on a
        // return visit — it shows the most recent REAL reading instantly
        // and refreshes in the background.
        let cached = WeatherService.cachedSnapshot
        _phase = State(initialValue: cached.map { Phase.data($0) } ?? .loading)
        _hasLoadedOnce = State(initialValue: cached != nil)
    }

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: phaseKey)
            // Initial fetch + periodic live refresh; SwiftUI cancels the
            // loop when the widget leaves the screen.
            .task { await autoRefreshLoop() }
            // Refresh the instant the app returns to the foreground so a
            // returning user never sees a stale reading.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refresh() }
                }
            }
    }

    // A small stable key so the cross-fade animates between states
    // without making `WeatherSnapshot` Equatable.
    private var phaseKey: Int {
        switch phase {
        case .loading: return 0
        case .data: return 1
        case .needsLocation: return 2
        case .unavailable: return 3
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .data(let snap):
            WeatherCard(snapshot: snap, lane: lane)
        case .loading:
            HomeWeatherSkeleton()
        case .needsLocation:
            HomeWeatherEnableLocationCard(onTap: handleEnableTap)
        case .unavailable:
            HomeWeatherUnavailableCard(onRetry: { Task { await refresh(force: true) } })
        }
    }

    /// Initial load, then a live refresh every `refreshInterval`. Runs
    /// inside `.task`, so SwiftUI cancels it when the widget disappears.
    private func autoRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: refreshInterval)
            if Task.isCancelled { break }
            await refresh()
        }
    }

    private func refresh(force: Bool = false) async {
        // Show the skeleton only on the FIRST load (or an explicit retry).
        // A live/foreground refresh updates the card in place so it never
        // flashes back to a skeleton under the user.
        if force || !hasLoadedOnce { phase = .loading }
        // Bound the FIRST load so a stalled upstream chain can't leave the
        // skeleton spinning for minutes; once we have data the live refresh
        // runs unbounded in the background (it never shows a skeleton).
        let snap = hasLoadedOnce
            ? await WeatherService.shared.fetchCurrent()
            : await fetchBounded(ceiling: firstLoadCeiling)
        if let snap {
            phase = .data(snap)
            hasLoadedOnce = true
            return
        }
        // Honest reason-aware empty state — distinguish "we never asked for
        // location" from "granted but momentarily unavailable".
        switch WeatherService.shared.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            phase = .needsLocation
        default:
            // A transient miss AFTER we already had data keeps the last-good
            // card on screen; only show "unavailable" if we never had data.
            if !hasLoadedOnce { phase = .unavailable }
        }
    }

    /// `fetchCurrent()` raced against a hard time ceiling. Whichever
    /// finishes first wins; the loser is cancelled. Guarantees the first
    /// load resolves promptly instead of lingering on the skeleton if the
    /// upstream chain stalls.
    private func fetchBounded(ceiling: UInt64) async -> WeatherSnapshot? {
        await withTaskGroup(of: WeatherSnapshot?.self) { group in
            group.addTask { await WeatherService.shared.fetchCurrent() }
            group.addTask {
                try? await Task.sleep(nanoseconds: ceiling)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func handleEnableTap() {
        let status = WeatherService.shared.authorizationStatus
        if status == .notDetermined {
            WeatherService.shared.requestPermissionIfNeeded()
            Task {
                // Give CoreLocation a beat to deliver the first fix after
                // the user grants, then re-fetch into the data state.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await refresh(force: true)
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Enable-location CTA (bespoke, zero SF Symbols)

private struct HomeWeatherEnableLocationCard: View {
    var onTap: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 48, height: 48)
                    WeatherIcons.utility(.pin, size: 22, tint: .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location for live weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Grant location access to see local conditions, visibility and route weather alerts.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                WeatherIcons.utility(.chev, size: 13, tint: palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enable location for live weather")
        .accessibilityHint("Grants location access so the weather card can show local conditions.")
    }
}

// MARK: - Honest unavailable state (bespoke)

private struct HomeWeatherUnavailableCard: View {
    var onRetry: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: onRetry) {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(palette.bgCardSoft)
                        .frame(width: 48, height: 48)
                    WeatherIcons.utility(.alert, size: 20, tint: palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weather unavailable")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Couldn't reach a live reading right now. Tap to retry.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                WeatherIcons.utility(.chev, size: 13, tint: palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weather unavailable. Tap to retry.")
    }
}

// MARK: - Loading skeleton (bespoke shimmer)

private struct HomeWeatherSkeleton: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Circle()
                .fill(palette.bgCardSoft)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 8) {
                bar(width: 120)
                bar(width: 180)
                bar(width: 90)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .overlay(shimmerSweep.clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Loading weather")
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(width: width, height: 10)
    }

    @ViewBuilder private var shimmerSweep: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, palette.textPrimary.opacity(0.06), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: shimmer ? geo.size.width : -geo.size.width * 0.5)
            }
            .allowsHitTesting(false)
        }
    }
}
