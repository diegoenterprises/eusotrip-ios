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

    private enum Phase {
        case loading
        case data(WeatherSnapshot)
        case needsLocation
        case unavailable
    }
    @State private var phase: Phase = .loading

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: phaseKey)
            .task { await load() }
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
            HomeWeatherUnavailableCard(onRetry: { Task { await load(force: true) } })
        }
    }

    private func load(force: Bool = false) async {
        if force { phase = .loading }
        let snap = await WeatherService.shared.fetchCurrent()
        if let snap {
            phase = .data(snap)
            return
        }
        // Honest reason-aware empty state — distinguish "we never asked
        // for location" from "granted but momentarily unavailable".
        switch WeatherService.shared.authorizationStatus {
        case .notDetermined, .denied, .restricted:
            phase = .needsLocation
        default:
            phase = .unavailable
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
                await load(force: true)
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
