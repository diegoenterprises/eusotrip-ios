//
//  601_EscortAssignmentDetail.swift
//  EusoTrip — Escort · Assignment Detail (brick 601).
//
//  Second brick on the Escort role track (600s). The natural follow-on
//  to 600_EscortHome — when the operator taps an active-assignment row
//  on the home, this is the deep assignment-detail surface that opens.
//  Until 601 shipped, that row tap was a no-op (an empty closure).
//  Now the tap presents this real surface so Escort depth matches the
//  structural depth of Carrier (300/301/302), Broker (400/401/402), and
//  Catalyst (500/501/502): three production screens per role.
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
//    • Assignment detail → `EscortAssignmentDetailStore`
//      (LiveDataStores.swift) → `escorts.getActiveAssignmentDetail`
//      (input `{ id: string }`). If the parallel router has not
//      shipped, the store resolves to `.error` and the screen
//      surfaces an honest retry banner. No fixture data ever.
//    • "Confirm route" CTA → `escorts.confirmRoute` mutation
//      (input `{ id: string }`). Disabled while the detail fetch
//      is in flight, while the mutation is in flight, and once
//      the server-side `routeConfirmed: true` flag has flipped.
//      On success the local cell repaints from the mutation's
//      returned envelope (no extra round-trip). On failure the
//      CTA flips back to its idle label and the inline error
//      surfaces — local state never lies about the commit landing.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh assignment (no
//      permit attached, no driver paired, no bridge clearance
//      surveyed, no notes) renders as a neutral em-dash, never
//      a fabricated value.
//    • Preview hint passthrough (loadNumber / lane / startedAt /
//      escortRole / corridorCoverage / permitNumber) so the
//      sheet has paint-1 visible content while the detail fetch
//      is in flight. Mirrors the 502_CatalystMatchDetail
//      preview-hint pattern.
//
//  Wired into `ContentView.ScreenRegistry` as id="601".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct EscortAssignmentDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The assignment id to fetch. Server expects `{ id: string }`
    /// per the Zod input on `escorts.getActiveAssignmentDetail`. The
    /// 600 row carries `id: String` already (EscortAPI.ActiveAssignment).
    let assignmentId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (600's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewEscortRole: String?
    let previewPermitNumber: String?
    let previewCorridorCoverage: Double?

    @StateObject private var detailStore = EscortAssignmentDetailStore()

    /// CTA in-flight state. Drives the "Confirm route" button label
    /// and disabled state separately from `detailStore.state`. Reset
    /// on retry / refresh.
    @State private var confirmInFlight: Bool = false
    /// CTA local error (post-mutation). Cleared on retry. Distinct
    /// from `detailStore`'s own `.error` — that one's about the
    /// detail fetch, this one's about the confirm-route mutation.
    @State private var confirmError: String? = nil
    /// Local override for the server's `routeConfirmed` flag. Set by
    /// a successful mutation so the CTA flips immediately without
    /// waiting for the next refresh round-trip.
    @State private var localConfirmed: Bool = false

    /// Toggle that presents the 602 corridor-map sheet. Set by the
    /// "View corridor →" drill-in CTA. Added 2026-04-27 in the 159th
    /// eusotrip-killers firing alongside the 602 brick.
    @State private var showCorridorMap: Bool = false

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
        // Corridor-map sheet — opened by tapping the "View corridor →"
        // drill-in CTA. Detents `[.large]` mirrors the Me sub-route
        // pattern in MeDetailScreens. The corridor screen reads from
        // `escorts.getCorridor` independently, so the parent's detail
        // fetch does not block the corridor open.
        .sheet(isPresented: $showCorridorMap) {
            let live: EscortAPI.AssignmentDetail? = detailStore.state.value ?? nil
            EscortCorridorMapScreen(
                theme: palette,
                assignmentId: assignmentId,
                previewLoadNumber: live?.loadNumber ?? previewLoadNumber,
                previewLane: corridorLanePreview,
                previewStatus: live?.status
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Lane string used as a preview hint when opening the 602 sheet —
    /// avoids a paint-1 blank header on the corridor screen.
    private var corridorLanePreview: String? {
        if let live = detailStore.state.value ?? nil {
            return "\(live.origin) → \(live.destination)"
        }
        return previewLane
    }

    // MARK: - Header

    private var header: some View {
        let live: EscortAPI.AssignmentDetail? = detailStore.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "—"
        let lane: String = {
            if let live { return "\(live.origin) → \(live.destination)" }
            return previewLane ?? "—"
        }()
        let status = live?.status ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
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
                        Text("ESCORT · ASSIGNMENT DETAIL")
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
        }
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch detailStore.state {
        case .loading:
            loadingCard
        case .loaded(let opt):
            if let detail = opt {
                detailCards(for: detail)
            } else {
                EusoEmptyState(
                    systemImage: "shield.lefthalf.filled",
                    title: "Assignment not found",
                    subtitle: "This corridor is no longer on your plate. Pull to refresh or pick another assignment from the home."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "shield.lefthalf.filled",
                title: "Assignment not found",
                subtitle: "This corridor is no longer on your plate. Pull to refresh or pick another assignment from the home."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Detail cards (live data)

    @ViewBuilder
    private func detailCards(for detail: EscortAPI.AssignmentDetail) -> some View {
        metricsRow(detail)
        scheduleCard(detail)
        corridorCard(detail)
        pairingCard(detail)
        contactCard(detail)
        notesCard(detail)
        viewCorridorMapCTA(detail)
        confirmRouteCTA(detail)
    }

    /// Drill-in CTA that opens the 602 corridor-map sheet. Added 2026-04-27
    /// in the 159th eusotrip-killers firing alongside the 602 brick.
    /// Closes the role-by-role 3-deep parity gap from the 158th firing
    /// (Escort was the only 2-deep non-driver role before this brick).
    @ViewBuilder
    private func viewCorridorMapCTA(_ d: EscortAPI.AssignmentDetail) -> some View {
        Button {
            showCorridorMap = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("View corridor")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
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
        .buttonStyle(.plain)
    }

    /// Three-tile row: corridor coverage / escort role / started.
    /// Em-dash on missing values so a brand-new assignment doesn't
    /// fabricate values.
    private func metricsRow(_ d: EscortAPI.AssignmentDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(
                label: "COVERAGE",
                value: coverage(d.corridorCoverage),
                icon: "scope"
            )
            metricTile(
                label: "ESCORT ROLE",
                value: roleDisplay(d.escortRole),
                icon: "car.2.fill"
            )
            metricTile(
                label: "STARTED",
                value: startedDisplay(d),
                icon: "clock"
            )
        }
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    /// Lane / origin / destination + routed miles when present.
    private func scheduleCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CORRIDOR", icon: "map")
            scheduleRow(label: "Origin",      value: d.origin.isEmpty ? "—" : d.origin)
            scheduleRow(label: "Destination", value: d.destination.isEmpty ? "—" : d.destination)
            if let miles = d.routedMiles, miles > 0 {
                scheduleRow(label: "Routed miles", value: milesString(miles))
            }
            if let route = d.routeName, !route.isEmpty {
                scheduleRow(label: "Route", value: route)
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

    /// Permit + hazmat + OS-OW context. Rows only render when the
    /// underlying field is set, so a permit-less assignment doesn't
    /// surface "Permit: —" filler.
    @ViewBuilder
    private func corridorCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        // Decide whether anything in this card has signal — if all
        // fields are empty, skip the section entirely.
        let hasPermit  = !d.permitNumber.isEmpty
        let hasHazmat  = (d.hazmatClass?.isEmpty == false)
        let hasUN      = (d.unNumber?.isEmpty == false)
        let hasOS      = (d.oversizeFlag == true)
        let hasOW      = (d.overweightFlag == true)
        let hasBridge  = (d.bridgeClearanceFt.map { $0 > 0 } ?? false)
        if hasPermit || hasHazmat || hasUN || hasOS || hasOW || hasBridge {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("PERMIT & COMPLIANCE", icon: "doc.badge.gearshape.fill")
                if hasPermit {
                    scheduleRow(label: "Permit", value: d.permitNumber)
                }
                if hasHazmat {
                    scheduleRow(label: "Hazmat class", value: d.hazmatClass!)
                }
                if hasUN {
                    scheduleRow(label: "UN number", value: d.unNumber!)
                }
                if hasOS || hasOW {
                    let chips: [String] = {
                        var c: [String] = []
                        if hasOS { c.append("OS") }
                        if hasOW { c.append("OW") }
                        return c
                    }()
                    scheduleRow(label: "Dimensional", value: chips.joined(separator: " · "))
                }
                if hasBridge, let bc = d.bridgeClearanceFt {
                    scheduleRow(label: "Bridge clearance", value: clearanceString(bc))
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

    /// Lead / chase pairing identifiers. Only renders when at least
    /// one slot is filled.
    @ViewBuilder
    private func pairingCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        let lead = d.leadVehicleId ?? ""
        let chase = d.chaseVehicleId ?? ""
        if !lead.isEmpty || !chase.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("LEAD / CHASE", icon: "car.2.fill")
                if !lead.isEmpty {
                    scheduleRow(label: "Lead vehicle",  value: lead)
                }
                if !chase.isEmpty {
                    scheduleRow(label: "Chase vehicle", value: chase)
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

    /// Driver / shipper contacts. Only renders when at least one
    /// field is set.
    @ViewBuilder
    private func contactCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        let driver = d.driverName ?? ""
        let driverPhone = d.driverPhone ?? ""
        let shipper = d.shipperName ?? ""
        if !driver.isEmpty || !driverPhone.isEmpty || !shipper.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("CONTACT", icon: "person.crop.circle")
                if !driver.isEmpty {
                    scheduleRow(label: "Driver", value: driver)
                }
                if !driverPhone.isEmpty {
                    scheduleRow(label: "Driver phone", value: driverPhone)
                }
                if !shipper.isEmpty {
                    scheduleRow(label: "Shipper", value: shipper)
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

    /// Free-form corridor notes from dispatch. Only renders when set.
    @ViewBuilder
    private func notesCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        if let notes = d.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("NOTES", icon: "text.alignleft")
                Text(notes)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Confirm route CTA

    /// "Confirm route" CTA. Drives `escorts.confirmRoute` and re-paints
    /// the cell from the mutation envelope. Disabled while the detail
    /// fetch is loading, while the mutation is in flight, and once the
    /// route has already been confirmed (server flag or local override).
    @ViewBuilder
    private func confirmRouteCTA(_ d: EscortAPI.AssignmentDetail) -> some View {
        // Only show the CTA on assignments where confirming is
        // plausible — the corridor must be in a pre-roll or live
        // status. Anything past `completed` / `cancelled` suppresses
        // the CTA so we don't offer a no-op.
        let confirmable: Set<String> = [
            "pending", "dispatched", "enroute", "at_origin", "at_destination"
        ]
        let alreadyConfirmed = (d.routeConfirmed == true) || localConfirmed
        if confirmable.contains(d.status.lowercased()) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await confirmRoute(id: d.id) }
                } label: {
                    HStack(spacing: 8) {
                        if confirmInFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: alreadyConfirmed ? "checkmark.circle.fill" : "arrow.up.right.circle.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Text(alreadyConfirmed ? "Route confirmed" : "Confirm route")
                            .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.diagonal.opacity(alreadyConfirmed ? 0.55 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(alreadyConfirmed || confirmInFlight)

                if let msg = confirmError, !msg.isEmpty {
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !alreadyConfirmed && confirmError == nil {
                    Text("Confirms this corridor with dispatch and arms the lead/chase pairing for departure. Sends `escorts.confirmRoute`.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func confirmRoute(id: String) async {
        guard !id.isEmpty, !confirmInFlight else { return }
        confirmInFlight = true
        confirmError = nil
        defer { confirmInFlight = false }
        do {
            let updated = try await EusoTripAPI.shared.escort.confirmRoute(id: id)
            // Re-paint the cell from the mutation envelope and flip
            // the local override so the CTA disables immediately.
            detailStore.state = .loaded(updated)
            localConfirmed = true
        } catch {
            confirmError = readableError(error)
        }
    }

    // MARK: - Loading + error states

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the latest from the assignment record…")
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

    private func scheduleRow(label: String, value: String) -> some View {
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

    /// "Live" framing for an escort assignment — anything pre-roll
    /// or rolling is gradient. Past completion reads as neutral.
    private var liveStatuses: Set<String> {
        ["pending", "dispatched", "enroute", "at_origin", "at_destination"]
    }

    /// Format a corridor-coverage ratio (0.0…1.0) as a percentage
    /// rounded to whole digits. Returns "—" for zero so the empty
    /// case never renders as "0%".
    private func coverage(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    /// Sentence-case the server enum so the metric tile reads
    /// "Lead", "Chase", or "Lead+Chase" instead of the raw token.
    private func roleDisplay(_ raw: String) -> String {
        guard !raw.isEmpty else { return "—" }
        switch raw.lowercased() {
        case "lead":         return "Lead"
        case "chase":        return "Chase"
        case "lead+chase",
             "lead_chase",
             "leadchase":    return "Lead + Chase"
        default:             return raw.capitalized
        }
    }

    /// "started 2m" — server-projected relative label from the
    /// ActiveAssignment row. Falls back to the AssignmentDetail.startedAt
    /// when the row hint is missing. Em-dash when both are absent.
    private func startedDisplay(_ d: EscortAPI.AssignmentDetail) -> String {
        if let s = previewStartedAt, !s.isEmpty {
            return s
        }
        return humanDate(d.startedAt)
    }

    /// Format escort-corridor mileage as a thousands-separated whole-mile
    /// string. Returns "—" for zero so the empty case never renders as
    /// "0 mi".
    private func milesString(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let core = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "\(core) mi"
    }

    /// Format bridge clearance feet as a doctrinal "13'6\"" string.
    /// Returns "—" for zero.
    private func clearanceString(_ ft: Double) -> String {
        guard ft > 0 else { return "—" }
        let whole = Int(ft)
        let inches = Int(((ft - Double(whole)) * 12).rounded())
        if inches == 0 { return "\(whole)'" }
        return "\(whole)'\(inches)\""
    }

    /// Parse an ISO-8601 date string from the server and render as a
    /// short human-readable form (e.g. "Apr 28 · 09:30"). Em-dash
    /// when nil / empty / unparseable so missing dates always look
    /// like a deliberate sentinel.
    private func humanDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "—" }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            // Server occasionally hands back YYYY-MM-DD only.
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · HH:mm"
        return fmt.string(from: d)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func refreshAll() async {
        detailStore.assignmentId = assignmentId
        confirmError = nil
        await detailStore.refresh()
        // Re-sync the local override against whatever the server
        // says — if the assignment was re-opened upstream, reflect it.
        if case .loaded(let opt) = detailStore.state, let v = opt {
            localConfirmed = (v.routeConfirmed == true)
        }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortAssignmentDetailScreen: View {
    let theme: Theme.Palette
    let assignmentId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewEscortRole: String?
    let previewPermitNumber: String?
    let previewCorridorCoverage: Double?

    init(
        theme: Theme.Palette,
        assignmentId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStartedAt: String? = nil,
        previewEscortRole: String? = nil,
        previewPermitNumber: String? = nil,
        previewCorridorCoverage: Double? = nil
    ) {
        self.theme = theme
        self.assignmentId = assignmentId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStartedAt = previewStartedAt
        self.previewEscortRole = previewEscortRole
        self.previewPermitNumber = previewPermitNumber
        self.previewCorridorCoverage = previewCorridorCoverage
    }

    var body: some View {
        Shell(theme: theme) {
            EscortAssignmentDetail(
                assignmentId: assignmentId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStartedAt: previewStartedAt,
                previewEscortRole: previewEscortRole,
                previewPermitNumber: previewPermitNumber,
                previewCorridorCoverage: previewCorridorCoverage
            )
        } nav: {
            BottomNav(
                leading: escortNavLeading_601(),
                trailing: escortNavTrailing_601(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_601() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                    isCurrent: false),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled",   isCurrent: true)]
}

private func escortNavTrailing_601() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map", isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("601 · Escort · Assignment Detail · Night") {
    EscortAssignmentDetailScreen(
        theme: Theme.dark,
        assignmentId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStartedAt: nil,
        previewEscortRole: nil,
        previewPermitNumber: nil,
        previewCorridorCoverage: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("601 · Escort · Assignment Detail · Afternoon") {
    EscortAssignmentDetailScreen(
        theme: Theme.light,
        assignmentId: "0",
        previewLoadNumber: "—",
        previewLane: "—",
        previewStartedAt: nil,
        previewEscortRole: nil,
        previewPermitNumber: nil,
        previewCorridorCoverage: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
