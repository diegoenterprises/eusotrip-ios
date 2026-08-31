//
//  HOSView.swift
//  EusoTrip Watch App
//
//  Hours-of-service detail with three progress rings and four tap targets
//  for status changes (Off / Sleeper / Drive / On-duty).
//

import SwiftUI

struct HOSView: View {
    private enum SyncResult {
        case sent
        case queued
        case unavailable

        var message: String {
            switch self {
            case .sent: return "Sent. Open the HOS notification on iPhone."
            case .queued: return "Queued for iPhone."
            case .unavailable: return "iPhone bridge unavailable. Open EusoTrip on iPhone."
            }
        }

        var symbol: String {
            switch self {
            case .sent: return "iphone.and.arrow.forward"
            case .queued: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
            case .unavailable: return "exclamationmark.triangle.fill"
            }
        }
    }

    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore

    @State private var isSyncing = false
    @State private var syncResult: SyncResult?

    var body: some View {
        Group {
            if let observation {
                verifiedClock(observation)
            } else {
                unavailableClock
            }
        }
        .toolbar(.hidden)
        .watchEdgeGlow()
        .task {
            guard observation == nil, auth.isSignedIn else { return }
            await hos.refresh(auth: auth)
        }
    }

    private var observation: WatchHOS? { hos.currentObservation }

    private func verifiedClock(_ observation: WatchHOS) -> some View {
        ZStack {
            ScrollView {
                VStack(spacing: S.s3) {
                    statusPill(observation)
                    evidenceState(observation)

                    ZStack {
                        ring(progress: observation.cyclePct, color: .esangBlue, lineWidth: 6, inset: 0)
                        ring(progress: observation.windowPct, color: .esangAmber, lineWidth: 6, inset: 16)
                        ring(progress: observation.drivePct, color: .esangGreen, lineWidth: 6, inset: 32)
                        VStack(spacing: 0) {
                            Text(observation.driveHoursText)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("DRIVE")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 168, height: 168)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Drive time remaining, \(observation.driveHoursText)")

                    hoursRow(label: "Drive", value: observation.driveHoursText, tint: .esangGreen)
                    hoursRow(label: "Window", value: observation.windowHoursText, tint: .esangAmber)
                    hoursRow(label: "Cycle", value: minutes(observation.cycleRemainingMinutes), tint: .esangBlue)

                    statusButtons
                    complianceFooter
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            ModularTickBezel(
                corners: .init(
                    topLeading: "DRV \(observation.driveHoursText)",
                    topTrailing: observation.status.short.uppercased(),
                    bottomLeading: "WIN \(observation.windowHoursText)",
                    bottomTrailing: "CYCLE"
                )
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .all)
    }

    private var unavailableClock: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 7) {
                    HStack(spacing: 9) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Circle().strokeBorder(Color.esangAmber.opacity(0.5), lineWidth: 1))
                            Image(systemName: "shield.slash")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.esangAmber)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("HOS EVIDENCE")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(Color.esangAmber)
                            Text("Clock unavailable")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        Spacer(minLength: 0)
                    }

                    Text("No current ELD observation. Duty changes stay locked until GPS and server evidence agree.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        evidenceChip(
                            label: "ACCOUNT",
                            value: auth.isSignedIn ? "READY" : "SIGN IN",
                            ready: auth.isSignedIn
                        )
                        evidenceChip(
                            label: "IPHONE",
                            value: connectivity.isReachable ? "LINKED" : "AWAY",
                            ready: connectivity.isReachable
                        )
                    }

                    Button {
                        Task { await requestEvidenceSync() }
                    } label: {
                        HStack(spacing: 7) {
                            if isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking evidence")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            } else if let syncResult {
                                Image(systemName: syncResult.symbol)
                                    .font(.system(size: 12, weight: .bold))
                                Text(syncResult.message)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Request HOS sync")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: syncResult == nil ? 38 : 44)
                        .foregroundStyle(.white)
                        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing)
                    .accessibilityLabel(
                        syncResult.map { "\($0.message) Double tap to retry." }
                            ?? (isSyncing ? "Checking HOS evidence" : "Request HOS sync")
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            ModularTickBezel(
                corners: .init(
                    topLeading: "HOS",
                    topTrailing: "EVIDENCE",
                    bottomLeading: connectivity.isReachable ? "PHONE LINKED" : "PHONE AWAY",
                    bottomTrailing: "LOCKED"
                )
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(.container, edges: .all)
        .accessibilityElement(children: .contain)
    }

    private func statusPill(_ observation: WatchHOS) -> some View {
        HStack(spacing: 6) {
            Image(systemName: observation.status.symbol)
                .foregroundStyle(.white)
            Text(observation.status.label)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(LinearGradient.esangPrimary, in: Capsule())
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func evidenceState(_ observation: WatchHOS) -> some View {
        Text("\(observation.source ?? "Source unavailable") · observed \(observation.observedAt?.formatted(date: .omitted, time: .shortened) ?? "time unavailable")")
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        if let error = hos.lastMutationError {
            Text(error)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    private func evidenceChip(label: String, value: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Circle()
                    .fill(ready ? Color.esangGreen : Color.esangAmber)
                    .frame(width: 5, height: 5)
                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    @MainActor
    private func requestEvidenceSync() async {
        guard !isSyncing else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            isSyncing = true
            syncResult = nil
        }

        connectivity.requestAuthMirror()
        if auth.isSignedIn {
            await hos.refresh(auth: auth)
        }

        guard hos.currentObservation == nil else {
            isSyncing = false
            return
        }

        let dispatch = connectivity.requestPhoneActivation(
            transcript: nil,
            reply: "Review and synchronize HOS evidence in EusoTrip.",
            destination: .hos
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            switch dispatch {
            case .sent:
                syncResult = .sent
            case .queued:
                syncResult = .queued
            case .unavailable:
                syncResult = .unavailable
            }
            isSyncing = false
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
                        hos.current.status == s
                            ? Color.esangBlue
                            : Color.esangCard,
                        in: RoundedRectangle(cornerRadius: R.sm)
                    )
                    .foregroundStyle(hos.current.status == s ? .white : .white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func minutes(_ m: Int) -> String {
        let h = m / 60
        let mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
