//
//  602_EscortCorridorMap.swift
//  EusoTrip — Escort · Corridor Map (brick 602).
//
//  Third brick on the Escort role track (600s). Drilled into from
//  601_EscortAssignmentDetail's "View corridor →" sheet CTA — the
//  operator opens this surface to inspect the routed legs, milestone
//  schedule, geofence overlays, and lead/chase escort pairing along
//  the regulated corridor before they roll. Brings Escort to
//  three-screen depth, achieving the "all 8 of 8 non-driver roles
//  ≥ 3-deep" milestone the 2027 motivation directive points at.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §4 (tokenized spacing / radius / type —
//  Space.s*, Radius.*, EType.*), §5 (palette semantic only — no
//  hard-coded `Color.white` / `Color.black` / `Color.gray` fills
//  outside the CTA inverse-text and shadow opacities), §3
//  (`AnyShapeStyle` wrapping for ternary shape-styles in fill /
//  stroke), §10 (previews compile in isolation — `.task` doesn't
//  run in the preview canvas, so the store stays in `.loading` and
//  never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Corridor envelope → `EscortCorridorStore` (LiveDataStores.swift)
//      → `escorts.getCorridor` (input `{ id: string }`). Server
//      returns legs + milestones + geofences + escort vehicles + KPI
//      counts in a single envelope. If the parallel router has not
//      shipped, the store resolves to `.error` and the screen
//      surfaces an honest retry banner. No fixture data ever.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—"). A corridor with zero resolved legs folds to `.empty`
//      so the operator sees a deliberate "Corridor not yet routed"
//      empty state rather than a blank scaffold.
//    • Header preview-hint passthrough (loadNumber / lane / status)
//      so the screen has paint-1 visible content while the corridor
//      fetch is in flight. Mirrors the 601_EscortAssignmentDetail
//      preview-hint pattern.
//
//  Wired into `ContentView.ScreenRegistry` as id="602".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct EscortCorridorMap: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The assignment id to fetch the corridor for. The 601 sheet
    /// caller passes `EscortAPI.AssignmentDetail.id` straight through.
    let assignmentId: String

    /// Optional preview header values used while the corridor fetch is
    /// in flight. The 601 caller carries these for free — passing them
    /// through prevents the perceptible "blank header → real header"
    /// flash on first paint. When unavailable, pass `nil` and the
    /// screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStatus: String?

    @StateObject private var corridor = EscortCorridorStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    // MARK: - Header

    private var header: some View {
        let live = corridor.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "—"
        let lane: String = {
            if let live { return "\(live.origin) → \(live.destination)" }
            return previewLane ?? "—"
        }()
        let status = live?.status ?? previewStatus ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("ESCORT · CORRIDOR MAP")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(loadNumber)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                if !status.isEmpty {
                    statusPill(status)
                }
            }
            Text(lane)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)

            // KPI strip — only painted once the envelope is loaded so
            // the strip never paints fabricated zeros mid-load.
            if case .loaded(let envelope) = corridor.state, let v = envelope {
                kpiStrip(for: v)
            }
        }
    }

    @ViewBuilder
    private func kpiStrip(for v: EscortAPI.EscortCorridor) -> some View {
        HStack(spacing: Space.s2) {
            kpiTile(
                label: "LEGS",
                value: "\(v.legsCompleted)",
                sub: "of \(v.legsTotal)"
            )
            kpiTile(
                label: "COVERAGE",
                value: coverage(v.corridorCoverage),
                sub: "across corridor"
            )
            kpiTile(
                label: "MILES",
                value: milesDisplay(v.routedMiles),
                sub: "routed"
            )
        }
    }

    private func kpiTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch corridor.state {
        case .loading:
            loadingCard
        case .loaded(let envelope):
            if let v = envelope {
                corridorCards(for: v)
            } else {
                emptyState
            }
        case .empty:
            emptyState
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    @ViewBuilder
    private func corridorCards(for v: EscortAPI.EscortCorridor) -> some View {
        legsCard(v)
        milestonesCard(v)
        geofencesCard(v)
        escortVehiclesCard(v)
        permitClearanceCard(v)
    }

    // MARK: - Legs card

    private func legsCard(_ v: EscortAPI.EscortCorridor) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ROUTED LEGS", icon: "point.topleft.down.curvedto.point.bottomright.up.fill")
            if v.legs.isEmpty {
                Text("Corridor route hasn't resolved yet.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(v.legs) { leg in
                        legRow(leg)
                    }
                }
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

    private func legRow(_ leg: EscortAPI.CorridorLeg) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(leg.label.isEmpty ? "—" : leg.label)
                    .font(.system(size: 12, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if !leg.status.isEmpty {
                    statusPill(leg.status)
                }
            }
            HStack(spacing: 6) {
                Text(leg.origin.isEmpty ? "—" : leg.origin)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(leg.destination.isEmpty ? "—" : leg.destination)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let m = leg.miles, m > 0 {
                    Text(milesString(m))
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            // Coverage progress bar — gradient fill against a neutral
            // track. Shows the proportion of this leg already piloted
            // by an escort vehicle.
            coverageBar(leg.coverage)

            if let chips = leg.chips, !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.self) { c in
                        Text(c.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.danger)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Brand.danger.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func coverageBar(_ ratio: Double) -> some View {
        // Delegates to a self-contained view so the gradient fill can
        // own its own `@State` sweep + reduce-motion gate. Keyed on the
        // real `ratio` so the bar re-settles when coverage updates on a
        // pull-to-refresh.
        CoverageBar(ratio: ratio, track: palette.tintNeutral)
    }

    // MARK: - Milestones card

    private func milestonesCard(_ v: EscortAPI.EscortCorridor) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("MILESTONES", icon: "flag.fill")
            if v.milestones.isEmpty {
                Text("No corridor milestones scheduled.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(v.milestones) { m in
                        milestoneRow(m)
                    }
                }
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

    private func milestoneRow(_ m: EscortAPI.CorridorMilestone) -> some View {
        let isComplete = m.status.lowercased() == "completed"
        let isInflight = m.status.lowercased() == "in_progress"
        let icon: String = {
            if isComplete { return "checkmark.circle.fill" }
            if isInflight { return "circle.dotted" }
            return "circle"
        }()
        let glyphStyle: AnyShapeStyle = (isComplete || isInflight)
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.textTertiary)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(glyphStyle)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.label.isEmpty ? "—" : m.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let note = m.note, !note.isEmpty {
                    Text(note)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let eta = m.eta, !eta.isEmpty {
                    Text(eta)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                } else if let elapsed = m.elapsed, !elapsed.isEmpty {
                    Text(elapsed)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                }
                Text(m.status.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Geofences card

    @ViewBuilder
    private func geofencesCard(_ v: EscortAPI.EscortCorridor) -> some View {
        if !v.geofences.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("GEOFENCES", icon: "scope")
                FlowLayoutCompat(spacing: 6) {
                    ForEach(v.geofences) { g in
                        geofenceChip(g)
                    }
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

    private func geofenceChip(_ g: EscortAPI.CorridorGeofence) -> some View {
        let breached = (g.status?.lowercased() == "breached")
        let icon: String = {
            switch g.kind.lowercased() {
            case "bridge_clearance":      return "arrow.up.and.down.circle.fill"
            case "hazmat_exclusion":      return "flame.fill"
            case "weigh_station_bypass":  return "scalemass.fill"
            case "ports_of_entry":        return "shield.lefthalf.filled"
            default:                      return "scope"
            }
        }()
        let fg: Color = breached ? Brand.danger : palette.textSecondary
        let stroke: Color = breached ? Brand.danger.opacity(0.4) : palette.borderFaint
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(breached
                                 ? AnyShapeStyle(Brand.danger)
                                 : AnyShapeStyle(LinearGradient.diagonal))
            Text(g.label.isEmpty ? "—" : g.label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .overlay(
            Capsule().strokeBorder(stroke, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    // MARK: - Escort vehicles card

    @ViewBuilder
    private func escortVehiclesCard(_ v: EscortAPI.EscortCorridor) -> some View {
        if !v.escortVehicles.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("LEAD / CHASE", icon: "car.2.fill")
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(v.escortVehicles, id: \.vehicleId) { ev in
                        escortVehicleRow(ev)
                    }
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

    private func escortVehicleRow(_ ev: EscortAPI.CorridorEscortVehicle) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ev.role.lowercased() == "lead"
                  ? "arrow.up.forward.circle.fill"
                  : "arrow.down.left.circle.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ev.role.isEmpty ? "—" : ev.role.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ev.vehicleId.isEmpty ? "—" : ev.vehicleId)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                if let dn = ev.driverName, !dn.isEmpty {
                    Text(dn)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let loc = ev.lastKnownLocation, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text(loc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if let ping = ev.lastPingAt, !ping.isEmpty {
                Text(ping)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Permit / clearance summary

    @ViewBuilder
    private func permitClearanceCard(_ v: EscortAPI.EscortCorridor) -> some View {
        let hasPermit = (v.permitNumber?.isEmpty == false)
        let hasClearance = (v.bridgeClearanceFt.map { $0 > 0 } ?? false)
        let hasRouteName = (v.routeName?.isEmpty == false)
        if hasPermit || hasClearance || hasRouteName {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("PERMIT & CLEARANCE", icon: "doc.badge.gearshape.fill")
                if hasRouteName, let route = v.routeName {
                    summaryRow(label: "Route", value: route)
                }
                if hasPermit, let permit = v.permitNumber {
                    summaryRow(label: "Permit", value: permit)
                }
                if hasClearance, let bc = v.bridgeClearanceFt {
                    summaryRow(label: "Bridge clearance", value: clearanceString(bc))
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

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Loading / empty / error

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the corridor route, milestones, and lead/chase pairing…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "map.fill",
            title: "Corridor not yet routed",
            subtitle: "Dispatch hasn't published a corridor for this assignment. Pull to refresh once the route engine resolves."
        )
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

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

    private func statusPill(_ raw: String) -> some View {
        let label = raw.replacingOccurrences(of: "_", with: " ").uppercased()
        let isLive = liveStatuses.contains(raw.lowercased())
        let style: AnyShapeStyle = isLive
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isLive ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    private var liveStatuses: Set<String> {
        ["pending", "dispatched", "enroute", "active",
         "at_origin", "at_destination", "in_progress"]
    }

    private func coverage(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    private func milesString(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let core = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "\(core) mi"
    }

    /// Header KPI display for total miles. `nil` / 0 fold to em-dash
    /// (no fabricated zero).
    private func milesDisplay(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }

    private func clearanceString(_ ft: Double) -> String {
        guard ft > 0 else { return "—" }
        let whole = Int(ft)
        let inches = Int(((ft - Double(whole)) * 12).rounded())
        if inches == 0 { return "\(whole)'" }
        return "\(whole)'\(inches)\""
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func refreshAll() async {
        corridor.assignmentId = assignmentId
        await corridor.refresh()
    }
}

// MARK: - FlowLayoutCompat — wrapping chip layout used for geofences
//
// Tiny wrapping layout container — the corridor map renders a few
// geofence chips that may exceed the row width, so we wrap them
// like a flow row instead of clipping. Implemented inline so the
// 602 brick has no new cross-file dependencies; the surrounding
// codebase has no shared FlowLayout primitive yet.

private struct FlowLayoutCompat: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            totalWidth = max(totalWidth, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.minX + maxWidth {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: s.width, height: s.height)
            )
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - CoverageBar — animated leg-coverage progress fill
//
// The gradient fill width is BOUND to the leg's real `coverage`
// ratio (0…1) off `EscortAPI.CorridorLeg.coverage` — the proportion
// of the leg already piloted by an escort vehicle. It is never a
// decorative constant.
//
// Motion: on appear (and whenever the real ratio changes on a
// pull-to-refresh) the fill eases from its prior value to the new
// fraction on the decelerate cubic-bezier(0.4, 0, 0.2, 1) over a
// 0.55s data-settle beat — a one-shot settle, not a loop. Width is
// transform-cheap (single layer resize), 60fps.
//
// Reduce-motion: gated via @Environment(\.accessibilityReduceMotion)
// — the fill snaps straight to the final fraction with no sweep.

private struct CoverageBar: View {
    let ratio: Double
    let track: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    /// Real coverage fraction, NaN/∞-guarded and clamped to 0…1.
    private var target: Double {
        ratio.isFinite ? min(max(ratio, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(track)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    // `max(2, …)` keeps a hairline of fill visible even
                    // at 0% so the bar reads as "present but empty"
                    // rather than absent, while still tracking the real
                    // fraction for every value above the hairline.
                    .frame(width: max(2, geo.size.width * CGFloat(shown)))
            }
        }
        .frame(height: 4)
        .onAppear { settle(to: target) }
        .onChange(of: target) { _, newValue in settle(to: newValue) }
    }

    private func settle(to value: Double) {
        guard !reduceMotion else {
            shown = value
            return
        }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.55)) {
            shown = value
        }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortCorridorMapScreen: View {
    let theme: Theme.Palette
    let assignmentId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStatus: String?

    init(
        theme: Theme.Palette,
        assignmentId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStatus: String? = nil
    ) {
        self.theme = theme
        self.assignmentId = assignmentId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStatus = previewStatus
    }

    var body: some View {
        Shell(theme: theme) {
            EscortCorridorMap(
                assignmentId: assignmentId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStatus: previewStatus
            )
        } nav: {
            BottomNav(
                leading: escortNavLeading_602(),
                trailing: escortNavTrailing_602(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_602() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false)]
}

private func escortNavTrailing_602() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map",    isCurrent: true),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("602 · Escort · Corridor Map · Night") {
    EscortCorridorMapScreen(
        theme: Theme.dark,
        assignmentId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStatus: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("602 · Escort · Corridor Map · Afternoon") {
    EscortCorridorMapScreen(
        theme: Theme.light,
        assignmentId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStatus: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
