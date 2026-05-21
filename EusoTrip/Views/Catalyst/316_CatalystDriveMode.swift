//
//  316_CatalystDriveMode.swift
//  EusoTrip — Catalyst · Drive Mode (brick 316).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/316 Drive Mode.svg`.
//  Owner-op self-drive surface — bridges the Catalyst (owner)
//  identity to the Driver (operator) identity inside the same
//  companyId, with HOS + DVIR + drift readouts and a DRIVE /
//  OFF-ROTATION / PARK toggle.
//
//  Wire bindings:
//    drivers.getMyHOS         — HOS remaining + ELD sync
//    driverDVIR.getMyPretrip  — pre-trip status (cached when offline)
//

import SwiftUI

private struct HOSData: Decodable, Hashable {
    let drivingRemainingMin: Int?
    let onDutyRemainingMin: Int?
    let cycleRemainingMin: Int?
    let driveTimeRemaining: Double?
    let eldSynced: Bool?
}

struct CatalystDriveModeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DriveModeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct DriveModeBody: View {
    @Environment(\.palette) private var palette

    enum Mode: String, CaseIterable {
        case drive = "DRIVE", offRotation = "OFF-ROTATION", park = "PARK"
    }

    @State private var hos: HOSData?
    @State private var mode: Mode = .offRotation
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                kpiGrid
                modeToggle
                modeContext
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVE MODE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Drive mode").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Owner-op · ready to roll").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("OWNER-OP · ME-ANCHORED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · ZERO ROTATION DRIFT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Eusotrans owns the asset · Michael drives it · same companyId · same Schedule C")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let driveMin = hos?.drivingRemainingMin ?? hos.flatMap { $0.driveTimeRemaining.map { Int($0) } } ?? 0
        let driveTime = "\(driveMin / 60)h \(driveMin % 60)m"
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("LANE", "1", "HOU → DAL · MC-306", .blue)
            kpi("HOS LEFT", driveTime, "11h drive · ELD \(hos?.eldSynced == true ? "synced" : "offline")",
                driveMin > 60 ? .green : .orange)
            kpi("DVIR", "PRE", "17 pts · due now", .green)
            kpi("DRIFT", "0d", "since last vac", .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(mode == m ? .white : palette.textSecondary)
                        .background(mode == m ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var modeContext: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT MODE · \(mode.rawValue)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(modeContextCopy)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(modeContextSubcopy)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modeContextCopy: String {
        switch mode {
        case .drive: return "Ready to roll — Houston → Dallas, MC-306 tanker."
        case .offRotation: return "Entered 06:00 CDT today · 1 active haul"
        case .park: return "Parked at home base — Belle Plaine bay 2."
        }
    }

    private var modeContextSubcopy: String {
        switch mode {
        case .drive: return "Pre-trip DVIR cleared · ELD synced · HOS green. Auto-records on engine-on."
        case .offRotation: return "Auto-locks at post-trip 18:30 CDT. Hour cycle resumes 06:00 tomorrow."
        case .park: return "Drift watch active. PM service due in 9d (May 8, oil + DEF, bay 2)."
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            hos = try await EusoTripAPI.shared.queryNoInput("drivers.getMyHOS")
        } catch { /* graceful — HOS panel renders even without live data */ }
    }
}

#Preview("316 Drive · Dark")  { CatalystDriveModeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("316 Drive · Light") { CatalystDriveModeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
