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
        ScrollView {
            VStack(spacing: S.s3) {
                statusPill
                ZStack {
                    ring(progress: hos.current.cyclePct, color: .esangBlue, lineWidth: 5, inset: 0)
                    ring(progress: hos.current.windowPct, color: .esangAmber, lineWidth: 5, inset: 12)
                    ring(progress: hos.current.drivePct, color: .esangGreen, lineWidth: 5, inset: 24)
                    VStack(spacing: 0) {
                        Text(hos.current.driveHoursText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("DRIVE")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                hoursRow(label: "Drive",    value: hos.current.driveHoursText,    tint: .esangGreen)
                hoursRow(label: "Window",   value: hos.current.windowHoursText,   tint: .esangAmber)
                hoursRow(label: "Cycle",    value: minutes(hos.current.cycleRemainingMinutes), tint: .esangBlue)

                statusButtons
            }
            .padding(.vertical, S.s1)
        }
        .navigationTitle("HOS")
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: hos.current.status.symbol)
                .foregroundStyle(.white)
            Text(hos.current.status.label)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(LinearGradient.esangPrimary, in: Capsule())
        .foregroundStyle(.white)
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
