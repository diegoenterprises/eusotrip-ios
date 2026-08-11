//
//  ES09_EscortHome.swift
//  EusoTrip — Escort · Home (ES-09).
//
//  SUPERSEDES-BY-ADOPTION: `600_EscortHome.swift`. That brick stays on
//  disk and stays wired — `EscortNavRoute.map["home"]` still resolves to
//  "600" — because nav is single-writer owned and this fire does not
//  touch `EscortNavController.swift`. When the single writer rewires,
//  point "home" at `EscortHomeES09Screen` and 600 retires. Nothing here
//  edits, deletes or shadows 600: the symbols are distinct
//  (`EscortHome` vs `EscortHomeES09`).
//
//  Built from the ES-09 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-09 Escort Home.svg").
//
//  ARCHETYPE — HOME · daily-ops INSTRUMENT CLUSTER. The hero is a
//  16-hour DAY-RULER (05:00→21:00) carrying the on-duty band, a NOW
//  needle and today's escort block as one gradient bar. Beneath it sit
//  three instruments that deliberately do NOT share a shape: a cert
//  depletion bar, weekly earnings bars, and a marketplace pulse. The
//  day — not the portfolio — is the subject, which is what separates
//  this from the shipper home it shares an archetype with.
//
//  WIRING (verified against frontend/server/routers/escorts.ts this fire):
//    EXISTS escorts.getActiveJobs          escorts.ts:706   → today's block
//    EXISTS escorts.getUpcomingJobs        escorts.ts:738   → NEXT UP rows
//    EXISTS escorts.getDashboardStats      escorts.ts:675   → earnings + counts
//    EXISTS escorts.getCompletedJobs       escorts.ts:2423  → weekly bars
//    EXISTS escorts.getCertificationStatus escorts.ts:924   → cert countdown
//    EXISTS escorts.getPermitStats         escorts.ts:2199  → coverage ribbon
//    EXISTS escorts.getMarketplaceStats    escorts.ts:849   → market pulse
//    EXISTS escorts.getAvailableJobs       escorts.ts:771   → OFFER WAITING
//    STUB   duty clock — no proc, no `duty_status` column, no event. The
//           on-duty band paints ONLY when a duty stamp exists; with no
//           stamp it collapses to the bare NOW needle. We never draw a
//           duty band we cannot source.
//    STUB   offer expiry countdown — `loads` carries no offer-expiry
//           column, so the countdown renders only when the row supplies
//           a pickup date it can honestly count toward.
//
//  RBAC: every proc above is `protectedProcedure` + `resolveEscortUserId`
//  row-scoping (escorts.ts:11 / :75). No `loads.rate` for the shipper's
//  account, no carrier margin, no shipper identity is bound anywhere in
//  this file.
//
//  OFFLINE (§W): READ_CACHED(15m) via `EscortOfflineCache` — the whole
//  read model is snapshotted on every successful refresh and replayed on
//  failure with `EscortOfflineCache.stalenessLine(age:)` rendered under
//  the meta row and the LiveDot dropped to its cached register. Past the
//  15-minute ttl the cache refuses the snapshot and the screen shows its
//  offline state rather than stale numbers dressed as live. Every
//  mutation reachable from here is ONLINE_ONLY (escort outbox not yet
//  ported — PLANNED per Encyclopedia v2); no queue badge is ever drawn.
//
//  Powered by ESANG AI™.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

/// escorts.getActiveJobs · escorts.ts:706
private struct ES09ActiveJob: Codable, Identifiable {
    let id: String
    let jobNumber: String?
    let loadNumber: String?
    let status: String?
    let loadStatus: String?
    let position: String?
    let cargoType: String?
    let hazmatClass: String?
    let origin: String?
    let destination: String?
    let distance: Double?
    let pay: Double?
    let rateType: String?
    let pickupDate: String?
}

/// escorts.getUpcomingJobs · escorts.ts:738
private struct ES09UpcomingJob: Codable, Identifiable {
    let id: String
    let loadNumber: String?
    let position: String?
    let origin: String?
    let destination: String?
    let scheduledDate: String?
    let pay: Double?
    let distance: Double?
}

/// escorts.getDashboardStats · escorts.ts:675
private struct ES09DashboardStats: Codable {
    let activeJobs: Int?
    let upcomingJobs: Int?
    let completedThisMonth: Int?
    let monthlyEarnings: Double?
}

/// escorts.getCompletedJobs · escorts.ts:2423 (weekly bars are derived here,
/// client-side — no new proc is claimed for the sparkline).
private struct ES09CompletedJob: Codable, Identifiable {
    let id: String
    let loadNumber: String?
    let earnings: Double?
    let completedAt: String?
    let route: String?
}

/// One row of `states` off getCertificationStatusInternal · escorts.ts:487.
private struct ES09CertStateRow: Codable {
    let code: String
    let name: String
    let status: String          // active | expiring | expired
    let expirationDate: String  // "YYYY-MM-DD" or "—"
}

/// escorts.getCertificationStatus · escorts.ts:924
private struct ES09CertStatus: Codable {
    let total: Int?
    let active: Int?
    let expiringSoon: Int?
    let expired: Int?
    let statesCleared: [String]?
    let states: [ES09CertStateRow]?
}

/// escorts.getPermitStats · escorts.ts:2199
private struct ES09PermitStats: Codable {
    let activePermits: Int?
    let expiringSoon: Int?
    let statesCovered: Int?
    let certifications: Int?
}

/// escorts.getMarketplaceStats · escorts.ts:849
private struct ES09MarketStats: Codable {
    let availableJobs: Int?
    let urgentJobs: Int?
    let avgPay: Double?
    let newThisWeek: Int?
    let myApplications: Int?
}

/// escorts.getAvailableJobs · escorts.ts:771 — only the fields this screen
/// paints. Unknown keys are ignored by the decoder.
private struct ES09OfferRow: Codable, Identifiable {
    let id: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let distance: Double?
    let pay: Double?
    let pickupDate: String?
}

private struct ES09EmptyInput: Encodable {}
private struct ES09LimitInput: Encodable { let limit: Int }
private struct ES09BoardInput: Encodable { let filter: String?; let search: String? }
private struct ES09CompletedInput: Encodable { let limit: Int }

/// Everything this screen paints, in one Codable envelope so the whole
/// fold caches or refuses together. A half-cached home is a lying home.
private struct ES09Snapshot: Codable {
    var active: [ES09ActiveJob] = []
    var upcoming: [ES09UpcomingJob] = []
    var stats: ES09DashboardStats? = nil
    var completed: [ES09CompletedJob] = []
    var cert: ES09CertStatus? = nil
    var permits: ES09PermitStats? = nil
    var market: ES09MarketStats? = nil
    var offers: [ES09OfferRow] = []
}

// MARK: - Nav intents (this file never touches EscortNavController)

extension Notification.Name {
    static let esES09OpenTodaysMove = Notification.Name("esES09OpenTodaysMove")
    static let esES09OpenPreTrip    = Notification.Name("esES09OpenPreTrip")
    static let esES09OpenOffer      = Notification.Name("esES09OpenOffer")
}

// MARK: - Screen body

struct EscortHomeES09: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, live, cached, failed }

    @State private var phase: Phase = .loading
    @State private var snap = ES09Snapshot()
    /// Non-nil only while painting a cached snapshot. Drives the visible
    /// staleness line — the honesty law, rendered, not implied.
    @State private var cacheAge: TimeInterval? = nil

    private let cacheKey = "es09.home"
    private let cacheTTL: TimeInterval = 15 * 60      // READ_CACHED(15m)

    // Semantic inks that palette-swap with the SVG pair.
    private var isDark: Bool { scheme == .dark }
    private var amberInk: Color { isDark ? Color(hex: 0xFBBF24) : Color(hex: 0xB45309) }
    private var purpleInk: Color { isDark ? Color(hex: 0xCE93D8) : Color(hex: 0x7B1FA2) }
    private var orangeInk: Color { isDark ? Color(hex: 0xFB923C) : Color(hex: 0xC2410C) }
    private let leadBlue = Color(hex: 0x1473FF)
    private let hpOrange = Color(hex: 0xF97316)
    private let chasePurple = Color(hex: 0x9C27B0)
    private let amber = Color(hex: 0xF59E0B)
    /// Hero rim — the brand gradient at the SVG's 0.85 rim opacity.
    private let heroRim = LinearGradient(
        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            titleRow
            metaRow
            if let age = cacheAge {
                stalenessLine(age)
            }
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
            Text("✦ ESCORT · TODAY")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(companyCaps)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    /// The escort's own tenant. Never a literal — a hardcoded company name
    /// would tell every operator on the platform who they work for.
    private var companyCaps: String {
        if let cid = session.user?.companyId, !cid.isEmpty {
            return "COMPANY · \(cid)".uppercased()
        }
        return "INDEPENDENT ESCORT"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("Today")
                .font(.system(size: 30, weight: .bold)).tracking(-0.5)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(leadBlue).frame(width: 6, height: 6)
                Text(todayStamp)
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(palette.bgCardSoft)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            if let pos = todaysJob?.position, !pos.isEmpty {
                positionBadge(pos)
            }
            Text(blockCountLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(cacheAge == nil ? AnyShapeStyle(Brand.success) : AnyShapeStyle(palette.textTertiary))
                    .frame(width: 6, height: 6)
                Text(cacheAge == nil ? "live" : "cached")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            Text(operatorCaps)
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    /// §W honesty law: when a snapshot is on screen, say so, in words, in
    /// the place the reader is already looking.
    private func stalenessLine(_ age: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 9, weight: .bold))
            Text("\(EscortOfflineCache.stalenessLine(age: age)) · showing the last good read, not live")
                .font(EType.mono(.micro))
        }
        .foregroundStyle(amberInk)
    }

    private var operatorCaps: String {
        let name = session.user?.name ?? ""
        return name.isEmpty ? "ESCORT" : name
    }

    // MARK: Content ladder

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingBlock
        case .failed:
            failedBlock
        case .live, .cached:
            VStack(alignment: .leading, spacing: Space.s4) {
                heroDayRuler
                instrumentCluster
                nextUpBlock
                offerBlock
                coverageRibbon
                esangCard
                ctaPair
                Color.clear.frame(height: Space.s6)
            }
        }
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 88)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var failedBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Today didn't load")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text("No live read and no snapshot inside the 15-minute window. Nothing here is being guessed at.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            CTAButton(title: "Try again", action: { Task { await refresh() } })
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Hero — the day ruler

    private var heroDayRuler: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("TODAY · ASSIGNMENT BLOCK",
                         trailing: snap.active.isEmpty ? "NOTHING SCHEDULED"
                                                       : "\(snap.active.count) OF \(snap.active.count) · ACCEPTED")
            if let job = todaysJob {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Text(job.loadNumber ?? job.jobNumber ?? "—")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(palette.bgCardSoft)
                            .clipShape(Capsule())
                        if let pos = job.position, !pos.isEmpty { positionBadge(pos, solid: true) }
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(cacheAge == nil ? AnyShapeStyle(Brand.success) : AnyShapeStyle(palette.textTertiary))
                                .frame(width: 7, height: 7)
                            Text(cacheAge == nil ? "LIVE" : "CACHED")
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textPrimary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(palette.bgCard)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(job.origin ?? "—") → \(job.destination ?? "—")")
                                .font(.system(size: 17, weight: .bold)).tracking(-0.2)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.72)
                            Text(heroSubline(job))
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: Space.s3)
                        if let countdown = stageCountdown(job) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("STAGES IN")
                                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(countdown)
                                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(amberInk)
                            }
                        }
                    }

                    dayRuler(for: job)

                    HStack(spacing: Space.s4) {
                        eventDot(amber, stageLabel(job))
                        eventDot(leadBlue, rollLabel(job))
                        eventDot(Brand.success, releaseLabel(job))
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(heroRim, lineWidth: 1.5)
                )
            } else {
                emptyCard("No block on the ruler today",
                          "When dispatch seats you, the day fills in here — staging, roll, release.")
            }
        }
    }

    /// The 16-hour instrument. Fractions are computed from the real pickup
    /// stamp; when there is no stamp there is no band — only the needle.
    private func dayRuler(for job: ES09ActiveJob) -> some View {
        let dayStart: Double = 5, dayEnd: Double = 21
        let span = dayEnd - dayStart
        let nowH = hourOfDay(Date())
        let stageH = job.pickupDate.flatMap(parseISO).map(hourOfDay)
        let releaseH = stageH.map { min($0 + estimatedBlockHours(job), dayEnd) }

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let clampedNow = CGFloat((min(max(nowH, dayStart), dayEnd) - dayStart) / span) * w
                let blockStart = stageH.map { CGFloat((min(max($0, dayStart), dayEnd) - dayStart) / span) * w }
                let blockEnd = releaseH.map { CGFloat((min(max($0, dayStart), dayEnd) - dayStart) / span) * w }
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(palette.bgCardSoft)
                        .frame(height: 10)
                        .offset(y: 12)
                    if let s = blockStart, let e = blockEnd, e > s {
                        ZStack {
                            Capsule().fill(LinearGradient.diagonal)
                            Text("ESCORT BLOCK")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .frame(width: max(e - s, 10), height: 16)
                        .offset(x: s, y: 9)
                    }
                    Rectangle()
                        .fill(palette.textPrimary)
                        .frame(width: 2, height: 26)
                        .offset(x: clampedNow - 1, y: 6)
                    Circle()
                        .fill(palette.textPrimary)
                        .frame(width: 6, height: 6)
                        .offset(x: clampedNow - 3, y: 3)
                }
            }
            .frame(height: 34)

            HStack(spacing: 0) {
                ForEach([5, 7, 9, 11, 13, 15, 17, 19, 21], id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: h == 5 ? .leading : (h == 21 ? .trailing : .center))
                }
            }
        }
    }

    private func eventDot(_ tint: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: Instrument cluster (three unlike gauges — BentoGrid)

    private var instrumentCluster: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("DAY INSTRUMENTS", trailing: cacheAge == nil ? "LIVE" : "SNAPSHOT")
            HStack(spacing: Space.s2) {
                certInstrument
                earningsInstrument
                marketInstrument
            }
            .frame(height: 104)
        }
    }

    private var certInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                Text(soonestCert.map { "CERT · \($0.code)" } ?? "CERT")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(certCountdownLabel)
                    .font(.system(size: 23, weight: .heavy, design: .monospaced))
                    .foregroundStyle(certIsUrgent ? amberInk : palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                // Depletion against the proc's own 30-day expiring horizon.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft)
                        Capsule().fill(amber)
                            .frame(width: geo.size.width * certRemainingFraction)
                    }
                }
                .frame(height: 6)
                Text(certSubline)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private var earningsInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                Text("EARNINGS · \(monthCaps)")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(money(snap.stats?.monthlyEarnings))
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(weeklyBars.enumerated()), id: \.offset) { idx, frac in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(idx == weeklyBars.count - 1
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(leadBlue.opacity(isDark ? 0.40 : 0.30)))
                            .frame(height: max(4, 18 * frac))
                    }
                }
                .frame(height: 18)
                Text(earningsSubline)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private var marketInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("MARKET")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    Circle().fill(Brand.success).frame(width: 7, height: 7)
                }
                Text("\(snap.market?.availableJobs ?? 0) open")
                    .font(.system(size: 19, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(pulseBars.enumerated()), id: \.offset) { _, frac in
                        Capsule()
                            .fill(chasePurple.opacity(isDark ? 0.55 : 0.45))
                            .frame(width: 5, height: max(4, 20 * frac))
                    }
                }
                .frame(height: 20)
                Text(marketSubline)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private func instrumentShell<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.s3)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: NEXT UP

    private var nextUpBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("NEXT UP · ACCEPTED", trailing: "SEE ALL (\(snap.upcoming.count))")
            if snap.upcoming.isEmpty {
                emptyCard("Nothing accepted after today",
                          "Accepted moves land here with the seat, the miles and the pay.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snap.upcoming.prefix(2).enumerated()), id: \.element.id) { idx, row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(row.origin ?? "—") → \(row.destination ?? "—")")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Spacer(minLength: Space.s2)
                                Text(money(row.pay))
                                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            HStack(spacing: 8) {
                                if let pos = row.position, !pos.isEmpty { positionBadge(pos, compact: true) }
                                Text(upcomingSubline(row))
                                    .font(EType.mono(.micro))
                                    .foregroundStyle(palette.textTertiary)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s4)
                        if idx == 0 && snap.upcoming.count > 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    // MARK: OFFER WAITING (deep-links ES-10)

    @ViewBuilder
    private var offerBlock: some View {
        if let offer = snap.offers.first {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionLabel("OFFER WAITING", trailing: "\(snap.market?.urgentJobs ?? 0) URGENT")
                Button {
                    NotificationCenter.default.post(
                        name: .esES09OpenOffer, object: nil,
                        userInfo: ["jobId": offer.id])
                } label: {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Rectangle().fill(amber).frame(width: 3)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("NEW OFFER")
                                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                    .foregroundStyle(isDark ? Color(hex: 0x0B0B0F) : .white)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(amber).clipShape(Capsule())
                                Text("\(offer.origin ?? "—") → \(offer.destination ?? "—")")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.72)
                                Spacer(minLength: Space.s2)
                                Text(money(offer.pay))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            Text(offerSubline(offer))
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.78)
                        }
                        .padding(.vertical, Space.s3)
                        .padding(.trailing, Space.s4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(amber.opacity(isDark ? 0.14 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(amber.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Coverage ribbon (DataStat quartet)

    private var coverageRibbon: some View {
        HStack(spacing: 0) {
            ribbonCell("PERMITS", "\(snap.permits?.activePermits ?? 0) active", nil)
            ribbonDivider
            ribbonCell("EXPIRING", "\(snap.permits?.expiringSoon ?? 0)",
                       (snap.permits?.expiringSoon ?? 0) > 0 ? amberInk : nil)
            ribbonDivider
            ribbonCell("STATES", "\(snap.permits?.statesCovered ?? 0) covered", nil)
            ribbonDivider
            ribbonCell("CERTS", "\(snap.permits?.certifications ?? 0) on file", nil)
        }
        .padding(.vertical, Space.s2)
        .background(palette.textPrimary.opacity(isDark ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func ribbonCell(_ label: String, _ value: String, _ tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s3)
    }

    private var ribbonDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 18)
    }

    // MARK: ESANG orb (the calm expert — one concrete-number action)

    @ViewBuilder
    private var esangCard: some View {
        if let line = esangSuggestion {
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
                HStack(alignment: .center, spacing: Space.s3) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                        Circle().fill(Color.white.opacity(0.35))
                            .frame(width: 15, height: 15).offset(x: -6, y: -6).blur(radius: 3)
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            .frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("ESANG")
                                .font(.system(size: 10.5, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(LinearGradient.primary)
                            Text(line.headline)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        Text(line.body)
                            .font(.system(size: 9))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                        Text(line.figures)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s3)
                .padding(.horizontal, Space.s3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: CTAs — both ONLINE_ONLY downstream

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Open today's move", action: {
                guard let job = todaysJob else { return }
                NotificationCenter.default.post(
                    name: .esES09OpenTodaysMove, object: nil,
                    userInfo: ["assignmentId": job.id])
            })
            .frame(maxWidth: .infinity)
            .opacity(todaysJob == nil ? 0.45 : 1)
            .disabled(todaysJob == nil)

            Button {
                NotificationCenter.default.post(
                    name: .esES09OpenPreTrip, object: nil,
                    userInfo: todaysJob.map { ["assignmentId": $0.id] } ?? [:])
            } label: {
                Text("Pre-trip check")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 150)
        }
    }

    // MARK: Small parts

    private func sectionLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func emptyCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(body).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    /// Position badges per the escort design directive: LEAD blue ·
    /// CHASE purple · HIGH-POLE orange. Server enum is lead | chase | both.
    private func positionBadge(_ raw: String, solid: Bool = false, compact: Bool = false) -> some View {
        let key = raw.lowercased()
        let label: String
        let tint: Color
        switch key {
        case "lead":       label = "LEAD";       tint = leadBlue
        case "chase":      label = "CHASE";      tint = chasePurple
        case "both":       label = "LEAD+CHASE"; tint = leadBlue
        case "high_pole", "highpole": label = "HIGH-POLE"; tint = hpOrange
        default:           label = raw.uppercased(); tint = Brand.neutral
        }
        return Text(label)
            .font(.system(size: compact ? 8 : 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(solid ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3 : 4)
            .background(solid ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(isDark ? 0.20 : 0.14)))
            .clipShape(Capsule())
    }

    // MARK: Derived copy (numbers-first · time-relative · location-as-name)

    private var todaysJob: ES09ActiveJob? { snap.active.first }

    private var blockCountLine: String {
        let n = snap.active.count
        if n == 0 { return "No block today" }
        return n == 1 ? "1 block today" : "\(n) blocks today"
    }

    private var todayStamp: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var monthCaps: String {
        let f = DateFormatter(); f.dateFormat = "MMM"
        return f.string(from: Date()).uppercased()
    }

    private func heroSubline(_ job: ES09ActiveJob) -> String {
        var parts: [String] = []
        if let n = job.loadNumber, !n.isEmpty { parts.append(n) }
        if let d = job.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        if let c = job.cargoType, !c.isEmpty { parts.append(c) }
        if let h = job.hazmatClass, !h.isEmpty { parts.append("hazmat \(h)") }
        if let s = job.status, !s.isEmpty { parts.append(s.uppercased()) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func stageCountdown(_ job: ES09ActiveJob) -> String? {
        guard let d = job.pickupDate.flatMap(parseISO) else { return nil }
        let delta = d.timeIntervalSinceNow
        guard delta > 0 else { return nil }
        let h = Int(delta) / 3600, m = (Int(delta) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func stageLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "STAGE —" }
        return "STAGE \(clock(d))"
    }

    private func rollLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "ROLL —" }
        return "ROLL \(clock(d.addingTimeInterval(30 * 60)))"
    }

    private func releaseLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "RELEASE —" }
        return "RELEASE ~\(clock(d.addingTimeInterval(estimatedBlockHours(job) * 3600)))"
    }

    /// Block length from routed miles at a 45 mph escort average, floored at
    /// one hour. Derived, and labelled as an estimate wherever it prints.
    private func estimatedBlockHours(_ job: ES09ActiveJob) -> Double {
        guard let d = job.distance, d > 0 else { return 2 }
        return max(1, min(12, d / 45 + 0.5))
    }

    private func upcomingSubline(_ row: ES09UpcomingJob) -> String {
        var parts: [String] = []
        if let s = row.scheduledDate, !s.isEmpty { parts.append(s) }
        if let d = row.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        if let n = row.loadNumber, !n.isEmpty { parts.append(n) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func offerSubline(_ offer: ES09OfferRow) -> String {
        var parts: [String] = []
        if let n = offer.loadNumber, !n.isEmpty { parts.append(n) }
        if let d = offer.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        if let p = offer.pickupDate.flatMap(parseISO) {
            parts.append("pickup \(relativeShort(p))")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // Cert instrument -------------------------------------------------

    /// The credential closest to death: expiring rows first, then actives
    /// by date. Expired rows sort to the very front — a dead cert is the
    /// most urgent thing on the screen.
    private var soonestCert: ES09CertStateRow? {
        let rows = snap.cert?.states ?? []
        let dated = rows.compactMap { row -> (ES09CertStateRow, Date)? in
            guard let d = parseDay(row.expirationDate) else { return nil }
            return (row, d)
        }
        if let expired = dated.filter({ $0.0.status == "expired" }).min(by: { $0.1 < $1.1 }) {
            return expired.0
        }
        return dated.min(by: { $0.1 < $1.1 })?.0
    }

    private var certDaysLeft: Int? {
        guard let row = soonestCert, let d = parseDay(row.expirationDate) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }

    private var certCountdownLabel: String {
        guard let days = certDaysLeft else { return "—" }
        if days < 0 { return "EXPIRED" }
        return "\(days) d"
    }

    private var certIsUrgent: Bool { (certDaysLeft ?? 999) <= 30 }

    /// Against the proc's own 30-day `isExpiring` horizon (escorts.ts:487),
    /// not an invented window.
    private var certRemainingFraction: CGFloat {
        guard let days = certDaysLeft else { return 0 }
        return CGFloat(min(max(Double(days) / 30.0, 0), 1))
    }

    private var certSubline: String {
        guard let row = soonestCert else { return "No certs on file" }
        let when = row.expirationDate == "—" ? "no expiry on record" : "expires \(row.expirationDate)"
        return "\(row.name) · \(when)"
    }

    // Earnings instrument ---------------------------------------------

    /// Five weekly buckets ending this week, normalised to the tallest.
    /// Derived from getCompletedJobs rows — no sparkline proc is claimed.
    private var weeklyBars: [CGFloat] {
        let cal = Calendar.current
        var buckets = [Double](repeating: 0, count: 5)
        for job in snap.completed {
            guard let d = parseDay(job.completedAt ?? "") ?? parseISO(job.completedAt ?? "") else { continue }
            let weeks = cal.dateComponents([.weekOfYear], from: d, to: Date()).weekOfYear ?? 99
            guard weeks >= 0, weeks < 5 else { continue }
            buckets[4 - weeks] += job.earnings ?? 0
        }
        let top = buckets.max() ?? 0
        guard top > 0 else { return [0.15, 0.15, 0.15, 0.15, 0.15] }
        return buckets.map { CGFloat($0 / top) }
    }

    private var earningsSubline: String {
        let n = snap.stats?.completedThisMonth ?? 0
        let last = snap.completed.first
        var line = n == 1 ? "1 move" : "\(n) moves"
        if let last, let when = last.completedAt, !when.isEmpty { line += " · last \(when)" }
        return line
    }

    // Market instrument -----------------------------------------------

    /// Eight bars whose shape is seeded by the real counts, so the pulse
    /// moves when the board moves instead of animating a decoration.
    private var pulseBars: [CGFloat] {
        let open = Double(snap.market?.availableJobs ?? 0)
        let urgent = Double(snap.market?.urgentJobs ?? 0)
        guard open > 0 else { return Array(repeating: 0.2, count: 8) }
        let base = min(1.0, open / max(open, 40))
        let heat = min(1.0, urgent / max(open, 1))
        return (0..<8).map { i in
            let wave = 0.55 + 0.45 * sin(Double(i) * 0.9 + heat * 3)
            return CGFloat(min(1.0, max(0.18, base * wave + heat * 0.25)))
        }
    }

    private var marketSubline: String {
        var parts: [String] = []
        let urgent = snap.market?.urgentJobs ?? 0
        parts.append("\(urgent) urgent <48h")
        if let avg = snap.market?.avgPay, avg > 0 { parts.append("avg \(money(avg))") }
        return parts.joined(separator: " · ")
    }

    // ESANG -----------------------------------------------------------

    private struct ES09Suggestion { let headline: String; let body: String; let figures: String }

    /// Composed from data already on screen — concrete numbers only, no
    /// chat round-trip on this surface.
    private var esangSuggestion: ES09Suggestion? {
        guard let row = soonestCert, let days = certDaysLeft, days <= 45 else { return nil }
        let statesCovered = snap.permits?.statesCovered ?? 0
        if days < 0 {
            return ES09Suggestion(
                headline: "\(row.code) \(row.name) has lapsed",
                body: "Jobs gated on \(row.code) will refuse you at the eligibility check until this is back in force.",
                figures: "expired \(row.expirationDate) · \(statesCovered) states covered")
        }
        return ES09Suggestion(
            headline: "Renew the \(row.code) \(row.name)",
            body: "It carries \(statesCovered) covered state\(statesCovered == 1 ? "" : "s") on your wallet — a lapse takes them with it.",
            figures: "\(days) d left · expires \(row.expirationDate)")
    }

    // MARK: Formatting helpers

    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v < 1000 ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "—"
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func relativeShort(_ d: Date) -> String {
        let delta = d.timeIntervalSinceNow
        if delta < 0 { return "past" }
        let h = Int(delta) / 3600
        if h < 1 { return "\(Int(delta) / 60)m" }
        if h < 48 { return "\(h)h" }
        return "\(h / 24)d"
    }

    private func hourOfDay(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    private func parseISO(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private func parseDay(_ s: String) -> Date? {
        guard !s.isEmpty, s != "—" else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: String(s.prefix(10)))
    }

    // MARK: - Data plumbing (READ_CACHED(15m) · mutations ONLINE_ONLY)

    /// A read whose failure degrades one cell instead of the whole fold.
    /// The non-optional `let v: T` inside keeps `Output` unambiguous.
    private func softQuery<T: Decodable, I: Encodable>(_ path: String, _ input: I) async -> T? {
        do {
            let v: T = try await EusoTripAPI.shared.query(path, input: input)
            return v
        } catch {
            return nil
        }
    }

    private func refresh() async {
        if snap.active.isEmpty && snap.stats == nil { phase = .loading }
        do {
            async let active: [ES09ActiveJob] = EusoTripAPI.shared.query(
                "escorts.getActiveJobs", input: ES09EmptyInput())
            async let upcoming: [ES09UpcomingJob] = EusoTripAPI.shared.query(
                "escorts.getUpcomingJobs", input: ES09LimitInput(limit: 5))
            async let stats: ES09DashboardStats = EusoTripAPI.shared.query(
                "escorts.getDashboardStats", input: ES09EmptyInput())
            async let cert: ES09CertStatus = EusoTripAPI.shared.query(
                "escorts.getCertificationStatus", input: ES09EmptyInput())

            var next = ES09Snapshot()
            next.active = try await active
            next.upcoming = try await upcoming
            next.stats = try await stats
            next.cert = try await cert

            // Secondary reads: a failure here degrades a cell, it does not
            // take the fold down, and the cell shows a zero it can source.
            let completed: [ES09CompletedJob]? = await softQuery(
                "escorts.getCompletedJobs", ES09CompletedInput(limit: 20))
            let permits: ES09PermitStats? = await softQuery(
                "escorts.getPermitStats", ES09EmptyInput())
            let market: ES09MarketStats? = await softQuery(
                "escorts.getMarketplaceStats", ES09EmptyInput())
            let offers: [ES09OfferRow]? = await softQuery(
                "escorts.getAvailableJobs", ES09BoardInput(filter: nil, search: nil))
            next.completed = completed ?? []
            next.permits = permits
            next.market = market
            next.offers = offers ?? []

            await MainActor.run {
                snap = next
                cacheAge = nil
                phase = .live
            }
            EscortOfflineCache.store(next, key: cacheKey)
        } catch {
            // READ_CACHED(15m): replay the last good snapshot, say its age
            // out loud, and refuse it entirely once the ttl is blown.
            if let hit = EscortOfflineCache.load(ES09Snapshot.self, key: cacheKey, ttl: cacheTTL) {
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
}

// MARK: - Screen wrapper (Shell + escort role tab bar)

struct EscortHomeES09Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortHomeES09()
        } nav: {
            BottomNav(
                leading: es09NavLeading(),
                trailing: es09NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es09NavLeading() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                  isCurrent: true),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false)]
}

private func es09NavTrailing() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// `.task` does not run in the preview canvas, so both variants render in
// their loading register without touching the network.

#Preview("ES-09 · Escort Home · Dark") {
    EscortHomeES09Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-09 · Escort Home · Light") {
    EscortHomeES09Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
