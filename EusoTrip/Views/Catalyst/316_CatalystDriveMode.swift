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

struct CatalystDriveModeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DriveModeBody() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .me),
                trailing: CarrierNavRoute.trailing(current: .me),
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

    @State private var hos: HOSStatus?
    @State private var hosError: String?
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
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
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
                Text("Eusotrans owns the asset · Michael drives it · same company · same Schedule C")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let driveHours = hos?.hasCurrentObservation() == true ? hos?.drivingRemaining : nil
        let driveTime = HOSStatus.formatHours(driveHours)
        let source = hos?.hasCurrentObservation() == true
            ? "\(hos?.source?.uppercased() ?? "SOURCED") · \(humanISO(hos?.freshness))"
            : hosError ?? hos?.assignmentEligibility().reason ?? "HOS evidence unavailable"
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("LANE", "1", "HOU → DAL · MC-306", .blue)
            kpi("HOS LEFT", driveTime, source,
                driveHours.map { $0 > 1 } == true ? .green : driveHours == nil ? palette.textTertiary : .orange)
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
                Button {
                    if m != .drive || canEnterDriveMode { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(mode == m ? .white : palette.textSecondary)
                        .background(mode == m ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(m == .drive && !canEnterDriveMode)
                .opacity(m == .drive && !canEnterDriveMode ? 0.5 : 1)
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
        case .drive: return canEnterDriveMode ? "Current HOS evidence permits driving." : "Drive mode is held pending current HOS evidence."
        case .offRotation: return "Off-rotation mode selected."
        case .park: return "Park mode selected."
        }
    }

    private var modeContextSubcopy: String {
        if let hosError { return hosError }
        guard let hos else { return "No HOS observation returned." }
        if hos.hasCurrentObservation() {
            return "\(hos.source?.uppercased() ?? "SOURCED") · observed \(humanISO(hos.freshness))"
        }
        return hos.assignmentEligibility().reason ?? "HOS observation is not current."
    }

    private var canEnterDriveMode: Bool {
        guard let hos,
              hos.hasCurrentObservation(),
              hos.status.flatMap(HOSDutyCode.init(rawValue:)) != nil,
              hos.drivingRemaining != nil,
              hos.onDutyRemaining != nil,
              hos.cycleRemaining != nil,
              hos.breakRequired != nil else {
            return false
        }
        return hos.canDrive == true && hos.breakRequired == false
    }

    private func load() async {
        loading = true; defer { loading = false }
        hosError = nil
        do {
            hos = try await EusoTripAPI.shared.queryNoInput("drivers.getMyHOS")
        } catch {
            hos = nil
            hosError = "Current HOS evidence could not refresh."
            if mode == .drive { mode = .offRotation }
        }
    }
}

#Preview("316 Drive · Dark")  { CatalystDriveModeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("316 Drive · Light") { CatalystDriveModeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
