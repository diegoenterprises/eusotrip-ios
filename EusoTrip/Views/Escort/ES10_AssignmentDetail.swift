//
//  ES10_AssignmentDetail.swift
//  EusoTrip — Escort · Assignment Detail (ES-10).
//
//  SUPERSEDES-BY-ADOPTION: `601_EscortAssignmentDetail.swift`. That brick
//  stays on disk and stays wired — `EscortNavRoute.map["assignments"]`
//  still resolves to "601" — because nav is single-writer owned and this
//  fire does not touch `EscortNavController.swift`. When the single
//  writer rewires, point "assignments" at `EscortAssignmentDetailES10Screen`
//  and 601 retires. Nothing here edits, deletes or shadows 601: the
//  symbols are distinct (`EscortAssignmentDetail` vs
//  `EscortAssignmentDetailES10`).
//
//  Built from the ES-10 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-10 Assignment Detail.svg").
//
//  ARCHETYPE — DETAIL · LIFECYCLE SPINE. One vertical spine carries the
//  whole life of a single assignment as three stations — OFFER, ACTIVE,
//  COMPLETED — on one scroll. The current station is the rimmed hero;
//  the two ahead render in their pending register. No map, no tabs, no
//  sheet: the spine IS the layout. That is what separates it from the
//  shipper Load Detail (map hero, stages reduced to a horizontal strip)
//  and from ES-07 Settlement (whose vertical nodes are priced LEGS of a
//  finished move — these are STATES, two of which have not happened).
//
//  WIRING (verified against frontend/server/routers/escorts.ts this fire):
//    EXISTS escorts.getJobDetails             escorts.ts:1979 → offer terms
//    EXISTS escorts.getActiveAssignmentDetail escorts.ts:3725 → active deepening
//    EXISTS escorts.acceptJob                 escorts.ts:1148 → ACCEPT
//    STUB   load dimensions (length/width/height) — `loads` carries
//           `weight` and `weightUnit` but NO lengthFt/widthFt/heightFt
//           columns, and `escorts.analyzeOversize` (escorts.ts:3237)
//           takes those three as CLIENT INPUT rather than reading them.
//           The three dimension cells therefore render em-dash unless an
//           oversize record supplies them. GVW and the oversize /
//           overweight flags are the envelope facts that ARE on the wire.
//    STUB   decline — there is no `escorts.declineJob` proc and no
//           `declined` value in the assignment status vocabulary. The
//           control dismisses the offer locally and SAYS SO. It never
//           claims a server decline.
//    STUB   move report — no `escorts.getMoveReport` proc, no
//           `move_report` table. The COMPLETED station composes the
//           report client-side from the assignment + settlement rows,
//           which is exactly why every ACTUAL cell is an em-dash.
//
//  CHAIN — ACCEPT is ONE-SIDED. `escorts.acceptJob` writes the accepted
//  row and returns with NO websocket fan-out at all, unlike
//  `applyForJob` (escorts.ts:890) which broadcasts to the LOAD channel
//  and to the catalyst + driver USER channels. The missing half is the
//  acceptance event. This screen therefore never tells the operator that
//  dispatch has been notified — the post-accept line says the opposite,
//  out loud.
//
//  OFFLINE (§W): offer terms + envelope READ_CACHED(10m) via
//  `EscortOfflineCache`, with `EscortOfflineCache.stalenessLine(age:)`
//  rendered directly under the expiry pill while a snapshot is on
//  screen. ACCEPT and DECLINE are ONLINE_ONLY(escort outbox not yet
//  ported — PLANNED per Encyclopedia v2): offline, the CTA disables
//  itself with an honest reason and never queues a commit it cannot
//  make. No queue badge is ever drawn.
//
//  RBAC: `protectedProcedure` + `resolveEscortUserId` row-scoping; the
//  detail proc re-checks `escortUserId` per row and 404s foreign rows.
//  No shipper identity, no carrier margin, no shipper-side `loads.rate`
//  is bound anywhere in this file.
//
//  Powered by ESANG AI™.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

/// escorts.getJobDetails · escorts.ts:1979
private struct ES10JobDetail: Codable {
    let id: String
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let origin: String?
    let destination: String?
    let rate: Double?
    let distance: Double?
    let pickupDate: String?
    let deliveryDate: String?
    let weight: Double?
    let specialInstructions: String?
    let position: String?
    let rateType: String?
}

/// escorts.getActiveAssignmentDetail · escorts.ts:3725 — the deepening
/// read that fills the ACTIVE station once the seat is taken.
private struct ES10AssignmentDeep: Codable {
    let id: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let escortRole: String?
    let startedAt: String?
    let permitNumber: String?
    let corridorCoverage: String?
    let status: String?
    let routedMiles: Double?
    let routeName: String?
    let hazmatClass: String?
    let unNumber: String?
    let oversizeFlag: Bool?
    let overweightFlag: Bool?
    let bridgeClearanceFt: Double?
    let leadVehicleId: String?
    let chaseVehicleId: String?
    let driverName: String?
    let driverPhone: String?
    let routeConfirmed: Bool?
}

/// escorts.acceptJob · escorts.ts:1148
private struct ES10AcceptResult: Decodable {
    let success: Bool?
    let jobId: String?
    let assignmentId: Int?
    let escortUserId: Int?
}

private struct ES10JobIdInput: Encodable { let jobId: String }
private struct ES10IdInput: Encodable { let id: String }

/// Both reads in one envelope so the surface caches or refuses together.
private struct ES10Snapshot: Codable {
    var detail: ES10JobDetail? = nil
    var deep: ES10AssignmentDeep? = nil
}

// MARK: - Nav intents (this file never touches EscortNavController)

extension Notification.Name {
    static let esES10Accepted     = Notification.Name("esES10Accepted")
    static let esES10OpenPreTrip  = Notification.Name("esES10OpenPreTrip")
}

// MARK: - Screen body

struct EscortAssignmentDetailES10: View {
    /// The assignment / job id this surface is scoped to. Passed by the
    /// caller; never guessed, never defaulted to "first row".
    let jobId: String

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, live, cached, failed }
    private enum AcceptState: Equatable {
        case idle
        case inFlight
        case accepted(String)     // assignment id echoed by the server
        case failed(String)
        case declinedLocally
    }

    @State private var phase: Phase = .loading
    @State private var snap = ES10Snapshot()
    @State private var cacheAge: TimeInterval? = nil
    @State private var accept: AcceptState = .idle

    private var cacheKey: String { "es10.assignment.\(jobId)" }
    private let cacheTTL: TimeInterval = 10 * 60      // READ_CACHED(10m)

    private var isDark: Bool { scheme == .dark }
    private var amberInk: Color { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309) }
    private var orangeInk: Color { isDark ? Color(hex: 0xFB923C) : Color(hex: 0xC2410C) }
    private var greenInk: Color { isDark ? Color(hex: 0x34D399) : Color(hex: 0x0B7A4B) }
    private var pendingInk: Color { isDark ? Color(hex: 0x4B5364) : Color(hex: 0xC2C9D2) }
    private let leadBlue = Color(hex: 0x1473FF)
    private let hpOrange = Color(hex: 0xF97316)
    private let chasePurple = Color(hex: 0x9C27B0)
    private let amber = Color(hex: 0xF59E0B)
    private let heroRim = LinearGradient(
        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            titleRow
            metaRow
            IridescentHairline()
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · ASSIGNMENT DETAIL")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(snap.detail?.loadNumber ?? snap.deep?.loadNumber ?? "—")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var titleRow: some View {
        Text(routeTitle)
            .font(.system(size: 26, weight: .bold)).tracking(-0.4)
            .foregroundStyle(LinearGradient.primary)
            .lineLimit(1).minimumScaleFactor(0.65)
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subTitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            HStack(spacing: Space.s2) {
                if let pos = snap.detail?.position ?? snap.deep?.escortRole, !pos.isEmpty {
                    positionBadge(pos)
                }
                if highPoleFlagged { positionBadge("high_pole") }
                HStack(spacing: 5) {
                    Circle()
                        .fill(cacheAge == nil ? AnyShapeStyle(stationTint) : AnyShapeStyle(palette.textTertiary))
                        .frame(width: 7, height: 7)
                    Text(stationLabel)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 0)
                Text(session.user?.name ?? "ESCORT")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Content ladder

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(palette.bgCardSoft)
                        .frame(height: 140)
                }
            }
            .redacted(reason: .placeholder)

        case .failed:
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("This assignment didn't load")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                Text("Nothing came back live, and there is no saved copy from the last 10 minutes. If this move is assigned to another escort it will stay blank by design — that is not a fault to work around.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                CTAButton(title: "Try again", action: { Task { await refresh() } })
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))

        case .live, .cached:
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionLabel("LIFECYCLE SPINE · ONE ASSIGNMENT, THREE STATIONS")
                spine
                Color.clear.frame(height: Space.s6)
            }
        }
    }

    // MARK: The spine

    private var spine: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Rail: travelled = gradient, ahead = dashed.
            SpineRailES10(activeIndex: currentStationIndex,
                          gradient: LinearGradient.diagonal,
                          dashTint: palette.borderStrong,
                          nodeFill: palette.bgCard,
                          nodeStroke: palette.borderStrong)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Space.s4) {
                offerStation
                activeStation
                completedStation
            }
        }
    }

    // Station 1 ------------------------------------------------------

    private var offerStation: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(currentStationIndex == 0 ? "OFFER · AWAITING YOU" : "OFFER · RESOLVED")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                if currentStationIndex == 0 {
                    Text(expiryPillText)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(isDark ? Color(hex: 0x0B0B0F) : .white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(amber).clipShape(Capsule())
                } else {
                    statusPill(acceptedPillText)
                }
            }

            if let age = cacheAge {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash").font(.system(size: 9, weight: .bold))
                    Text("\(EscortOfflineCache.stalenessLine(age: age)) · terms are a snapshot, not a live read")
                        .font(EType.mono(.micro))
                }
                .foregroundStyle(amberInk)
            }

            Text(offerContextLine)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            // Terms triplet (DataStat)
            HStack(alignment: .top, spacing: 0) {
                termCell("POSITION",
                         value: positionDisplay,
                         sub: highPoleFlagged ? "+ HIGH-POLE required" : nil,
                         subTint: orangeInk,
                         gradientValue: false)
                termDivider
                termCell("RATE",
                         value: rateDisplay,
                         sub: rateBasisLine,
                         subTint: palette.textSecondary,
                         gradientValue: false)
                termDivider
                termCell("EST PAY",
                         value: money(snap.detail?.rate),
                         sub: estPaySubline,
                         subTint: palette.textSecondary,
                         gradientValue: true)
            }

            Rectangle().fill(palette.borderFaint).frame(height: 1)

            acceptRow
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(currentStationIndex == 0 ? AnyShapeStyle(heroRim)
                                                       : AnyShapeStyle(palette.borderFaint),
                              lineWidth: currentStationIndex == 0 ? 1.5 : 1)
        )
    }

    @ViewBuilder
    private var acceptRow: some View {
        switch accept {
        case .accepted(let assignmentId):
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Brand.success)
                    Text("Seat taken · assignment \(assignmentId)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                // CHAIN A3 · one-sided. Say it, don't imply a fan-out.
                Text("Your acceptance is saved. Dispatch is NOT notified automatically — there is no live acceptance alert on this board yet, so tell them on comms if they're waiting.")
                    .font(EType.caption)
                    .foregroundStyle(amberInk)
            }

        case .declinedLocally:
            VStack(alignment: .leading, spacing: 5) {
                Text("Dismissed on this device")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Declining is not reported anywhere yet, so nothing was sent. The offer stays on the board until it expires or someone else takes it.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }

        default:
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    CTAButton(title: acceptTitle,
                              action: { Task { await commitAccept() } },
                              isLoading: accept == .inFlight)
                        .frame(maxWidth: .infinity)
                        .opacity(canCommit ? 1 : 0.45)
                        .disabled(!canCommit)

                    Button {
                        accept = .declinedLocally
                    } label: {
                        Text("Decline")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 104, height: 44)
                            .background(palette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if case .failed(let why) = accept {
                    Text(why)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                }

                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(commitFootnote)
                        .font(EType.mono(.micro))
                }
                .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // Station 2 ------------------------------------------------------

    private var activeStation: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(currentStationIndex >= 1 ? "ACTIVE · RUNNING" : "ACTIVE · ON ACCEPT")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                statusPill(currentStationIndex >= 1 ? (snap.deep?.corridorCoverage ?? "RUNNING") : "NOT STARTED")
            }

            Text(currentStationIndex >= 1
                 ? "Pre-trip check is on file · corridor coverage from the convoy spine"
                 : "Pre-trip check gates ROLL · convoy opens on the first position ping")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            HStack {
                Text("LOAD ENVELOPE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text(snap.detail?.loadNumber ?? snap.deep?.loadNumber ?? "—")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            // BentoGrid quartet. L / W / H have no columns on the wire —
            // they render em-dash and the footnote names the gap.
            HStack(spacing: 6) {
                envelopeCell("LENGTH", value: "—", sub: "no column", ringed: false)
                envelopeCell("WIDTH",  value: "—", sub: "no column", ringed: false)
                envelopeCell("HEIGHT", value: "—", sub: "no column", ringed: false)
                envelopeCell("GVW",
                             value: weightDisplay,
                             sub: (snap.deep?.overweightFlag == true) ? "> 80k OW" : "on the wire",
                             ringed: snap.deep?.overweightFlag == true)
            }

            Text("Length, width and height aren't stored on a load — only weight is. The dimension cells stay empty rather than guess.")
                .font(.system(size: 8.5))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)

            Text("POSITION & CONVOY")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: 6) {
                convoyChip(leadLabel, tint: leadBlue, filled: true)
                if highPoleFlagged { convoyChip("HIGH-POLE", tint: hpOrange, filled: true) }
                convoyChip(chaseLabel, tint: chasePurple, filled: chaseSeated)
                Spacer(minLength: 0)
                Text("790-ft law")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            Text(corridorLine)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(currentStationIndex == 1 ? AnyShapeStyle(heroRim)
                                                       : AnyShapeStyle(palette.borderFaint),
                              lineWidth: currentStationIndex == 1 ? 1.5 : 1)
        )
    }

    // Station 3 ------------------------------------------------------

    private var completedStation: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("COMPLETED · MOVE REPORT")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                statusPill(currentStationIndex == 2 ? "RELEASED" : "OPENS AT RELEASE")
            }

            Text("Fills at release · built from the assignment and settlement records (no standalone report yet)")
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            HStack {
                Spacer(minLength: 0)
                Text("PLANNED")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 88, alignment: .trailing)
                Text("ACTUAL")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 64, alignment: .trailing)
            }

            VStack(spacing: 7) {
                reportRow("Escorted miles", planned: milesDisplay)
                reportRow("Position-hours", planned: positionHoursDisplay)
                reportRow("Clearance checks", planned: clearanceDisplay, plannedTint: amberInk)
                reportRow("Jurisdiction handoffs", planned: "—")
                reportRow("Detention / holds", planned: "—")
                reportRow("Incidents", planned: "—")
            }

            Rectangle().fill(palette.borderFaint).frame(height: 1)

            HStack {
                Text("SETTLEMENT OPENS ON RELEASE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("\(money(snap.detail?.rate)) planned")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(currentStationIndex == 2 ? AnyShapeStyle(heroRim)
                                                       : AnyShapeStyle(palette.borderFaint),
                              lineWidth: currentStationIndex == 2 ? 1.5 : 1)
        )
    }

    private func reportRow(_ label: String, planned: String, plannedTint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Space.s2)
            Text(planned)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(plannedTint ?? palette.textPrimary)
                .frame(width: 88, alignment: .trailing)
            Text("—")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(pendingInk)
                .frame(width: 64, alignment: .trailing)
        }
    }

    // MARK: Small parts

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    private func statusPill(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(palette.textPrimary.opacity(isDark ? 0.07 : 0.05))
            .clipShape(Capsule())
    }

    private func termCell(_ label: String, value: String, sub: String?,
                          subTint: Color, gradientValue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientValue {
                    Text(value)
                        .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(subTint)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var termDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 52)
            .padding(.horizontal, Space.s2)
    }

    private func envelopeCell(_ label: String, value: String, sub: String, ringed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(ringed ? orangeInk : palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(value == "—" ? pendingInk : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(ringed ? orangeInk : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(ringed ? AnyShapeStyle(hpOrange.opacity(isDark ? 0.16 : 0.10))
                           : AnyShapeStyle(palette.bgCardSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        // SafetyRing — only around a cell that actually trips a rule.
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(ringed ? hpOrange.opacity(0.65) : .clear, lineWidth: 1.5))
    }

    private func convoyChip(_ text: String, tint: Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
            .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textTertiary))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    filled ? Color.clear : palette.textTertiary.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1, dash: filled ? [] : [3, 3]))
            )
    }

    private func positionBadge(_ raw: String) -> some View {
        let key = raw.lowercased()
        let label: String
        let tint: Color
        switch key {
        case "lead":       label = "LEAD";       tint = leadBlue
        case "chase":      label = "CHASE";      tint = chasePurple
        case "both", "lead+chase": label = "LEAD+CHASE"; tint = leadBlue
        case "high_pole", "highpole": label = "HIGH-POLE"; tint = hpOrange
        default:           label = raw.uppercased(); tint = Brand.neutral
        }
        return Text(label)
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.opacity(isDark ? 0.20 : 0.14))
            .clipShape(Capsule())
    }

    // MARK: Derived state

    /// 0 = offer · 1 = active · 2 = completed. Read off the real status
    /// vocabulary (pending | accepted | en_route | on_site | escorting |
    /// completed | cancelled), never assumed.
    private var currentStationIndex: Int {
        if case .accepted = accept { return 1 }
        let s = (snap.deep?.status ?? snap.detail?.status ?? "pending").lowercased()
        switch s {
        case "completed", "delivered", "released": return 2
        case "accepted", "en_route", "on_site", "escorting", "active", "in_transit": return 1
        default: return 0
        }
    }

    private var stationLabel: String {
        switch currentStationIndex {
        case 0: return cacheAge == nil ? "Offer live" : "Offer · cached"
        case 1: return "Running"
        default: return "Released"
        }
    }

    private var stationTint: Color {
        switch currentStationIndex {
        case 0: return amber
        case 1: return Brand.success
        default: return Brand.neutral
        }
    }

    private var routeTitle: String {
        let o = shortPlace(snap.detail?.origin ?? snap.deep?.origin)
        let d = shortPlace(snap.detail?.destination ?? snap.deep?.destination)
        guard !o.isEmpty || !d.isEmpty else { return "Assignment" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    private var subTitle: String {
        var parts: [String] = []
        if let m = snap.detail?.distance ?? snap.deep?.routedMiles, m > 0 {
            parts.append("\(Int(m.rounded())) mi")
        }
        if let r = snap.deep?.routeName, !r.isEmpty { parts.append(r) }
        if let p = snap.deep?.permitNumber, !p.isEmpty { parts.append("permit \(p)") }
        if let un = snap.deep?.unNumber, !un.isEmpty { parts.append("UN\(un)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var offerContextLine: String {
        var parts: [String] = []
        if let p = parseISO(snap.detail?.pickupDate) {
            parts.append("pickup \(stamp(p))")
        }
        if let d = parseISO(snap.detail?.deliveryDate) {
            parts.append("delivery \(stamp(d))")
        }
        if let notes = snap.detail?.specialInstructions, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? "Terms as posted" : parts.joined(separator: " · ")
    }

    private var positionDisplay: String {
        let raw = (snap.detail?.position ?? snap.deep?.escortRole ?? "").lowercased()
        switch raw {
        case "lead": return "LEAD"
        case "chase": return "CHASE"
        case "both", "lead+chase": return "LEAD+CHASE"
        case "": return "—"
        default: return raw.uppercased()
        }
    }

    /// The escort's own rate, per the assignment row. `rateType` is the
    /// server's own vocabulary — flat | per_mile — and is never assumed.
    private var rateDisplay: String {
        guard let rate = snap.detail?.rate, rate > 0 else { return "—" }
        let type = (snap.detail?.rateType ?? "").lowercased()
        return type.contains("mile") ? "\(money(rate))/mi" : money(rate)
    }

    private var rateBasisLine: String? {
        let type = snap.detail?.rateType ?? ""
        return type.isEmpty ? nil : "basis · \(type)"
    }

    private var estPaySubline: String? {
        guard let miles = snap.detail?.distance, miles > 0 else { return nil }
        return "\(Int(miles.rounded())) escorted mi"
    }

    /// The high-pole hat is inferred ONLY from the oversize flag the
    /// server actually computes — never from a height we don't have.
    private var highPoleFlagged: Bool { snap.deep?.oversizeFlag == true }

    private var leadLabel: String {
        if let l = snap.deep?.leadVehicleId, !l.isEmpty { return "LEAD · \(l)" }
        return "LEAD · YOU"
    }

    private var chaseLabel: String {
        if let c = snap.deep?.chaseVehicleId, !c.isEmpty { return "CHASE · \(c)" }
        return "CHASE · UNASSIGNED"
    }

    private var chaseSeated: Bool {
        !(snap.deep?.chaseVehicleId ?? "").isEmpty
    }

    private var corridorLine: String {
        var parts: [String] = []
        if let o = snap.detail?.origin ?? snap.deep?.origin, !o.isEmpty { parts.append(o) }
        if let d = snap.detail?.destination ?? snap.deep?.destination, !d.isEmpty { parts.append(d) }
        if let started = parseISO(snap.deep?.startedAt) {
            parts.append("rolling since \(stamp(started))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " → ")
    }

    private var weightDisplay: String {
        guard let w = snap.detail?.weight, w > 0 else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: w)) ?? "—"
    }

    private var milesDisplay: String {
        guard let m = snap.detail?.distance ?? snap.deep?.routedMiles, m > 0 else { return "—" }
        return "\(Int(m.rounded())) mi"
    }

    /// Routed miles at a 45 mph escort average. Derived, and it says so.
    private var positionHoursDisplay: String {
        guard let m = snap.detail?.distance ?? snap.deep?.routedMiles, m > 0 else { return "—" }
        return String(format: "%.1f h", m / 45)
    }

    private var clearanceDisplay: String {
        guard let ft = snap.deep?.bridgeClearanceFt, ft > 0 else { return "—" }
        return String(format: "%.1f ft", ft)
    }

    private var expiryPillText: String {
        guard let p = parseISO(snap.detail?.pickupDate) else { return "OFFER OPEN" }
        let delta = p.timeIntervalSinceNow
        guard delta > 0 else { return "PICKUP PASSED" }
        let h = Int(delta) / 3600
        return h < 48 ? "PICKUP IN \(h)H" : "PICKUP IN \(h / 24)D"
    }

    private var acceptedPillText: String {
        (snap.deep?.status ?? snap.detail?.status ?? "accepted").uppercased()
    }

    private var acceptTitle: String {
        guard canCommit else { return "Reconnect to accept" }
        let pay = money(snap.detail?.rate)
        return pay == "—" ? "Accept assignment" : "Accept · \(pay)"
    }

    /// ONLINE_ONLY, enforced in the UI as well as declared: a cached read
    /// means we cannot see the wire, so we do not pretend to write to it.
    private var canCommit: Bool {
        cacheAge == nil && accept != .inFlight && currentStationIndex == 0
    }

    private var commitFootnote: String {
        cacheAge == nil
            ? "ONLINE ONLY · accept commits live — no escort outbox yet"
            : "OFFLINE · accept is disabled, nothing is queued"
    }

    // MARK: Formatting helpers

    private func money(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v < 1000 ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "—"
    }

    private func shortPlace(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return s.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? s
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }

    /// Takes an optional so call sites read `parseISO(x?.y)` instead of
    /// chaining a `flatMap` through two layers of Optional.
    private func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    // MARK: - Data plumbing (READ_CACHED(10m) · ACCEPT ONLINE_ONLY)

    private func softQuery<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do {
            let v: T = try await EusoTripAPI.shared.query(path, input: input)
            return v
        } catch {
            return nil
        }
    }

    private func refresh() async {
        if snap.detail == nil { phase = .loading }
        do {
            // getJobDetails answers null for a foreign or missing row —
            // decode it as an optional and treat null as "not yours".
            let detail: ES10JobDetail? = try await EusoTripAPI.shared.query(
                "escorts.getJobDetails", input: ES10JobIdInput(jobId: jobId))
            guard let detail else {
                await MainActor.run { phase = .failed }
                return
            }
            // Deepening read — absent until the seat is taken, so a nil
            // here is a legitimate answer, not a failure.
            let deep: ES10AssignmentDeep? = await softQuery(
                "escorts.getActiveAssignmentDetail", ES10IdInput(id: jobId))

            var next = ES10Snapshot()
            next.detail = detail
            next.deep = deep

            await MainActor.run {
                snap = next
                cacheAge = nil
                phase = .live
            }
            EscortOfflineCache.store(next, key: cacheKey)
        } catch {
            if let hit = EscortOfflineCache.load(ES10Snapshot.self, key: cacheKey, ttl: cacheTTL) {
                await MainActor.run {
                    snap = hit.value
                    cacheAge = hit.age
                    phase = .cached
                }
            } else {
                await MainActor.run {
                    cacheAge = nil
                    phase = .failed
                }
            }
        }
    }

    /// ACCEPT — ONLINE_ONLY. The escort outbox does not exist, and the
    /// mutation path is not on the driver-only enqueue table, so a failure
    /// here is a failure: it is reported, never queued, never faked.
    private func commitAccept() async {
        guard canCommit else { return }
        await MainActor.run { accept = .inFlight }
        do {
            let result: ES10AcceptResult = try await EusoTripAPI.shared.mutation(
                "escorts.acceptJob", input: ES10JobIdInput(jobId: jobId))
            guard result.success == true else {
                await MainActor.run { accept = .failed("The seat was not confirmed. Nothing was recorded — you do not have this job.") }
                return
            }
            let assigned = result.assignmentId.map(String.init) ?? (result.jobId ?? jobId)
            await MainActor.run { accept = .accepted(assigned) }
            NotificationCenter.default.post(
                name: .esES10Accepted, object: nil,
                userInfo: ["jobId": jobId, "assignmentId": assigned])
            await refresh()
        } catch {
            await MainActor.run {
                accept = .failed("Accept did not go through — check signal and try again. Nothing is queued, so the job is still open.")
            }
        }
    }
}

// MARK: - The spine rail (travelled = gradient · ahead = dashed)

private struct SpineRailES10: View {
    let activeIndex: Int
    let gradient: LinearGradient
    let dashTint: Color
    let nodeFill: Color
    let nodeStroke: Color

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // Nodes sit against each station card's header line.
            let ys: [CGFloat] = [34, h * 0.5, h - 34]
            ZStack(alignment: .top) {
                // travelled
                Capsule()
                    .fill(gradient)
                    .frame(width: 2.5, height: max(ys[min(activeIndex, 2)] + 14, 20))
                    .position(x: 12, y: max(ys[min(activeIndex, 2)] + 14, 20) / 2)
                // ahead
                Path { p in
                    p.move(to: CGPoint(x: 12, y: ys[min(activeIndex, 2)] + 14))
                    p.addLine(to: CGPoint(x: 12, y: ys[2] + 6))
                }
                .stroke(dashTint, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 6]))

                ForEach(0..<3, id: \.self) { i in
                    node(isCurrent: i == activeIndex, isPast: i < activeIndex)
                        .position(x: 12, y: ys[i])
                }
            }
        }
    }

    @ViewBuilder
    private func node(isCurrent: Bool, isPast: Bool) -> some View {
        if isCurrent {
            ZStack {
                Circle().strokeBorder(gradient, lineWidth: 2).frame(width: 22, height: 22)
                Circle().fill(gradient).frame(width: 14, height: 14)
                Circle().fill(Color.white).frame(width: 5, height: 5)
            }
        } else if isPast {
            Circle().fill(gradient).frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(nodeFill)
                .overlay(Circle().strokeBorder(nodeStroke, lineWidth: 2))
                .frame(width: 12, height: 12)
        }
    }
}

// MARK: - Screen wrapper (Shell + escort role tab bar)

struct EscortAssignmentDetailES10Screen: View {
    let theme: Theme.Palette
    let jobId: String

    var body: some View {
        Shell(theme: theme) {
            EscortAssignmentDetailES10(jobId: jobId)
        } nav: {
            BottomNav(
                leading: es10NavLeading(),
                trailing: es10NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es10NavLeading() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: true)]
}

private func es10NavTrailing() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// `.task` does not run in the preview canvas, so both variants render in
// their loading register without touching the network.

#Preview("ES-10 · Assignment Detail · Dark") {
    EscortAssignmentDetailES10Screen(theme: Theme.dark, jobId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-10 · Assignment Detail · Light") {
    EscortAssignmentDetailES10Screen(theme: Theme.light, jobId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
