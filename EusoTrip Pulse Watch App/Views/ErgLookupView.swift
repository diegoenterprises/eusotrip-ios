//
//  ErgLookupView.swift
//  EusoTrip Watch App
//
//  Phase 3 — on-wrist ERG 2024 lookup for hazmat drivers. Resolves
//  UN numbers + proper shipping names from the bundled ERG database,
//  surfaces the Guide page + PAD distances (for immediate action at
//  the scene of an incident).
//
//  For detailed protocols the driver is always pointed at the iPhone
//  surface — the watch is strictly for first-moment reference.
//

import SwiftUI
import WatchKit

struct ErgLookupView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var selected: ErgEntry?

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                Text("ERG 2024")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                // Voice-dictation-backed text field on watch.
                TextField("UN# or name", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(7)
                    .frame(maxWidth: .infinity)
                    .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))

                if let entry = selected {
                    entryCard(entry)
                } else {
                    let results = ErgDatabase.shared.search(query: query)
                    if results.isEmpty && !query.isEmpty {
                        Text("No match for “\(query)”")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } else {
                        ForEach(results) { entry in
                            Button {
                                WKInterfaceDevice.current().play(.click)
                                selected = entry
                            } label: {
                                resultRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    connectivity.requestPhoneActivation(
                        transcript: "open ERG on iPhone",
                        reply: "Opening full ERG on your iPhone."
                    )
                    dismiss()
                } label: {
                    Label("Full ERG on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(S.s2)
        }
        .navigationTitle("ERG")
        // Guide-page pills + hazmat-yellow badges sit at the edges;
        // clip to the bezel so nothing sneaks past the rounded corner.
        .clipShape(ContainerRelativeShape())
    }

    @ViewBuilder
    private func resultRow(_ entry: ErgEntry) -> some View {
        HStack(spacing: 6) {
            Text(entry.un)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.esangHazmat)
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(2)
                Text("Guide \(entry.guide)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func entryCard(_ entry: ErgEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.un)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.esangHazmat)
                Spacer()
                Text("Guide \(entry.guide)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.esangHazmat, in: Capsule())
                    .foregroundStyle(.black)
            }
            Text(entry.name)
                .font(.system(size: 12, weight: .semibold))
            if let placard = entry.placard {
                Text(placard)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Divider().background(Color.esangBorder)
            if let response = entry.emergencyResponse {
                Text("IMMEDIATE ACTION")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(response)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let health = entry.healthHazards {
                Text("HEALTH HAZARDS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(health)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
            }
            if let pad = entry.protectiveActionDistance {
                Divider().background(Color.esangBorder)
                Text("PAD — LARGE SPILL")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Isolate \(pad.largeSpillIsolationFeet) ft")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.esangAmber)
                    Spacer()
                    Text(String(format: "Protect %.1f mi", pad.largeSpillProtectiveMiles))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.esangDanger)
                }
            }
            Button {
                selected = nil
            } label: {
                Text("Back")
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))
    }
}
