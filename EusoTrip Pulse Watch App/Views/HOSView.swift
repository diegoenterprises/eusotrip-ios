//
//  HOSView.swift
//  EusoTrip Watch App
//
//  Hours-of-service detail with three progress rings and four tap targets
//  for status changes (Off / Sleeper / Drive / On-duty).
//

import SwiftUI

struct HOSView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: S.s3) {
                    statusPill
                    evidenceState
                    ZStack {
                        ring(progress: observation?.cyclePct ?? 0, color: .esangBlue, lineWidth: 6, inset: 0)
                        ring(progress: observation?.windowPct ?? 0, color: .esangAmber, lineWidth: 6, inset: 16)
                        ring(progress: observation?.drivePct ?? 0, color: .esangGreen, lineWidth: 6, inset: 32)
                        VStack(spacing: 0) {
                            Text(observation?.driveHoursText ?? "—")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("DRIVE")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Grow the rings so they paint across the full
                    // wrist face like the orb on Home, instead of
                    // reading as a letterboxed inset card.
                    .frame(width: 168, height: 168)

                    hoursRow(label: "Drive",    value: observation?.driveHoursText ?? "—", tint: .esangGreen)
                    hoursRow(label: "Window",   value: observation?.windowHoursText ?? "—", tint: .esangAmber)
                    hoursRow(label: "Cycle",    value: minutes(observation?.cycleRemainingMinutes), tint: .esangBlue)

                    statusButtons

                    // Compliance anchor on the HOS surface — the watch's
                    // HOS screen is the single most-viewed compliance
                    // surface on the wrist, so we pin the March 23, 2026
                    // eDVIR rule citation here. Full rule detail + ack
                    // live on the phone (MeComplianceView's shared
                    // ComplianceStore); this footer is the wrist-side
                    // signal that the rule is active and governs the
                    // DVIR flow the driver just completed.
                    complianceFooter
                }
                // Inner padding zeroed on horizontal so the rings + bezel
                // ticks meet the actual wrist edge. Keep a thin vertical
                // crumb so the status pill doesn't kiss the system clock.
                .padding(.horizontal, 0)
                .padding(.vertical, S.s1)
                .frame(maxWidth: .infinity)
            }

            // Modular Ultra bezel — tick rails + HOS corner labels.
            // Live values so the driver sees the four summary numbers
            // even before the inner rings render.
            ModularTickBezel(
                corners: .init(
                    topLeading:     "DRV \(observation?.driveHoursText ?? "—")",
                    topTrailing:    observation?.status.short.uppercased() ?? "UNVERIFIED",
                    bottomLeading:  "WIN \(observation?.windowHoursText ?? "—")",
                    bottomTrailing: "CYCLE"
                )
            )
            .allowsHitTesting(false)
        }
        // Drop the navigationTitle — without a wrapping NavigationStack
        // it just reserved a chrome strip at the top that letterboxed
        // the whole tab against the orb's full-bleed look on Home.
        .toolbar(.hidden)
        .ignoresSafeArea(.container, edges: .all)
        // Same radial halo HomeView uses behind the orb so the watch's
        // rounded corners feel lit, not clipped against rectangular
        // foreground content.
        .watchEdgeGlow()
    }

    private var observation: WatchHOS? { hos.currentObservation }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: observation?.status.symbol ?? "questionmark.circle")
                .foregroundStyle(.white)
            Text(observation?.status.label ?? "HOS unavailable")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(LinearGradient.esangPrimary, in: Capsule())
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var evidenceState: some View {
        if let observation {
            Text("\(observation.source ?? "Source unavailable") · observed \(observation.observedAt?.formatted(date: .omitted, time: .shortened) ?? "time unavailable")")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Current sourced HOS evidence is unavailable. Duty controls require live GPS and server confirmation.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        if let error = hos.lastMutationError {
            Text(error)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Compliance footer — Mar 23, 2026 wave anchor

    /// Slim compliance signal rendered at the bottom of the HOS card.
    /// Single-line, gradient leading dot, single citation. Designed to
    /// echo the iPhone's `ComplianceInlineChip(tag: .eDvir)` so the
    /// driver sees the same regulatory anchor on wrist and phone.
    private var complianceFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient.esangPrimary)
                .frame(width: 4, height: 4)
            Text("eDVIR · 49 CFR § 396")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("MAR 23, 2026")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.top, S.s1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Electronic DVIR rule, 49 CFR section 396, effective March 23, 2026")
    }

    @ViewBuilder
    private func ring(progress: Double, color: Color, lineWidth: CGFloat, inset: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.20), lineWidth: lineWidth)
                .padding(inset)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(inset)
        }
    }

    @ViewBuilder
    private func hoursRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var statusButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(HOSStatus.allCases, id: \.self) { s in
                Button {
                    Task { await hos.changeStatus(to: s, auth: auth, connectivity: connectivity) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: s.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(s.short)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        observation?.status == s
                            ? Color.esangBlue
                            : Color.esangCard,
                        in: RoundedRectangle(cornerRadius: R.sm)
                    )
                    .foregroundStyle(observation?.status == s ? .white : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func minutes(_ m: Int?) -> String {
        guard let m else { return "—" }
        let h = m / 60
        let mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
