//
//  CanonicalOfflineRouteItineraryView.swift
//  EusoTrip
//
//  Read-only fallback for a fresh, server-signed Rail or Vessel route package.
//  The caller must obtain the package through CanonicalRoutePackageStore;
//  unverified, stale, wrong-account, and wrong-subject bytes never reach here.
//

import Foundation
import SwiftUI

struct CanonicalOfflineRouteItineraryView: View {
    let package: CanonicalRoutePackage

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LifecycleCard(accentGradient: true) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Brand.success)
                        Text("SIGNED OFFLINE \(modeLabel.uppercased()) ROUTE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(palette.textTertiary)
                    }

                    Text(distanceLabel)
                        .font(.system(size: 24, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)

                    HStack(spacing: Space.s2) {
                        if let durationLabel {
                            Text(durationLabel)
                        }
                        Text("\(package.segments.count) signed segment\(package.segments.count == 1 ? "" : "s")")
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                    Text(validityLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if let composition = OfflineMapProductionComposition.shared,
               package.mode == .rail || package.mode == .vessel {
                OfflineNativeCoverageMapSurfaceHost(
                    composition: composition,
                    offlineSnapshot: composition.owner.snapshot,
                    identity: .init(
                        mode: package.mode == .rail ? .rail : .vessel,
                        family: .operational,
                        theme: colorScheme == .dark ? .dark : .light
                    ),
                    journeyProjection: .serverCanonical(package)
                )
                .frame(minHeight: 260)
            }

            Text("OFFLINE ITINERARY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(palette.textTertiary)

            if package.instructions.isEmpty {
                LifecycleCard {
                    Text("The signed route contains geometry but no written instructions.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(package.instructions, id: \.sequence) { instruction in
                            HStack(alignment: .top, spacing: Space.s3) {
                                Text("\(instruction.sequence + 1)")
                                    .font(.system(size: 11, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(Brand.info)
                                    .frame(minWidth: 24, alignment: .leading)
                                Text(instruction.text)
                                    .font(EType.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Verified offline \(modeLabel) route")
    }

    private var modeLabel: String {
        switch package.mode {
        case .road:
            return "road"
        case .truck:
            return "truck"
        case .rail:
            return "rail"
        case .vessel:
            return "vessel"
        }
    }

    private var distanceLabel: String {
        let meters = Double(package.summary.distanceMeters)
        switch package.mode {
        case .vessel:
            return String(format: "%.0f nautical miles", meters / 1_852)
        case .road, .truck, .rail:
            return String(format: "%.0f miles", meters / 1_609.344)
        }
    }

    private var durationLabel: String? {
        guard let duration = package.summary.durationSeconds else { return nil }
        let hours = duration / 3_600
        let minutes = (duration % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var validityLabel: String {
        guard let validUntil = package.validUntil else {
            return "Freshness is rechecked before every offline use"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Valid through \(formatter.string(from: validUntil))"
    }
}
