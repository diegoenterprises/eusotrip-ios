//
//  ES02_HeightPole.swift
//  EusoTrip — Escort · Height Pole / Clearance (brick 604 · ES-02).
//
//  GAUGE+MAP archetype (gauge-first), built verbatim from the ES-02
//  design-authority SVG pair
//  ("07 Escort/{Dark,Light}-SVG/ES-02 Height Pole.svg") and the
//  ES2_height_pole.md spec. The clearance arc gauge is the hero:
//  margin between the active pole height and the next low structure,
//  with the danger register, the upcoming-structures rail, the
//  proximity map, and the strike-capture flow underneath.
//
//  Wiring truth (code-traced this firing):
//    REAL  escorts.getActiveAssignments → the live assignment
//          (load number, lane, position, permit).
//    REAL  escorts.checkBridgeClearances → the national low-
//          clearance structure set checked against the active pole
//          height (per-structure posted clearance, margin, and
//          clear / warning / blocked classification). This feeds
//          the gauge, the structure rail, the map pins, and the
//          low-clearance banner.
//    REAL  escorts.logClearanceEvent → LOG STRIKE first writes the
//          structured clearance-event row for corridor memory/history.
//    REAL  incidents.report → strike events also open a visible safety
//          incident with GPS, structure, pole set-height, and haul-
//          stopped context in the description.
//    REAL  escorts.setPoleConfig → persists the current load height
//          + offset to escortAssignments.poleConfig so the setup
//          survives across devices.
//    ABSENT (named gap): ALERT CONVOY has no broadcast spine on this
//          screen yet → honest notice, never a fake send.
//
//  RBAC: registered role .escort only.
//
//  Pixel doctrine: palette tokens only, gradient-only accent,
//  tokenized spacing/radius/type, Dark + Light previews.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Wire projections (screen-local, private)

private struct EscortAssignmentRow: Decodable, Identifiable {
    let id: String
    let loadNumber: String
    let origin: String
    let destination: String
    let escortRole: String
    let permitNumber: String?
}

private struct AssignmentsLimitInput: Encodable { let limit: Int }

/// Input echo for `escorts.checkBridgeClearances`. The service
/// checks the national low-clearance structure set against the
/// supplied height; the load id rides along for the audit echo.
private struct ClearanceCheckInput: Encodable {
    let loadId: Int
    let vehicleHeightFt: Double
}

private struct BridgeStructure: Decodable, Hashable {
    let id: String
    let name: String
    let state: String
    let route: String
    let clearanceFt: Double
    let lat: Double
    let lng: Double
    let restricted: Bool?
}

private struct StructureWarning: Decodable, Hashable, Identifiable {
    var id: String { bridge.id }
    let bridge: BridgeStructure
    let marginFt: Double
    let status: String        // "clear" | "warning" | "blocked"
}

private struct ClearanceResultBlock: Decodable {
    let bridgesChecked: Int?
    let clearAll: Bool?
    let warnings: [StructureWarning]?
}

/// Envelope off `escorts.checkBridgeClearances`. The proc returns
/// `clearances` as an object when a check ran and as an empty array
/// when the height is below the check threshold — decode defensively
/// so both shapes land.
private struct ClearanceEnvelope: Decodable {
    let required: Bool
    let allClear: Bool?
    let result: ClearanceResultBlock?

    enum CodingKeys: String, CodingKey { case required, allClear, clearances }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        required = (try? c.decode(Bool.self, forKey: .required)) ?? false
        allClear = try? c.decodeIfPresent(Bool.self, forKey: .allClear)
        result = try? c.decodeIfPresent(ClearanceResultBlock.self, forKey: .clearances)
    }
}

/// Input for the dedicated `escorts.logClearanceEvent` clearance-events spine.
private struct ClearanceEventInput: Encodable {
    let eventType: String
    let loadHeightFt: Double
    let poleHeightSetFt: Double
    let damageObserved: Bool
    let haulStopped: Bool
    let lat: Double?
    let lng: Double?
    let structureName: String?
    let notes: String?
}
private struct ClearanceEventResult: Decodable { let success: Bool?; let id: Int?; let escalation: String? }

/// Input for `escorts.setPoleConfig` — persists the pole setup to the assignment.
private struct SetPoleConfigInput: Encodable {
    let assignmentId: Int
    let loadHeightFt: Double
    let offsetIn: Int
}
private struct SetPoleConfigResult: Decodable { let success: Bool? }

/// Input for `incidents.report` — the real strike-capture write.
private struct StrikeReportInput: Encodable {
    let type: String
    let severity: String
    let date: String
    let time: String
    let location: String
    let description: String
    let driverId: String
    let vehicleId: String
    let loadNumber: String?
}

private struct StrikeReportResponse: Decodable {
    let id: String?
    let incidentNumber: String?
    let status: String?
}

// MARK: - Screen body

struct EscortHeightPole: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    // Pole configuration — local first, then synced to the assignment
    // poleConfig record via escorts.setPoleConfig.
    @AppStorage("escort.pole.loadHeightInches") private var loadHeightInches: Int = 0
    @AppStorage("escort.pole.offsetInches") private var offsetInches: Int = 4

    @State private var assignment: EscortAssignmentRow? = nil
    @State private var clearance: ClearanceEnvelope? = nil
    @State private var clearanceFailed: Bool = false
    @State private var poleSyncMessage: String? = nil
    @State private var poleSyncError: String? = nil
    @State private var userCoord: CLLocationCoordinate2D? = nil

    /// Strike-capture sheet toggle + last committed incident ref.
    @State private var showStrikeSheet: Bool = false
    @State private var loggedIncidentNumber: String? = nil

    /// Honest ALERT CONVOY notice — no broadcast spine is attached.
    @State private var showConvoyNotice: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                titleRow
                statusRow
                hairline
                gaugeCard
                poleConfigCard
                structuresRail
                mapCard
                lowClearanceBanner
                if let n = loggedIncidentNumber { strikeLoggedCard(n) }
                if showConvoyNotice { convoyNoticeCard }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .eusoRefreshable { await refreshAll() }
        .sheet(isPresented: $showStrikeSheet) {
            EscortStrikeCaptureSheet(
                structures: sortedStructures,
                poleHeightFt: activePoleHeightFt,
                loadHeightFt: loadHeightFt,
                loadNumber: assignment?.loadNumber,
                coordinate: userCoord,
                onLogged: { ref in
                    loggedIncidentNumber = ref
                }
            )
            .environment(\.palette, palette)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Derived pole state

    private var loadHeightFt: Double { Double(loadHeightInches) / 12.0 }
    private var offsetFt: Double { Double(offsetInches) / 12.0 }
    private var poleIsSet: Bool { loadHeightInches > 0 }
    private var activePoleHeightFt: Double { poleIsSet ? loadHeightFt + offsetFt : 0 }

    /// Structures off the live clearance check, nearest-first when a
    /// GPS fix exists, tightest-margin-first otherwise.
    private var sortedStructures: [StructureWarning] {
        let rows = clearance?.result?.warnings ?? []
        guard let coord = userCoord else {
            return rows.sorted { $0.marginFt < $1.marginFt }
        }
        return rows.sorted {
            distanceMi(from: coord, to: $0.bridge) < distanceMi(from: coord, to: $1.bridge)
        }
    }

    /// The gauge's structure: nearest ahead when GPS is live,
    /// otherwise the tightest margin on the corridor set.
    private var nextStructure: StructureWarning? { sortedStructures.first }

    /// The corridor's most dangerous structure (for the banner).
    private var tightestStructure: StructureWarning? {
        (clearance?.result?.warnings ?? []).min { $0.marginFt < $1.marginFt }
    }

    // MARK: - Header

    private var eyebrowRow: some View {
        HStack {
            EusoTripEyebrow(verbatim: "ESCORT · HEIGHT POLE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(companyCaps)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var companyCaps: String {
        if let cid = session.user?.companyId, !cid.isEmpty {
            return "COMPANY · \(cid)".uppercased()
        }
        return "ESCORT NETWORK"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("Height Pole")
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if let move = assignment?.loadNumber, !move.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AnyShapeStyle(Brand.warning))
                        .frame(width: 6, height: 6)
                    Text(move)
                        .font(EType.mono(.caption)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: Space.s3) {
            if let role = assignment?.escortRole, !role.isEmpty {
                Text(role.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Brand.warning.opacity(0.14))
                    .clipShape(Capsule())
            }
            if poleIsSet {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AnyShapeStyle(Brand.success))
                        .frame(width: 6, height: 6)
                    Text("Pole active · \(ftIn(activePoleHeightFt)) set")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            } else {
                Text("Pole not set")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(operatorCaps)
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var operatorCaps: String {
        let name = session.user?.name ?? ""
        guard !name.isEmpty else { return "" }
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
        return "\(name) · \(initials)"
    }

    private var hairline: some View {
        Rectangle()
            .fill(palette.iridescentHairline)
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Clearance arc gauge (hero)

    @ViewBuilder
    private var gaugeCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                sectionHeader("CLEARANCE · NEXT STRUCTURE", icon: "arrow.up.and.down")
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(AnyShapeStyle(userCoord != nil ? Brand.success : palette.textTertiary))
                        .frame(width: 6, height: 6)
                    Text(userCoord != nil ? "GPS LIVE" : "GPS OFF")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if !poleIsSet {
                gaugeUnsetState
            } else if let next = nextStructure {
                ClearanceArcGauge(
                    marginFt: next.marginFt,
                    postedFt: next.bridge.clearanceFt,
                    poleFt: activePoleHeightFt,
                    palette: palette
                )
                .frame(height: 230)
                gaugeStatStrip(next)
            } else if clearanceFailed {
                gaugeErrorState
            } else if clearance != nil {
                gaugeAllClearState
            } else {
                gaugeLoadingState
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var gaugeUnsetState: some View {
        HStack(spacing: 10) {
            Image(systemName: "ruler")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set the load height to arm the gauge")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Enter the certified load height from your permit packet below. The clearance check runs against your active pole height the moment it's set.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(Space.s3)
        .background(palette.tintNeutral.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var gaugeLoadingState: some View {
        Text("Checking the low-clearance structure set against your pole height…")
            .font(EType.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(Space.s3)
    }

    private var gaugeAllClearState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("No structures under check at this height")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Your active pole height rides below the check threshold — no monitored structure is close enough to flag.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(Space.s3)
        .background(palette.tintSuccess)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var gaugeErrorState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't run the clearance check")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("EusoTrip couldn't reach the structure set. Your pole configuration is kept — pull to refresh to retry the check.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { Task { await refreshClearance() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.tintDanger)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func gaugeStatStrip(_ next: StructureWarning) -> some View {
        HStack(spacing: Space.s2) {
            gaugeStat(
                label: "TO STRUCT",
                value: userCoord.map { milesLabel(distanceMi(from: $0, to: next.bridge)) } ?? "-",
                tint: palette.textPrimary
            )
            gaugeStat(
                label: "STRUCTURES",
                value: "\(sortedStructures.count)",
                tint: palette.textPrimary
            )
            gaugeStat(
                label: "MARGIN",
                value: ftIn(next.marginFt),
                tint: marginColor(next.marginFt)
            )
        }
    }

    private func gaugeStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Pole configuration panel

    private var poleConfigCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("POLE CONFIGURATION", icon: "slider.horizontal.3")
            HStack(spacing: Space.s2) {
                loadHeightTile
                offsetTile
            }
            HStack(spacing: Space.s2) {
                activePoleTile
                stateRuleTile
            }
            Text("Saved on this device and synced to the assignment record when an active escort move is loaded.")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let poleSyncError {
                Text(poleSyncError)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let poleSyncMessage {
                Text(poleSyncMessage)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(Brand.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var loadHeightTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LOAD HEIGHT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(poleIsSet ? ftIn(loadHeightFt) : "-")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            HStack(spacing: 6) {
                configButton("-1'") { bumpLoadHeight(-12) }
                configButton("-1\"") { bumpLoadHeight(-1) }
                configButton("+1\"") { bumpLoadHeight(1) }
                configButton("+1'") { bumpLoadHeight(12) }
            }
            Text(poleIsSet ? "set on this device" : "from your permit packet")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var offsetTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("POLE OFFSET")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text("+\(offsetInches)\"")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            HStack(spacing: 6) {
                configButton("-") { bumpOffset(-1) }
                configButton("+") { bumpOffset(1) }
            }
            Text("3–6 in over load height")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var activePoleTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVE POLE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(poleIsSet ? ftIn(activePoleHeightFt) : "-")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text("load height + offset")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var stateRuleTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STATE RULE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text("-")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text("no trigger check on file — verify in your permit")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func configButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 30, minHeight: 26)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func bumpLoadHeight(_ inches: Int) {
        let next = max(0, min(20 * 12, loadHeightInches + inches))
        loadHeightInches = next
        Task { await refreshClearance() }
    }

    private func bumpOffset(_ inches: Int) {
        offsetInches = max(3, min(6, offsetInches + inches))
        Task { await refreshClearance() }
    }

    // MARK: - Upcoming structures rail

    @ViewBuilder
    private var structuresRail: some View {
        if poleIsSet, !sortedStructures.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    sectionHeader("UPCOMING STRUCTURES", icon: "building.columns")
                    Spacer(minLength: 0)
                    Text("\(sortedStructures.count) UNDER CHECK")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(sortedStructures.prefix(12)) { structureChip($0) }
                    }
                }
            }
        }
    }

    private func structureChip(_ w: StructureWarning) -> some View {
        let tint = statusColor(w.status)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let coord = userCoord {
                    Text(milesLabel(distanceMi(from: coord, to: w.bridge)))
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(tint)
                } else {
                    Text(w.bridge.state)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(tint)
                }
                Text("· \(w.bridge.name)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Text("\(ftIn(w.bridge.clearanceFt)) · Δ\(ftIn(w.marginFt))")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Proximity map

    @ViewBuilder
    private var mapCard: some View {
        if poleIsSet, !sortedStructures.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("PROXIMITY MAP", icon: "map.fill")
                HereVectorMapView(
                    center: mapCenter,
                    zoom: userCoord != nil ? 9 : 5,
                    interactive: false,
                    layers: [.markers(mapMarkers)]
                )
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .allowsHitTesting(false)
                if userCoord == nil {
                    Text("Enable location to sort structures by distance and center the map on your corridor position.")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var mapCenter: HereLatLng {
        if let c = userCoord { return HereLatLng(c) }
        if let first = sortedStructures.first {
            return HereLatLng(first.bridge.lat, first.bridge.lng)
        }
        return HereLatLng(39.5, -98.35)
    }

    private var mapMarkers: [HereMarker] {
        var pins = sortedStructures.prefix(12).map { w in
            HereMarker(
                at: HereLatLng(w.bridge.lat, w.bridge.lng),
                kind: .alert,
                label: ftIn(w.bridge.clearanceFt)
            )
        }
        if let c = userCoord {
            pins.append(HereMarker(at: HereLatLng(c), kind: .truck, label: "YOU"))
        }
        return pins
    }

    // MARK: - Low-clearance banner

    @ViewBuilder
    private var lowClearanceBanner: some View {
        if poleIsSet, let tight = tightestStructure, tight.marginFt < 0 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lowClearanceHeadline(tight))
                        .font(.system(size: 12, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                    Text("\(tight.bridge.name) · \(tight.bridge.route) · \(ftIn(tight.bridge.clearanceFt)) vs \(ftIn(activePoleHeightFt)) · \(ftIn(tight.marginFt))")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.danger)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func lowClearanceHeadline(_ w: StructureWarning) -> String {
        if let coord = userCoord {
            return "LOW CLEARANCE · \(milesLabel(distanceMi(from: coord, to: w.bridge)))"
        }
        return "LOW CLEARANCE ON THE STRUCTURE SET"
    }

    // MARK: - Strike logged / convoy notice

    private func strikeLoggedCard(_ ref: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged · \(ref)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Filed to your safety record. Critical and major events also notify the safety desk in real time.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintSuccess)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var convoyNoticeCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Convoy broadcast isn't connected")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("No live channel is attached to this move, so the low-clearance call can't reach the convoy from this screen. Call it out on CB channel 17, then log the event here so it's on the record.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                showStrikeSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("LOG STRIKE")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Brand.danger)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.12)) { showConvoyNotice = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .heavy))
                    Text("ALERT CONVOY")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                }
                .foregroundStyle(Brand.warning)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.55), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "blocked": return Brand.danger
        case "warning": return Brand.warning
        default:        return Brand.success
        }
    }

    private func marginColor(_ margin: Double) -> Color {
        if margin < 0 { return Brand.danger }
        if margin < 2 { return Brand.warning }
        return Brand.success
    }

    private func milesLabel(_ mi: Double) -> String {
        if mi < 10 { return String(format: "%.1f mi", mi) }
        return "\(Int(mi.rounded())) mi"
    }

    private func distanceMi(from coord: CLLocationCoordinate2D, to bridge: BridgeStructure) -> Double {
        let a = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let b = CLLocation(latitude: bridge.lat, longitude: bridge.lng)
        return a.distance(from: b) / 1609.344
    }

    // MARK: - Data plumbing

    private func refreshAll() async {
        async let coord = DriverLocationResolver.shared.currentCoordinate()
        await refreshAssignment()
        userCoord = await coord
        await refreshClearance()
    }

    private func refreshAssignment() async {
        let rows: [EscortAssignmentRow]? = try? await EusoTripAPI.shared.query(
            "escorts.getActiveAssignments",
            input: AssignmentsLimitInput(limit: 1)
        )
        assignment = rows?.first
    }

    private func refreshClearance() async {
        guard poleIsSet else {
            clearance = nil
            clearanceFailed = false
            poleSyncMessage = nil
            poleSyncError = nil
            return
        }
        do {
            let env: ClearanceEnvelope = try await EusoTripAPI.shared.query(
                "escorts.checkBridgeClearances",
                input: ClearanceCheckInput(
                    loadId: assignment.flatMap { Int($0.id) } ?? 0,
                    vehicleHeightFt: activePoleHeightFt
                )
            )
            clearance = env
            clearanceFailed = false
        } catch {
            clearanceFailed = true
        }
        await syncPoleConfig()
    }

    private func syncPoleConfig() async {
        guard let aid = assignment.flatMap({ Int($0.id) }), aid > 0 else {
            poleSyncMessage = nil
            poleSyncError = "Pole setup is saved on this device; no active escort assignment was returned to sync."
            return
        }
        do {
            let out: SetPoleConfigResult = try await EusoTripAPI.shared.mutation(
                "escorts.setPoleConfig",
                input: SetPoleConfigInput(assignmentId: aid, loadHeightFt: loadHeightFt, offsetIn: offsetInches)
            )
            if out.success == false {
                poleSyncMessage = nil
                poleSyncError = "Pole setup is saved on this device, but the assignment sync was not accepted."
            } else {
                poleSyncError = nil
                poleSyncMessage = "Pole setup synced to assignment \(aid)."
            }
        } catch {
            poleSyncMessage = nil
            poleSyncError = Self.poleSyncFailureCopy(for: error)
        }
    }

    /// Operator-language copy for a failed pole sync. The underlying error is
    /// kept intact for logging; the escort reads a sentence they can act on,
    /// never a raw system error string.
    private static func poleSyncFailureCopy(for error: Error) -> String {
        guard let api = error as? EusoTripAPIError else {
            return "Pole setup is saved on this device. It could not be synced to the assignment — check your signal and it will sync on the next reading."
        }
        switch api {
        case .unauthenticated, .forbidden:
            return "Pole setup is saved on this device. Your sign-in no longer covers this assignment, so it was not synced — sign in again, then reopen this move."
        case .httpStatus, .badURL, .notConfigured, .empty:
            return "Pole setup is saved on this device. The assignment record could not be reached, so it was not synced — try again in a moment."
        case .decodingFailed:
            return "Pole setup is saved on this device. The assignment record came back in a form this build can't read, so it was not synced — update the app, then reopen this move."
        case .queuedForOfflineReplay:
            return "Pole setup is saved on this device. You're offline — it will sync to the assignment when you reconnect."
        case .trpcError(let reason):
            return "Pole setup is saved on this device, but the assignment sync was refused: \(reason)"
        }
    }
}

// MARK: - Clearance arc gauge

/// The ES-02 hero: a 180° arc scaled -2 ft … +4 ft of margin between
/// the active pole height and the next structure's posted clearance.
/// Red band below zero, amber to +2 ft, green above. The needle ring
/// rides the arc at the live margin; the center stack carries the
/// margin readout, the posted-vs-pole line, and the register pill.
private struct ClearanceArcGauge: View {
    let marginFt: Double
    let postedFt: Double
    let poleFt: Double
    let palette: Theme.Palette

    private let scaleMin: Double = -2
    private let scaleMax: Double = 4
    private let lineWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h - 28
            let r = min(w / 2 - lineWidth, h - 60)

            ZStack {
                arcSegment(from: 0.0, to: bandFraction(0), color: Brand.danger, cx: cx, cy: cy, r: r)
                arcSegment(from: bandFraction(0), to: bandFraction(2), color: Brand.warning, cx: cx, cy: cy, r: r)
                arcSegment(from: bandFraction(2), to: 1.0, color: Brand.success, cx: cx, cy: cy, r: r)

                // Needle ring at the live margin.
                Circle()
                    .strokeBorder(palette.textPrimary, lineWidth: 3)
                    .background(Circle().fill(palette.bgCard))
                    .frame(width: 18, height: 18)
                    .position(needlePoint(cx: cx, cy: cy, r: r))

                // Scale end labels.
                Text(endLabel(scaleMin))
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(Brand.danger)
                    .position(x: cx - r, y: cy + 14)
                Text(endLabel(scaleMax))
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(Brand.success)
                    .position(x: cx + r, y: cy + 14)

                // Center readout.
                VStack(spacing: 3) {
                    Text("MARGIN")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Text(gaugeFtIn(marginFt))
                        .font(.system(size: 40, weight: .heavy, design: .monospaced))
                        .foregroundStyle(registerColor)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("POSTED \(gaugeFtIn(postedFt)) · POLE \(gaugeFtIn(poleFt))")
                        .font(EType.mono(.micro)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                    Text(registerLabel)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(registerColor)
                        .clipShape(Capsule())
                }
                .position(x: cx, y: cy - r * 0.28)
            }
        }
    }

    /// Fraction (0…1) along the arc for a margin value on the scale.
    private func bandFraction(_ margin: Double) -> Double {
        let clamped = min(max(margin, scaleMin), scaleMax)
        return (clamped - scaleMin) / (scaleMax - scaleMin)
    }

    private func arcSegment(from: Double, to: Double, color: Color,
                            cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Path { p in
            p.addArc(
                center: CGPoint(x: cx, y: cy),
                radius: r,
                startAngle: .degrees(180 + from * 180),
                endAngle: .degrees(180 + to * 180),
                clockwise: false
            )
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
    }

    private func needlePoint(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPoint {
        let theta = (180.0 + bandFraction(marginFt) * 180.0) * .pi / 180.0
        return CGPoint(x: cx + r * CGFloat(cos(theta)), y: cy + r * CGFloat(sin(theta)))
    }

    private var registerColor: Color {
        if marginFt < 0 { return Brand.danger }
        if marginFt < 2 { return Brand.warning }
        return Brand.success
    }

    private var registerLabel: String {
        if marginFt < 0 { return "DANGER" }
        if marginFt < 2 { return "CAUTION" }
        return "CLEAR"
    }

    private func endLabel(_ v: Double) -> String {
        v < 0 ? "\(Int(v))'" : "+\(Int(v))'"
    }

    private func gaugeFtIn(_ ft: Double) -> String {
        let sign = ft < 0 ? "-" : ""
        let a = abs(ft)
        var whole = Int(a)
        var inches = Int(((a - Double(whole)) * 12).rounded())
        if inches == 12 { whole += 1; inches = 0 }
        return "\(sign)\(whole)'\(inches)\""
    }
}

/// Shared feet-inches formatter for the screen body.
private func ftIn(_ ft: Double) -> String {
    let sign = ft < 0 ? "-" : ""
    let a = abs(ft)
    var whole = Int(a)
    var inches = Int(((a - Double(whole)) * 12).rounded())
    if inches == 12 { whole += 1; inches = 0 }
    return "\(sign)\(whole)'\(inches)\""
}

// MARK: - Strike capture sheet (real incidents write)

/// The LOG STRIKE modal — captures the event and files it as a real
/// safety incident. Strike → accident, near miss → near_miss,
/// clearance check → other; severity keys off the observed damage.
/// The pole set-height, posted clearance, structure, GPS, and
/// haul-stopped call are composed into the incident description so
/// the safety desk gets the full picture in one record.
private struct EscortStrikeCaptureSheet: View {
    let structures: [StructureWarning]
    let poleHeightFt: Double
    let loadHeightFt: Double
    let loadNumber: String?
    let coordinate: CLLocationCoordinate2D?
    let onLogged: (String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private enum EventKind: String, CaseIterable, Identifiable {
        case strike = "Strike"
        case nearMiss = "Near miss"
        case check = "Clearance check"
        var id: String { rawValue }

        var wireType: String {
            switch self {
            case .strike:   return "accident"
            case .nearMiss: return "near_miss"
            case .check:    return "other"
            }
        }

        /// Event type for the dedicated clearance-events spine.
        var clearanceWireType: String {
            switch self {
            case .strike:   return "strike"
            case .nearMiss: return "near_miss"
            case .check:    return "clearance_check"
            }
        }
    }

    private enum DamageKind: String, CaseIterable, Identifiable {
        case none = "None"
        case pole = "Pole damage"
        case cargoBrush = "Cargo brush"
        case structural = "Structural contact"
        var id: String { rawValue }

        var wireSeverity: String {
            switch self {
            case .structural:        return "critical"
            case .pole, .cargoBrush: return "major"
            case .none:              return "minor"
            }
        }
    }

    @State private var kind: EventKind = .strike
    @State private var damage: DamageKind = .none
    @State private var haulStopped: Bool = false
    @State private var structureIndex: Int = 0
    @State private var notes: String = ""
    @State private var inFlight: Bool = false
    @State private var failed: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Log clearance event")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)

                fieldLabel("EVENT")
                Picker("Event", selection: $kind) {
                    ForEach(EventKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                fieldLabel("STRUCTURE")
                structurePicker

                fieldLabel("DAMAGE OBSERVED")
                Picker("Damage", selection: $damage) {
                    ForEach(DamageKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                fieldLabel("HAUL STOPPED")
                Picker("Haul stopped", selection: $haulStopped) {
                    Text("No").tag(false)
                    Text("Yes").tag(true)
                }
                .pickerStyle(.segmented)

                fieldLabel("NOTES")
                TextField("What happened (optional)", text: $notes, axis: .vertical)
                    .font(EType.body)
                    .lineLimit(3...5)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                if failed {
                    Text("EusoTrip couldn't file the event. Nothing was recorded — check your connection and submit again.")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if inFlight {
                            ProgressView().progressViewStyle(.circular)
                                .tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .heavy))
                        }
                        Text(inFlight ? "Filing…" : "File event")
                            .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Brand.danger.opacity(inFlight ? 0.6 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                Color.clear.frame(height: 24)
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    @ViewBuilder
    private var structurePicker: some View {
        if structures.isEmpty {
            Text("No monitored structure nearby — the event files with your GPS position.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("Structure", selection: $structureIndex) {
                ForEach(0..<structures.count, id: \.self) { i in
                    Text("\(structures[i].bridge.name) · \(structures[i].bridge.route)").tag(i)
                }
                Text("Other / unlisted").tag(structures.count)
            }
            .pickerStyle(.menu)
            .tint(palette.textPrimary)
            .padding(Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var selectedStructure: StructureWarning? {
        guard structureIndex >= 0, structureIndex < structures.count else { return nil }
        return structures[structureIndex]
    }

    private func submit() async {
        guard !inFlight else { return }
        inFlight = true
        failed = false
        defer { inFlight = false }

        let now = Date()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        let locationText: String = {
            if let s = selectedStructure {
                return "\(s.bridge.name) · \(s.bridge.route), \(s.bridge.state)"
            }
            if let c = coordinate {
                return String(format: "%.5f, %.5f", c.latitude, c.longitude)
            }
            return "On corridor — position unavailable"
        }()

        var parts: [String] = []
        parts.append("Height-pole \(kind.rawValue.lowercased()) logged by escort.")
        if let s = selectedStructure {
            parts.append("Structure: \(s.bridge.name) (\(s.bridge.route), \(s.bridge.state)), posted \(ftInSheet(s.bridge.clearanceFt)).")
            parts.append("Margin vs active pole: \(ftInSheet(s.marginFt)).")
        }
        parts.append("Active pole height \(ftInSheet(poleHeightFt)); load height \(ftInSheet(loadHeightFt)).")
        parts.append("Damage observed: \(damage.rawValue.lowercased()).")
        parts.append("Haul stopped: \(haulStopped ? "yes" : "no").")
        if let c = coordinate {
            parts.append(String(format: "GPS %.5f, %.5f.", c.latitude, c.longitude))
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Notes: \(notes)")
        }

        do {
            // Primary structured record: the dedicated clearance-events spine
            // (corridor memory + per-structure strike history).
            let _: ClearanceEventResult = try await EusoTripAPI.shared.mutation(
                "escorts.logClearanceEvent",
                input: ClearanceEventInput(
                    eventType: kind.clearanceWireType,
                    loadHeightFt: loadHeightFt,
                    poleHeightSetFt: poleHeightFt,
                    damageObserved: damage != .none,
                    haulStopped: haulStopped,
                    lat: coordinate?.latitude,
                    lng: coordinate?.longitude,
                    structureName: locationText,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                )
            )
            // A real strike also opens a visible safety incident.
            var reference = "Clearance event logged"
            if kind == .strike {
                let resp: StrikeReportResponse = try await EusoTripAPI.shared.mutation(
                    "incidents.report",
                    input: StrikeReportInput(
                        type: kind.wireType,
                        severity: haulStopped && damage == .none ? "major" : damage.wireSeverity,
                        date: dayFmt.string(from: now),
                        time: timeFmt.string(from: now),
                        location: locationText,
                        description: parts.joined(separator: " "),
                        driverId: "",
                        vehicleId: "",
                        loadNumber: loadNumber
                    )
                )
                reference = resp.incidentNumber ?? "Safety record"
            }
            onLogged(reference)
            dismiss()
        } catch {
            failed = true
        }
    }

    private func ftInSheet(_ ft: Double) -> String {
        let sign = ft < 0 ? "-" : ""
        let a = abs(ft)
        var whole = Int(a)
        var inches = Int(((a - Double(whole)) * 12).rounded())
        if inches == 12 { whole += 1; inches = 0 }
        return "\(sign)\(whole)'\(inches)\""
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortHeightPoleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortHeightPole()
        } nav: {
            BottomNav(
                leading: escortNavLeading_604(),
                trailing: escortNavTrailing_604(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_604() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func escortNavTrailing_604() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews
//
// Previews don't run `.task`, so the gauge renders its unset /
// loading registers without touching the network or CoreLocation.

#Preview("604 · Escort · Height Pole · Dark") {
    EscortHeightPoleScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("604 · Escort · Height Pole · Light") {
    EscortHeightPoleScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
