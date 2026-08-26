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
//  WEB PARITY ROUTE (blueprint field 1):
//    /escort → client/src/pages/EscortDashboardNW.tsx, registered
//    App.tsx:931 behind guard(ESCT), lazy import App.tsx:164. The older
//    EscortDashboard.tsx is superseded at the ROUTE level (DAW-ESC-01) and
//    kept on disk — it is NOT the parity surface. There is no /escort/home
//    route on the web; the escort root is /escort.
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
//    LIFECYCLE DOTS — escorts.getUpcomingJobs' OWN hard filter
//           status='accepted' escorts.ts:752 (REPOINT — the pre-remediation
//           header cited :751, which is the .innerJoin(loads, …) line
//           immediately above the .where). Dot 1 (ACCEPTED) is inked
//           because the row could not be in the result set otherwise; dots
//           2-3 (STAGE, ROLL) stay hollow because the proc returns no
//           status field that could advance them.
//
//  WRITE PATH (blueprint field 3):
//    ES-09 writes NOTHING. Every bound procedure is a `.query`, so no DB
//    row, no audit record and no broadcast originates on this surface. The
//    one write reachable from here is the Pre-trip CTA handing off to ES-06:
//      escorts.submitVehicleCheck escorts.ts:1208
//        → INSERT escort_vehicle_inspections escorts.ts:1239
//          (+ certificate row INSERT documents escorts.ts:1271)
//        → recordAuditEvent escorts.ts:1282
//          (AuditAction.RECORD_CREATED · auditService.ts:162)
//        → wsService.broadcastToChannel WS_CHANNELS.LOAD escorts.ts:1301,
//          with a WS_CHANNELS.DISPATCH_UPDATES fan-out on failure :1305
//    blockchainAuditTrail = STUB · escort-lane-blockchain-audit-absent. The
//    table is real (drizzle/schema.ts:10018, GAP-444) but escorts.ts holds
//    ZERO references to it across all 4,745 lines. The escort lane books
//    none of it, while peer routers insert it broadly — 53 files under
//    server/ carry an insert(blockchainAuditTrail) call, among them
//    wallet.ts (:1190, :1631, :1752, :3495, :4327) and
//    detentionAccessorials.ts (:909, :1409), plus dispatch.ts (10 insert
//    sites), loads.ts, drivers.ts, catalysts.ts, compliance.ts,
//    shippers.ts, appointments.ts, kyc.ts and fraud.ts. The gap is
//    escort-specific, not platform-wide. No escort event — not even the
//    pre-trip certificate — is chained today. The missing half is a
//    blockchainAuditTrail insert alongside recordAuditEvent in the escort
//    mutations. Named here, not faked, and no chain badge is drawn.
//
//  RBAC (blueprint field 4): every proc above is gated by
//  `roleProcedure(ROLES.ESCORT)` — factory _core/trpc.ts:216,
//  `escortProcedure = roleProcedure(ROLES.ESCORT)` _core/trpc.ts:228,
//  imported into escorts.ts:11 under the LOCAL ALIAS `protectedProcedure`.
//  The alias is cosmetic; the gate underneath is a real ROLE gate that
//  refuses a non-ESCORT session, not the generic authenticated procedure
//  the local name suggests. Row scope `resolveEscortUserId`
//  escorts.ts:138 (REPOINT — the pre-fire6 header cited :75, which is a
//  call site inside another helper, not the declaration). No `loads.rate`
//  for the shipper's account, no carrier margin, no shipper identity is
//  bound anywhere in this file.
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
//  ── CANON DELTA vs run-1 (canon gate 2026-08-23.1, fire 2026-08-26) ──
//  Every wiring pin above is carried VERBATIM from run-1; it is the
//  contract of record and nothing below edits a pin to match a face.
//  What changed is the SKIN only:
//    · eyebrow retired — the 10px all-caps 1.0-tracking identity row is
//      replaced by a sentence-case 12/600 orientation line;
//    · type scale floored at 12 and snapped to the exemplar histogram
//      10 · 12 · 14 · 15 · 17 · 28 · 34. 10 is reserved for bottom-nav
//      captions, which this file does not own (BottomNav does);
//    · every positive `.tracking()` deleted. Negative optical tracking
//      survives only on display type: -0.4 on the 28 screen title and
//      -0.6 on the 34 hero number;
//    · retired brand gradients withdrawn. `LinearGradient.primary`,
//      `LinearGradient.diagonal` and `IridescentHairline` no longer paint
//      here. The only gradients left are the three canon defs: ONE
//      EusoLine on the day-ruler spine, plus the ESANG orb + its
//      specular highlight;
//    · the primary command is a FLAT #0B66E5 fill — never a gradient —
//      so the shared `CTAButton` (gradient-backed, 17pt label) is not
//      used on this surface;
//    · colours are pinned to the §4 canon token table, light and dark,
//      instead of the ad-hoc inks run-1 carried;
//    · soft-fill position/state badges retired for the exemplar's dot +
//      ink-word treatment;
//    · the hero's single largest number is the stage countdown at 34/700,
//      with its 12px explainer beneath it;
//    · DUTY CLOCK — the header now prints the honest `Duty clock
//      unavailable` in tertiary ink. There is no duty-clock procedure and
//      no `escort_duty_status` column, so the verb stays SILENT and no
//      percentage, elapsed value, zero or dash-dressed-as-data is drawn.
//  The bottom bar is unchanged and remains bound to the shipped escort
//  enum HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME
//  (EscortNavController.swift:77-85; orb labels :63).
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

// MARK: - Canon tokens (§4 of the 2026-08-23.1 rework spec)
//
// The shared `Theme.Palette` is band-wide and predates this gate; its
// tertiary inks and inset tracks do not carry the canon pairs. Rather than
// reach across into a single-writer file, ES-09 pins its own tokens here.
// Every value below is one row of the §4 table, light column then dark —
// nothing is invented and nothing is interpolated.

private enum ES09Ink {
    /// Carried for completeness of the §4 row set. `Shell` owns the page
    /// field, so this screen never paints it — but the value is recorded
    /// here so the twin's background is checkable against the table.
    static func pageBg(_ dark: Bool)        -> Color { dark ? Color(hex: 0x030309) : Color(hex: 0xEEF0F5) }
    static func surface(_ dark: Bool)       -> Color { dark ? Color(hex: 0x0D0E1A) : Color(hex: 0xFFFFFF) }
    static func track(_ dark: Bool)         -> Color { dark ? Color(hex: 0x0B0C16) : Color(hex: 0xE6E9EF) }
    static func hairline(_ dark: Bool)      -> Color { dark ? Color(hex: 0x25283A) : Color(hex: 0xD8DDE6) }
    static func primary(_ dark: Bool)       -> Color { dark ? Color(hex: 0xF5F5F7) : Color(hex: 0x0D1117) }
    static func secondary(_ dark: Bool)     -> Color { dark ? Color(hex: 0xAAB2BB) : Color(hex: 0x52606D) }
    static func tertiary(_ dark: Bool)      -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x596978) }
    /// Action primary is deliberately identical on both twins — the CTA is
    /// the one surface that must not shift register between themes.
    static let action                        = Color(hex: 0x0B66E5)
    static func link(_ dark: Bool)          -> Color { dark ? Color(hex: 0x4DA3FF) : Color(hex: 0x075FAB) }
    static let warnDot                       = Color(hex: 0xFFA726)
    static func warnInk(_ dark: Bool)       -> Color { dark ? Color(hex: 0xFFA726) : Color(hex: 0x7A4400) }
    static let successDot                    = Color(hex: 0x00C48C)
    static func successInk(_ dark: Bool)    -> Color { dark ? Color(hex: 0x00C48C) : Color(hex: 0x006B4D) }
    /// Accent carries the chase / secondary role.
    static func accent(_ dark: Bool)        -> Color { dark ? Color(hex: 0xD28BEB) : Color(hex: 0x6B2B83) }
    static func esangRegion(_ dark: Bool)   -> Color { dark ? Color(hex: 0x2A2038) : Color(hex: 0xE8DDFC) }
    static func esangProof(_ dark: Bool)    -> Color { dark ? Color(hex: 0xAAB2BB) : Color(hex: 0x52606D) }
    static let neutralDot                    = Color(hex: 0x6B7280)
    static func ctaStroke(_ dark: Bool)     -> Color { dark ? Color(hex: 0x7F8996) : Color(hex: 0x778391) }
}

/// §5 — the only three gradients that survive the canon gate.
private enum ES09Grad {
    /// `eusoLine`. Used EXACTLY ONCE on this screen: the day-ruler spine,
    /// which is the one temporal object the screen is about.
    static let eusoLine = LinearGradient(
        stops: [.init(color: Color(hex: 0x1473FF), location: 0.0),
                .init(color: Color(hex: 0x813FF5), location: 0.52),
                .init(color: Color(hex: 0xBE01FF), location: 1.0)],
        startPoint: .leading, endPoint: .trailing)

    /// `esangOrb` — the counsel dot, and nowhere else.
    static let esangOrb = LinearGradient(
        stops: [.init(color: Color(hex: 0x1473FF), location: 0.0),
                .init(color: Color(hex: 0x813FF5), location: 0.52),
                .init(color: Color(hex: 0xBE01FF), location: 1.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// `orbSpec` — the specular highlight that rides on the counsel dot.
    static func orbSpec(diameter: CGFloat) -> RadialGradient {
        RadialGradient(
            stops: [.init(color: Color.white.opacity(0.85), location: 0.0),
                    .init(color: Color.white.opacity(0.12), location: 0.35),
                    .init(color: Color.white.opacity(0.0),  location: 1.0)],
            center: UnitPoint(x: 0.32, y: 0.28),
            startRadius: 0, endRadius: diameter * 0.75)
    }
}

/// §3 — the exemplar histogram, spelled out so no call site can drift below
/// the floor. 10 belongs to bottom-nav captions, which `BottomNav` owns.
private enum ES09Type {
    /// §3 — tabular numerics on every money and countdown value.
    static let heroNumber   = Font.system(size: 34, weight: .bold, design: .default).monospacedDigit()
    static let screenTitle  = Font.system(size: 28, weight: .bold)
    static let large        = Font.system(size: 17, weight: .semibold)
    static let largeValue   = Font.system(size: 17, weight: .bold, design: .monospaced)
    static let rowTitle     = Font.system(size: 15, weight: .semibold)
    static let money        = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let chevron      = Font.system(size: 14, weight: .semibold)
    static let label        = Font.system(size: 12, weight: .semibold)
    static let body         = Font.system(size: 12, weight: .medium)
    static let mono         = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoStrong   = Font.system(size: 12, weight: .bold, design: .monospaced)
}

// MARK: - Nav intents (this file never touches EscortNavController)

extension Notification.Name {
    static let esES09OpenTodaysMove = Notification.Name("esES09OpenTodaysMove")
    static let esES09OpenPreTrip    = Notification.Name("esES09OpenPreTrip")
    static let esES09OpenOffer      = Notification.Name("esES09OpenOffer")
}

// MARK: - Screen body

struct EscortHomeES09: View {
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

    // Canon inks, resolved for the active twin.
    private var isDark: Bool { scheme == .dark }
    private var inkPrimary: Color   { ES09Ink.primary(isDark) }
    private var inkSecondary: Color { ES09Ink.secondary(isDark) }
    private var inkTertiary: Color  { ES09Ink.tertiary(isDark) }
    private var surface: Color      { ES09Ink.surface(isDark) }
    private var track: Color        { ES09Ink.track(isDark) }
    private var hairline: Color     { ES09Ink.hairline(isDark) }
    private var warnInk: Color      { ES09Ink.warnInk(isDark) }
    private var successInk: Color   { ES09Ink.successInk(isDark) }
    private var accentInk: Color    { ES09Ink.accent(isDark) }
    private var linkInk: Color      { ES09Ink.link(isDark) }
    private var esangProof: Color   { ES09Ink.esangProof(isDark) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            orientationRow
            titleRow
            metaRow
            if let age = cacheAge {
                stalenessLine(age)
            }
            // Canon hairline — flat, not iridescent. The one iridescent
            // spine this screen is allowed goes on the day ruler.
            Rectangle().fill(hairline).frame(height: 1)
            content
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: Header

    /// Sentence case, 12/600, zero tracking. The run-1 eyebrow shouted at
    /// 10px all-caps on 1.0 tracking; both were retired by the canon gate.
    private var orientationRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(companyLine)
                .font(ES09Type.label)
                .foregroundStyle(inkSecondary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(todayStamp)
                .font(ES09Type.mono)
                .foregroundStyle(inkSecondary)
                .lineLimit(1)
        }
    }

    /// The escort's own tenant. Never a literal — a hardcoded company name
    /// would tell every operator on the platform who they work for.
    private var companyLine: String {
        if let cid = session.user?.companyId, !cid.isEmpty {
            return "Escort · \(cid)"
        }
        return "Escort · independent"
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            // §3 — screen title 28 / 700 / -0.4. The one 28 on the screen.
            Text("Today")
                .font(ES09Type.screenTitle).tracking(-0.4)
                .foregroundStyle(inkPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            // §9 TRUTH LAW — there is no duty-clock procedure and no
            // `escort_duty_status` column, so the elapsed-duty value run-1
            // painted is WITHDRAWN. The verb is logged SILENT and the face
            // says so in tertiary ink rather than printing a zero, a dash
            // dressed as data, or an extrapolation.
            Text("Duty clock unavailable")
                .font(ES09Type.body)
                .foregroundStyle(inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            if let pos = todaysJob?.position, !pos.isEmpty {
                positionBadge(pos)
            }
            Text(blockCountLine)
                .font(ES09Type.body)
                .foregroundStyle(inkSecondary)
            HStack(spacing: 5) {
                Circle()
                    .fill(cacheAge == nil ? ES09Ink.successDot : ES09Ink.neutralDot)
                    .frame(width: 6, height: 6)
                Text(cacheAge == nil ? "live" : "cached")
                    .font(ES09Type.label)
                    .foregroundStyle(inkSecondary)
            }
            Spacer(minLength: 0)
            Text(operatorLine)
                .font(ES09Type.mono)
                .foregroundStyle(inkTertiary)
                .lineLimit(1)
        }
    }

    /// §W honesty law: when a snapshot is on screen, say so, in words, in
    /// the place the reader is already looking.
    private func stalenessLine(_ age: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(ES09Type.label)
            Text("\(EscortOfflineCache.stalenessLine(age: age)) · showing the last good read, not live")
                .font(ES09Type.mono)
        }
        .foregroundStyle(warnInk)
    }

    private var operatorLine: String {
        let name = session.user?.name ?? ""
        return name.isEmpty ? "Escort" : name
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
                    .fill(track)
                    .frame(height: 88)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var failedBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Today didn't load")
                .font(ES09Type.rowTitle).foregroundStyle(inkPrimary)
            Text("No live read and no snapshot inside the 15-minute window. Nothing here is being guessed at.")
                .font(ES09Type.body).foregroundStyle(inkSecondary)
            primaryCommand("Try again") { Task { await refresh() } }
        }
        .padding(Space.s4)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(hairline, lineWidth: 1))
    }

    // MARK: Hero — the day ruler

    private var heroDayRuler: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("Today's assignment",
                         trailing: snap.active.isEmpty ? "Nothing scheduled"
                                                       : "\(snap.active.count) accepted")
            if let job = todaysJob {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Text(job.loadNumber ?? job.jobNumber ?? "—")
                            .font(ES09Type.mono)
                            .foregroundStyle(inkSecondary)
                        if let pos = job.position, !pos.isEmpty { positionBadge(pos) }
                        Spacer(minLength: 0)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(cacheAge == nil ? ES09Ink.successDot : ES09Ink.neutralDot)
                                .frame(width: 6, height: 6)
                            Text(cacheAge == nil ? "Accepted · live" : "Accepted · cached")
                                .font(ES09Type.label)
                                .foregroundStyle(cacheAge == nil ? successInk : inkTertiary)
                        }
                    }

                    // §8 — one hero surface carrying the screen's single
                    // largest number, with a 12px explainer under it. This
                    // is the one 34 on the screen.
                    if let countdown = stageCountdown(job) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(countdown)
                                .font(ES09Type.heroNumber).tracking(-0.6)
                                .foregroundStyle(inkPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(stageExplainer(job))
                                .font(ES09Type.body)
                                .foregroundStyle(inkSecondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(job.origin ?? "—") → \(job.destination ?? "—")")
                            .font(ES09Type.large)
                            .foregroundStyle(inkPrimary)
                            .lineLimit(1).minimumScaleFactor(0.72)
                        Text(heroSubline(job))
                            .font(ES09Type.mono)
                            .foregroundStyle(inkTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }

                    dayRuler(for: job)

                    HStack(spacing: Space.s4) {
                        eventDot(ES09Ink.warnDot, stageLabel(job))
                        eventDot(ES09Ink.action, rollLabel(job))
                        eventDot(ES09Ink.successDot, releaseLabel(job))
                    }
                }
                .padding(Space.s4)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(hairline, lineWidth: 1)
                )
            } else {
                emptyCard("No block on the ruler today",
                          "When dispatch seats you, the day fills in here — staging, roll, release.")
            }
        }
    }

    /// The 16-hour instrument. Fractions are computed from the real pickup
    /// stamp; when there is no stamp there is no band — only the needle.
    /// This spine carries the screen's ONE EusoLine (§5) and nothing else
    /// on the surface is allowed to reach for it.
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
                        .fill(track)
                        .frame(height: 6)
                        .offset(y: 10)
                    if let s = blockStart, let e = blockEnd, e > s {
                        Capsule()
                            .fill(ES09Grad.eusoLine)
                            .frame(width: max(e - s, 10), height: 6)
                            .offset(x: s, y: 10)
                    }
                    // The NOW needle. Sourced from the device clock, which
                    // is the only clock this screen can honestly cite.
                    Rectangle()
                        .fill(inkPrimary)
                        .frame(width: 2, height: 14)
                        .offset(x: clampedNow - 1, y: 6)
                }
            }
            .frame(height: 22)

            HStack(spacing: 0) {
                ForEach([5, 9, 13, 17, 21], id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(ES09Type.mono)
                        .foregroundStyle(inkTertiary)
                        .frame(maxWidth: .infinity, alignment: h == 5 ? .leading : (h == 21 ? .trailing : .center))
                }
            }
        }
    }

    private func eventDot(_ tint: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(ES09Type.body)
                .foregroundStyle(inkSecondary)
                .lineLimit(1)
        }
    }

    // MARK: Instrument cluster (three unlike gauges — BentoGrid)

    private var instrumentCluster: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("Day instruments", trailing: cacheAge == nil ? "Live" : "Snapshot")
            HStack(spacing: Space.s2) {
                certInstrument
                earningsInstrument
                marketInstrument
            }
            .frame(height: 118)
        }
    }

    private var certInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                Text(soonestCert.map { "Cert · \($0.code)" } ?? "Cert")
                    .font(ES09Type.label)
                    .foregroundStyle(inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(certCountdownLabel)
                    .font(ES09Type.largeValue)
                    .foregroundStyle(certIsUrgent ? warnInk : inkPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // Depletion against the proc's own 30-day expiring horizon.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        Capsule().fill(ES09Ink.warnDot)
                            .frame(width: geo.size.width * certRemainingFraction)
                    }
                }
                .frame(height: 6)
                Text(certSubline)
                    .font(ES09Type.body)
                    .foregroundStyle(inkTertiary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private var earningsInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                Text("Earnings · \(monthShort)")
                    .font(ES09Type.label)
                    .foregroundStyle(inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(money(snap.stats?.monthlyEarnings))
                    .font(ES09Type.largeValue)
                    .foregroundStyle(inkPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(alignment: .bottom, spacing: 5) {
                    if weeklyBars.isEmpty {
                        Text("No settled moves in the last 5 weeks")
                            .font(ES09Type.body)
                            .foregroundStyle(inkTertiary)
                            .lineLimit(2).minimumScaleFactor(0.85)
                    } else {
                        ForEach(Array(weeklyBars.enumerated()), id: \.offset) { idx, frac in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(idx == weeklyBars.count - 1
                                      ? ES09Ink.action
                                      : ES09Ink.action.opacity(isDark ? 0.40 : 0.30))
                                .frame(height: max(4, 18 * frac))
                        }
                    }
                }
                .frame(height: 18)
                Text(earningsSubline)
                    .font(ES09Type.body)
                    .foregroundStyle(inkTertiary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private var marketInstrument: some View {
        instrumentShell {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Market")
                        .font(ES09Type.label)
                        .foregroundStyle(inkSecondary)
                    Spacer(minLength: 0)
                    Circle().fill(ES09Ink.successDot).frame(width: 6, height: 6)
                }
                Text("\(snap.market?.availableJobs ?? 0) open")
                    .font(ES09Type.largeValue)
                    .foregroundStyle(inkPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                // §9 TRUTH LAW — run-1 drew eight "pulse" bars whose heights
                // came from a sine function seeded by the counts. There is no
                // time series on the wire: getMarketplaceStats returns
                // scalars only. Eight bars implied eight buckets that do not
                // exist, so the wave is WITHDRAWN. What replaces it is the
                // one proportion both scalars can honestly support — urgent
                // against open — and it paints only when open > 0.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(track)
                        if let frac = urgentFraction {
                            Capsule().fill(accentInk)
                                .frame(width: geo.size.width * frac)
                        }
                    }
                }
                .frame(height: 6)
                Text(marketSubline)
                    .font(ES09Type.body)
                    .foregroundStyle(inkTertiary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
        }
    }

    private func instrumentShell<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        inner()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.s3)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(hairline, lineWidth: 1))
    }

    // MARK: NEXT UP

    private var nextUpBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("Next up · accepted",
                         trailing: "See all (\(snap.upcoming.count))",
                         trailingIsLink: true)
            if snap.upcoming.isEmpty {
                emptyCard("Nothing accepted after today",
                          "Accepted moves land here with the seat, the miles and the pay.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snap.upcoming.prefix(2).enumerated()), id: \.element.id) { idx, row in
                        // 14-kit ListRow anatomy: 40×40 rx10 icon chip +
                        // title/sub + lifecycle dots + right pill + money.
                        HStack(alignment: .center, spacing: Space.s3) {
                            listRowIconChip(row.position ?? "")
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("\(row.origin ?? "—") → \(row.destination ?? "—")")
                                        .font(ES09Type.rowTitle)
                                        .foregroundStyle(inkPrimary)
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                    Spacer(minLength: Space.s2)
                                    Text(money(row.pay))
                                        .font(ES09Type.money)
                                        .foregroundStyle(inkPrimary)
                                }
                                HStack(spacing: 8) {
                                    Text(upcomingSubline(row))
                                        .font(ES09Type.mono)
                                        .foregroundStyle(inkTertiary)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: Space.s2)
                                    lifecycleDots(row.position ?? "")
                                    if let pos = row.position, !pos.isEmpty {
                                        positionBadge(pos)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, Space.s3)
                        .padding(.horizontal, Space.s4)
                        if idx == 0 && snap.upcoming.count > 1 {
                            Rectangle().fill(hairline).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1))
            }
        }
    }

    /// The 14-kit ListRow leading chip. `Radius` carries no 10-pt token
    /// (sm 8 · md 12 · lg 16 · xl 20), so the kit's chip value is spelled
    /// out here rather than rounded to the nearest token.
    private enum ListRowChip {
        static let side: CGFloat = 40
        static let radius: CGFloat = 10
    }

    private func listRowIconChip(_ position: String) -> some View {
        RoundedRectangle(cornerRadius: ListRowChip.radius, style: .continuous)
            .fill(track)
            .frame(width: ListRowChip.side, height: ListRowChip.side)
            .overlay(
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(ES09Type.large)
                    .foregroundStyle(positionInk(position))
            )
    }

    /// ACCEPTED · STAGE · ROLL. Only dot 1 is inked, and that is not a
    /// decision — `escorts.getUpcomingJobs` hard-filters status='accepted'
    /// (escorts.ts:752) and returns no status field, so nothing on the wire
    /// could advance dots 2-3. Hollow means "not on the wire", never "not
    /// yet happened dressed as known".
    private func lifecycleDots(_ position: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(positionInk(position)).frame(width: 5, height: 5)
            Circle().fill(hairline).frame(width: 5, height: 5)
            Circle().fill(hairline).frame(width: 5, height: 5)
        }
    }

    /// Position dot tints, pinned to the §4 table. LEAD reads on the action
    /// token, CHASE on the accent token, HIGH-POLE on the warn token — §4
    /// carries no fourth role colour and none is invented here.
    private func positionTint(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "chase": return ES09Ink.accent(isDark)
        case "high_pole", "highpole", "high-pole": return ES09Ink.warnDot
        default: return ES09Ink.action
        }
    }

    private func positionInk(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "chase": return ES09Ink.accent(isDark)
        case "high_pole", "highpole", "high-pole": return ES09Ink.warnInk(isDark)
        default: return ES09Ink.action
        }
    }

    // MARK: OFFER WAITING (deep-links ES-10)

    @ViewBuilder
    private var offerBlock: some View {
        if let offer = snap.offers.first {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionLabel("Offer waiting", trailing: "\(snap.market?.urgentJobs ?? 0) urgent")
                Button {
                    NotificationCenter.default.post(
                        name: .esES09OpenOffer, object: nil,
                        userInfo: ["jobId": offer.id])
                } label: {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Circle().fill(ES09Ink.warnDot)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("\(offer.origin ?? "—") → \(offer.destination ?? "—")")
                                    .font(ES09Type.rowTitle)
                                    .foregroundStyle(inkPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.72)
                                Spacer(minLength: Space.s2)
                                Text(money(offer.pay))
                                    .font(ES09Type.money)
                                    .foregroundStyle(inkPrimary)
                            }
                            Text(offerSubline(offer))
                                .font(ES09Type.body)
                                .foregroundStyle(inkSecondary)
                                .lineLimit(1).minimumScaleFactor(0.78)
                        }
                    }
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Coverage ribbon (DataStat quartet)

    private var coverageRibbon: some View {
        HStack(spacing: 0) {
            ribbonCell("Permits", "\(snap.permits?.activePermits ?? 0) active", nil)
            ribbonDivider
            ribbonCell("Expiring", "\(snap.permits?.expiringSoon ?? 0)",
                       (snap.permits?.expiringSoon ?? 0) > 0 ? warnInk : nil)
            ribbonDivider
            ribbonCell("States", "\(snap.permits?.statesCovered ?? 0) covered", nil)
            ribbonDivider
            ribbonCell("Certs", "\(snap.permits?.certifications ?? 0) on file", nil)
        }
        .padding(.vertical, Space.s3)
        .background(track)
        // 14-kit "inner" radius. `Radius` has no 14-pt token (md 12 / lg 16),
        // so the kit value is spelled out rather than rounded to a token.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func ribbonCell(_ label: String, _ value: String, _ tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(ES09Type.body)
                .foregroundStyle(inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(value)
                .font(ES09Type.monoStrong)
                .foregroundStyle(tint ?? inkPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s3)
    }

    private var ribbonDivider: some View {
        Rectangle().fill(hairline).frame(width: 1, height: 22)
    }

    // MARK: ESANG counsel (one soft region — the calm expert)

    @ViewBuilder
    private var esangCard: some View {
        if let line = esangSuggestion {
            HStack(alignment: .top, spacing: Space.s3) {
                // The only place on this screen that reaches for the orb
                // gradient pair, per §5.
                ZStack {
                    Circle().fill(ES09Grad.esangOrb)
                    Circle().fill(ES09Grad.orbSpec(diameter: 20))
                }
                .frame(width: 20, height: 20)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(line.headline)
                        .font(ES09Type.rowTitle)
                        .foregroundStyle(inkPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                    Text(line.body)
                        .font(ES09Type.body)
                        .foregroundStyle(esangProof)
                        .lineLimit(2)
                    // Source + proposal boundary, on the face, always.
                    Text("\(line.figures) · proposal — you decide")
                        .font(ES09Type.body)
                        .foregroundStyle(esangProof)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(ES09Type.chevron)
                    .foregroundStyle(esangProof)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ES09Ink.esangRegion(isDark))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    // MARK: Command dock — both ONLINE_ONLY downstream

    /// §8 command dock: 52-pt tall, rx 12, primary is a FLAT #0B66E5 fill
    /// with a white 15/600 label. The shared `CTAButton` is gradient-backed
    /// at a 17-pt label, so it is deliberately not used on this surface.
    private func primaryCommand(_ title: String,
                                enabled: Bool = true,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ES09Type.rowTitle)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(ES09Ink.action)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }

    private func secondaryCommand(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ES09Type.rowTitle)
                .foregroundStyle(inkPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(ES09Ink.ctaStroke(isDark), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            primaryCommand("Open today's move", enabled: todaysJob != nil) {
                guard let job = todaysJob else { return }
                NotificationCenter.default.post(
                    name: .esES09OpenTodaysMove, object: nil,
                    userInfo: ["assignmentId": job.id])
            }
            .frame(maxWidth: .infinity)

            secondaryCommand("Pre-trip check") {
                NotificationCenter.default.post(
                    name: .esES09OpenPreTrip, object: nil,
                    userInfo: todaysJob.map { ["assignmentId": $0.id] } ?? [:])
            }
            .frame(width: 150)
        }
    }

    // MARK: Small parts

    /// §8 — section label 12/600 secondary at left, 12/500 tertiary count at
    /// right. Sentence case, zero tracking; the run-1 all-caps 9px labels on
    /// 1.0 tracking were the gate's first named defect class.
    private func sectionLabel(_ text: String,
                              trailing: String? = nil,
                              trailingIsLink: Bool = false) -> some View {
        HStack {
            Text(text)
                .font(ES09Type.label)
                .foregroundStyle(inkSecondary)
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing)
                    .font(trailingIsLink ? ES09Type.label : ES09Type.body)
                    .foregroundStyle(trailingIsLink ? linkInk : inkTertiary)
            }
        }
    }

    private func emptyCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(ES09Type.rowTitle).foregroundStyle(inkPrimary)
            Text(body).font(ES09Type.body).foregroundStyle(inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(hairline, lineWidth: 1))
    }

    /// Position per the escort design directive: LEAD · CHASE · HIGH-POLE.
    /// Server enum is lead | chase | both. The canon gate retired soft-fill
    /// badges, so the state reads as a dot plus an ink word — the same
    /// treatment the exemplar gives "Accepted" and "Chase".
    private func positionBadge(_ raw: String) -> some View {
        let key = raw.lowercased()
        let label: String
        switch key {
        case "lead":       label = "Lead"
        case "chase":      label = "Chase"
        case "both":       label = "Lead + chase"
        case "high_pole", "highpole", "high-pole": label = "High-pole"
        default:           label = raw.capitalized
        }
        return HStack(spacing: 5) {
            Circle().fill(positionTint(raw)).frame(width: 6, height: 6)
            Text(label)
                .font(ES09Type.label)
                .foregroundStyle(positionInk(raw))
                .lineLimit(1)
        }
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
        f.dateFormat = "EEE MMM d · HH:mm"
        return f.string(from: Date())
    }

    private var monthShort: String {
        let f = DateFormatter(); f.dateFormat = "MMM"
        return f.string(from: Date())
    }

    private func heroSubline(_ job: ES09ActiveJob) -> String {
        var parts: [String] = []
        if let n = job.loadNumber, !n.isEmpty { parts.append(n) }
        if let d = job.distance, d > 0 { parts.append("\(Int(d.rounded())) mi") }
        if let c = job.cargoType, !c.isEmpty { parts.append(c) }
        if let h = job.hazmatClass, !h.isEmpty { parts.append("hazmat \(h)") }
        if let s = job.status, !s.isEmpty { parts.append(s) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func stageCountdown(_ job: ES09ActiveJob) -> String? {
        guard let d = job.pickupDate.flatMap(parseISO) else { return nil }
        let delta = d.timeIntervalSinceNow
        guard delta > 0 else { return nil }
        let h = Int(delta) / 3600, m = (Int(delta) % 3600) / 60
        return h > 0 ? "\(h) h \(m) m" : "\(m) m"
    }

    /// The 12px explainer that sits under the hero number. It names what
    /// the countdown is counting toward — never a bare figure.
    private func stageExplainer(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "until stage-in" }
        return "until stage-in · roll \(clock(d.addingTimeInterval(30 * 60)))"
    }

    private func stageLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "Stage —" }
        return "Stage \(clock(d))"
    }

    private func rollLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "Roll —" }
        return "Roll \(clock(d.addingTimeInterval(30 * 60)))"
    }

    private func releaseLabel(_ job: ES09ActiveJob) -> String {
        guard let d = job.pickupDate.flatMap(parseISO) else { return "Release —" }
        return "Release ~\(clock(d.addingTimeInterval(estimatedBlockHours(job) * 3600)))"
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
        if days < 0 { return "Expired" }
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
        // §9 TRUTH LAW — run-1 fell back to five equal 0.15 bars when no
        // completed move landed in the window. That is a drawn flat line
        // where the truth is "nothing settled yet", so the fallback is
        // WITHDRAWN: an empty array paints no bars at all.
        let top = buckets.max() ?? 0
        guard top > 0 else { return [] }
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

    /// Urgent tenders as a share of the open board. Both terms come off
    /// escorts.getMarketplaceStats (escorts.ts:849) — nothing is smoothed,
    /// extrapolated or shaped by a curve. Nil when the board is empty, so
    /// the track paints bare instead of implying a reading.
    private var urgentFraction: CGFloat? {
        let open = Double(snap.market?.availableJobs ?? 0)
        guard open > 0 else { return nil }
        let urgent = Double(snap.market?.urgentJobs ?? 0)
        return CGFloat(min(max(urgent / open, 0), 1))
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
            // §7 — the shipped escort enum, never invented:
            // HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME.
            // EscortNavController.swift:77-85 (orb labels :63).
            BottomNav(
                leading: es09NavLeading(),
                trailing: es09NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es09NavLeading() -> [NavSlot] {
    EscortNavRoute.leading(current: .home)
}

private func es09NavTrailing() -> [NavSlot] {
    EscortNavRoute.trailing(current: .home)
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
