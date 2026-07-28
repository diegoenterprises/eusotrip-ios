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
//    • loading      → a bespoke "Updating weather…" placeholder
//    • needsLocation→ an "Enable location" CTA that fires the system prompt
//
//  ALWAYS-ON doctrine (founder mandate 2026-06-19): the widget must NEVER
//  show "unavailable"/"not available" — not on a screen revisit, a cold
//  launch, a fetch error, or with no network. Two guarantees enforce this:
//
//    1. The last-good REAL snapshot is PERSISTED to disk
//       (`WeatherService.cachedSnapshot`), so a COLD launch seeds straight
//       into `.data` from the most recent reading instead of a skeleton.
//    2. `refresh()` NEVER flips to a "no data" state while ANY cache exists
//       (memory or disk): a failed fetch KEEPS the last-good card on screen
//       and schedules a silent faster retry.
//
//  The "no data yet" placeholder is reachable ONLY on a brand-new install
//  whose very first fetch failed AND that has no persisted cache — and even
//  then it renders a soft, branded "Updating weather…" placeholder that
//  keeps silently retrying. The word "unavailable" can never render.
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

    /// Destination-hero policy (user direction 2026-04-24): while a load is
    /// active the hero shows the DESTINATION conditions (HERE Destination
    /// Weather), not the parked-here reading. The driver dashboard passes
    /// its resolved destination snapshot here; when non-nil it wins over
    /// the widget's own local fetch. Nil (every other role / between
    /// loads) → the widget's own local snapshot renders as before.
    var preferredSnapshot: WeatherSnapshot? = nil

    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private enum Phase {
        case loading
        case data(WeatherSnapshot)
        case needsLocation
        // Reachable ONLY on a brand-new install whose first fetch failed
        // with no persisted cache. Renders the soft "Updating weather…"
        // placeholder (NEVER the word "unavailable") and keeps retrying.
        case updating
    }
    @State private var phase: Phase = .loading
    /// True once the first fetch resolves — gates the skeleton so a
    /// periodic/foreground refresh updates the card IN PLACE instead of
    /// flashing back to the loading state under the user.
    @State private var hasLoadedOnce = false

    /// Live auto-refresh cadence. Current conditions don't change
    /// second-to-second and the upstream sources (Apple WeatherKit / WeatherKit
    /// / NWS) are rate-limited, so a 10-minute live tick — plus an instant
    /// refresh whenever the app returns to the foreground — is the right
    /// "real-time" behavior for a home weather surface.
    private let refreshInterval: UInt64 = 600 * 1_000_000_000

    /// Hard ceiling on the FIRST load (no cache). If the upstream chain
    /// (location + Apple WeatherKit + WeatherKit/NWS/Open-Meteo fallbacks)
    /// stalls, the widget resolves to an honest state instead of sitting on
    /// the skeleton — no multi-minute lingering loads.
    private let firstLoadCeiling: UInt64 = 9 * 1_000_000_000

    init(lane: LaneWeather? = nil, preferredSnapshot: WeatherSnapshot? = nil) {
        self.lane = lane
        self.preferredSnapshot = preferredSnapshot
        // Seed from the last-good cache so the widget is NEVER blank on a
        // return visit — it shows the most recent REAL reading instantly
        // (even a stale one, with its honest "updated Nh ago" line) and
        // refreshes in the background.
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
            .onReceive(NotificationCenter.default.publisher(for: .eusoWeatherAuthorizationChanged)) { _ in
                Task { await refresh(force: true) }
            }
    }

    // A small stable key so the cross-fade animates between states
    // without making `WeatherSnapshot` Equatable.
    private var phaseKey: Int {
        switch phase {
        case .loading: return 0
        case .data: return 1
        case .needsLocation: return 2
        case .updating: return 3
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .data(let snap):
            // Destination-hero policy: the caller's active-load destination
            // snapshot wins over the local reading while a load is active.
            WeatherCard(snapshot: preferredSnapshot ?? snap, lane: lane)
        case .loading:
            HomeWeatherSkeleton()
        case .needsLocation:
            HomeWeatherEnableLocationCard(onTap: handleEnableTap)
        case .updating:
            HomeWeatherUpdatingCard {
                Task { await refresh(force: true) }
            }
        }
    }

    /// Initial load, then a live refresh every `refreshInterval`. Runs
    /// inside `.task`, so SwiftUI cancels it when the widget disappears.
    private func autoRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            // Back off briefly after a FAILED fetch so a transient weather
            // outage self-heals in ~45s instead of forcing the full 600s wait
            // (or an app restart) — founder feedback #20. Applies to the
            // brand-new-install `.updating` placeholder too, so it keeps
            // silently retrying until the very first reading lands.
            let failed: Bool = { if case .updating = phase { return true } else { return false } }()
            let wait: UInt64 = failed ? 45 * 1_000_000_000 : refreshInterval
            try? await Task.sleep(nanoseconds: wait)
            if Task.isCancelled { break }
            await refresh()
        }
    }

    private func refresh(force: Bool = false) async {
        // The persisted/in-memory last-good snapshot — survives a cold
        // launch, so on EVERY refresh (including the very first of a fresh
        // process) we know whether weather has ever loaded for this device.
        let cache = WeatherService.cachedSnapshot

        // If we have ANY cache (memory or disk), paint it INSTANTLY and
        // never fall to a skeleton — even an explicit retry refreshes the
        // card in place over the last-good reading.
        if let cache, !hasLoadedOnce {
            phase = .data(cache)
            hasLoadedOnce = true
        } else if !hasLoadedOnce {
            // No cache at all (brand-new install) → the ONLY time we show
            // the loading placeholder. `force` deliberately does NOT reach
            // this branch: a force-refresh (auth-change notification fires
            // on every process start) used to drop a VALID on-screen card
            // to the skeleton mid-session — force is purely a fetch
            // trigger now, and the .needsLocation → granted transition
            // still recovers because the fetch result sets `.data`.
            phase = .loading
        }

        // Bound the FIRST load so a stalled upstream chain can't leave the
        // placeholder spinning for minutes; once we have data the live
        // refresh runs unbounded in the background (it never shows loading).
        let snap = hasLoadedOnce
            ? await WeatherService.shared.fetchCurrent()
            : await fetchBounded(ceiling: firstLoadCeiling)
        if let snap {
            phase = .data(snap)
            hasLoadedOnce = true
            return
        }

        // Fetch failed. NEVER leave the weather surface blank/"unavailable":
        //  • If a cache exists (memory or disk), KEEP showing it. The
        //    auto-refresh loop already retries faster on a miss.
        let liveCache = WeatherService.cachedSnapshot
        if let liveCache {
            phase = .data(liveCache)
            hasLoadedOnce = true
            return
        }
        //  • No cache AND we've truly never loaded. Distinguish a real,
        //    actionable permission ask from a transient first-fetch miss.
        switch WeatherService.shared.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            phase = .needsLocation
        default:
            // Granted but the brand-new install's first fetch missed: show
            // the soft "Updating weather…" placeholder (NOT "unavailable")
            // and keep silently retrying until the first reading lands.
            if !hasLoadedOnce { phase = .updating }
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
            DriverLocationResolver.shared.requestPermissionIfNeeded()
            Task {
                // Give CoreLocation a beat to deliver the first fix after
                // the user grants, then re-fetch into the data state.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await refresh(force: true)
            }
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
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

// MARK: - Soft "Updating weather…" placeholder (bespoke)
//
// The ONLY non-data, non-permission state, and it is reachable ONLY on a
// brand-new install whose first fetch missed with NO persisted cache.
// Founder mandate (2026-06-19): the widget must NEVER show "unavailable"/
// "not available". This is deliberately framed as an in-progress update,
// not an error — a gentle last-known weather glyph + shimmer that keeps
// silently retrying (the auto-refresh loop backs off to ~45s in this
// state). It also supports an immediate user retry while the background
// refresh loop continues.

private struct HomeWeatherUpdatingCard: View {
    let onRetry: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        Button(action: onRetry) {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal.opacity(0.18))
                        .frame(width: 48, height: 48)
                    WeatherGlyph(kind: .cloudy)
                        .frame(width: 26, height: 26)
                        .opacity(0.85)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconnecting weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap to retry live local conditions.")
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
        .overlay(shimmerSweep.clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Reconnect weather")
        .accessibilityHint("Retries live local weather now.")
    }

    @ViewBuilder private var shimmerSweep: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, palette.textPrimary.opacity(0.05), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: shimmer ? geo.size.width : -geo.size.width * 0.5)
            }
            .allowsHitTesting(false)
        }
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
