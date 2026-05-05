//
//  MeDetailScreens.swift
//  EusoTrip — Destination screens for the Me tab (Wave 1 A5–A14).
//
//  Each row in `DriverMePane.entries` opens one of these screens in a
//  bottom sheet. The full backend-live versions of these screens ship in
//  subsequent waves — this file provides production-quality previews
//  (animated, themed, populated with representative data) so taps land on
//  a real surface rather than a dead row.
//
//  Architecture:
//    • `MeDetailRoute` enum — one case per row (10 total).
//    • `MeDetailContainer` — the sheet host. Given a route, it renders the
//      matching view inside a consistent chrome (title bar + hairline +
//      scroll body + close chip).
//    • Per-route views — small, self-contained, palette-aware.
//
//  Doctrine:
//    §2 nav invariants (no secondary chrome), §3 numbers-first copy,
//    §4.3 iridescent hairline under the top bar, §7 breathe density
//    (Space.s5 padding, ActiveCard grouping), shared design primitives
//    (ActiveCard, MetricTile, StatusPill, CTAButton).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Me-detail action coordinator
//
// The Me-detail screens are "production-quality previews" per file doctrine
// — their CTAs will get full backend adapters in later waves, but every tap
// must still feel real TODAY. `MeAction.fire(_:)` is the single choke point
// for every driver-facing CTA on these screens:
//
//   • A success haptic so the driver feels the tap land.
//   • A `.eusoMeActionFired` notification with a stable key (e.g.
//     "wallet.instant-payout") so the app-level toast layer + analytics +
//     any future backend bridge can all intercept with zero per-call-site
//     refactor. When the tRPC mutation for a given key lands, wiring up is
//     a single `switch` case in whichever service listens.
//   • Light key + userInfo extensibility.
//
// Doctrine: no dead buttons. If a CTA doesn't have its backend wave yet,
// it still fires — it just fires through this helper.
//
enum MeAction {
    static func fire(_ key: String, userInfo: [String: Any] = [:]) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        NotificationCenter.default.post(
            name: .eusoMeActionFired,
            object: key,
            userInfo: userInfo
        )
    }
}

// MARK: - Route

enum MeDetailRoute: String, Identifiable, CaseIterable {
    case carrier, authority, earnings, rateSheet, documents, eusoTicket, tax, dvir, availability, missions, rewards, badges, referrals, zeun, eld, fleet, haul, news, pulse, notifications, settings, disputes, counterInbox, compliance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carrier:       return "Carrier"
        case .authority:     return "Authority"
        case .earnings:      return "EusoWallet"
        case .rateSheet:     return "Rate Sheets"
        case .documents:     return "Documents Center"
        case .eusoTicket:    return "EusoTicket"
        case .tax:           return "Tax · W-9 / 1099"
        case .dvir:          return "DVIR"
        case .availability:  return "Availability"
        case .missions:      return "Missions"
        case .rewards:       return "Rewards"
        case .badges:        return "Badges"
        case .referrals:     return "Invite & Earn"
        case .zeun:          return "Zeun Mechanics"
        case .eld:           return "ELD"
        case .fleet:         return "Fleet Management"
        case .haul:          return "The Haul"
        case .news:          return "Driver Intel"
        case .pulse:         return "EusoTrip Pulse"
        case .notifications: return "Notifications"
        case .settings:      return "Settings"
        case .disputes:      return "Disputes"
        case .counterInbox:  return "Counter Inbox"
        case .compliance:    return "Compliance"
        }
    }

    var subtitle: String {
        switch self {
        case .carrier:       return "Who you drive for · DOT · MC · compliance"
        case .authority:     return "Lease-on · trip lease · FMCSR Part 376"
        case .earnings:      return "Week · month · year to date"
        case .rateSheet:     return "Schedule A · pay calculator · reconciliation"
        case .documents:     return "Vault · upload · AI auto-classify · share · tax"
        case .eusoTicket:    return "BOL · run ticket · haul receipts · terminal stats"
        case .tax:           return "Filing documents + totals"
        case .dvir:          return "Inspection history"
        case .availability:  return "Duty schedule · home-time"
        case .missions:      return "Active · completed · rewards"
        case .rewards:       return "Points · tier · claim catalog"
        case .badges:        return "Achievements + progression"
        case .referrals:     return "Code · QR · share · stage funnel · rewards"
        case .zeun:          return "Diagnostics · DVIR · maintenance · breakdowns"
        case .eld:           return "Duty status · drive clock · HoS violations"
        case .fleet:         return "Vehicles · trailers · geofences · IFTA"
        case .haul:          return "Lobby · missions · rewards · leaderboard"
        case .news:          return "News · regulations · market · safety"
        case .pulse:         return "Apple Watch pairing · last sync"
        case .notifications: return "Inbox · categories · delivery"
        case .settings:      return "Account · notifications · device"
        case .disputes:      return "Detention · accessorial · settlement disputes you're named in"
        case .counterInbox:  return "Shipper counters waiting · accept / decline / re-counter"
        case .compliance:    return "HOS · insurance · hazmat · TWIC · carrier safety"
        }
    }
}

// MARK: - Container

/// Sheet host used by DriverMePane. Provides the chrome and forwards the
/// route to the correct view body.
struct MeDetailContainer: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let route: MeDetailRoute

    // Routes that own their entire chrome (header + scroll + refresh).
    // For these the container skips its own `header` + hairline so we
    // don't double-render.
    private var ownsOwnChrome: Bool {
        switch route {
        case .news, .earnings: return true
        default:               return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !ownsOwnChrome {
                header
                IridescentHairline()
            }
            // Driver Intel (news) hosts its own ScrollView + refresh handler
            // and needs the full device width for the hero card and row
            // list. Wrapping it in the container's ScrollView + Space.s5
            // gutter caused a double-padding (40pt per side) that squeezed
            // the hero card narrower than the Figma target. Render news
            // bare here so MeNewsView controls its own chrome.
            //
            // Brick 068 (Me · Earnings) also owns its own header +
            // ScrollView + refreshable closure — render bare, same as
            // news, so the hero/chart/footer layout isn't double-padded.
            if ownsOwnChrome {
                routeBody
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        routeBody
                    }
                    .padding(Space.s5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Drag-down refresh on every Me sub-sheet (Eusowallet,
                // Tax, DVIR, Availability, Missions, Badges, Referrals,
                // ZEUN, Haul, Settings). One stub now; routeBody can
                // wire its own refetch later.
                .refreshable {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        // Uniform cafe-door surface animation for every Me detail screen
        // the moment it's selected. Keyed by route.rawValue so the
        // container remounts on each selection and re-plays the entry.
        .id("me-detail-\(route.rawValue)")
        .screenTileRoot()
    }

    // Patch #1: EusoHeader replaces the hand-rolled route header. The
    // old ALL-CAPS-bullet subtitle (e.g. "EARNINGS · SETTLEMENTS ·
    // PAYOUTS") is dropped in favour of a sentence-case single-line
    // descriptor — still informative, no AI-template tell.
    @ViewBuilder
    private var header: some View {
        EusoHeader(title: route.title,
                   subtitle: route.subtitle,
                   size: .sheet) {
            // Canonical close X — same primitive shipped on every
            // pull-down sheet so the dismiss target is unmistakable
            // and at the same coordinates regardless of which Me
            // sub-route is showing.
            SheetCloseButton { dismiss() }
                .accessibilityLabel("Close \(route.title)")
        }
    }

    @ViewBuilder
    private var routeBody: some View {
        switch route {
        case .earnings:
            // EusoWallet surface — same DriverWalletPane the Home page
            // presents from the "Wallet available" tile, per user
            // direction (2026-04-25):
            //   > you do realize the wallet you get when you click on
            //   > "wallet available" on home page is eusowallet right.
            //   > thats how it should look in the me screen for
            //   > eusowallet.
            // The legacy `MeEarnings068` brick rendered an empty
            // earnings shell with no Stripe / wallet amount — replaced
            // wholesale with the full DriverWalletPane so Home and Me
            // share one canonical wallet view.
            DriverWalletPane()
        case .carrier:      MeCarrierView()
        case .authority:    MeAuthority()
        case .rateSheet:    MeRateSheet()
        case .documents:    MeDocumentsHub()
        case .eusoTicket:   MeEusoTicketsView()
        case .tax:          MeTaxView()
        case .dvir:         MeDvirView()
        case .availability: MeAvailabilityView()
        case .missions:     MeMissionsView()
        case .rewards:      MeRewardsView()
        case .badges:       MeBadgesView()
        case .referrals:    MeReferrals()  // brick 088 — full Invite & Earn surface (hero code + QR poster + stage funnel + events + reward schedule). Replaces legacy MeReferralsView, which only showed the bare referral list and read as a placeholder.
        case .zeun:         MeZeunView()
        case .eld:          MeEldView()
        case .fleet:        MeFleetView()
        case .haul:         MeHaulView()
        case .news:         MeNewsView()
        case .pulse:         MePulseView()
        case .notifications: MeNotificationsView()
        case .settings:      MeSettingsView()
        case .disputes:      DisputeListView()
        case .counterInbox:  DriverCounterInboxView()
        case .compliance:    DriverComplianceDashboard()
        }
    }
}

// MARK: - 1. Earnings
//
// Ported to brick 068 (`MeEarnings068` in `Views/Driver/068_MeEarnings.swift`).
// The legacy `MeEarningsView` used by this sub-route was a single
// `EusoEmptyState` stub; the new brick ships the full live surface:
// period picker · hero card · breakdown grid · chart · top loads ·
// YTD/tax footer — all wired to the canonical `earningsRouter` +
// `taxRouter`. See `MeDetailContainer.ownsOwnChrome` for why the
// container skips its header when this route is active.

// MARK: - 2. Tax

struct MeTaxView: View {
    @Environment(\.palette) var palette
    @StateObject private var taxStore = TaxSummaryStore()
    @StateObject private var ytdStore = YTDEarningsStore()

    // Live bind order: earnings.getYTDSummary is canonical (confirmed via
    // MCP against frontend/server/routers/earnings.ts). tax.getDriverSummary
    // wraps the same aggregate with federal/state withholding hints; on
    // failure we render the YTD gross on its own. 1099 download flag
    // flips true once the user's contractor record clears $600 threshold
    // (IRS 1099-NEC rule — taxReportingRouter on the backend).
    var body: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("YTD · GROSS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                switch ytdStore.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                case .loaded(let y?):
                    Text(formatUSD(y.totalEarnings))
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(y.totalLoads) loads · \(Int(y.totalMiles.rounded())) mi · projected \(formatUSD(y.projectedAnnual))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                case .empty, .loaded(.none):
                    Text("$0")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Your YTD gross populates as settlements clear.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                case .error:
                    Text("—")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Text("Couldn't reach earnings service.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .task {
            await ytdStore.refresh()
            await taxStore.refresh()
        }

        // Withholding tile — bound to tax.getDriverSummary. When empty,
        // surface an honest "no withholding posted yet" empty state.
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("WITHHOLDING + 1099")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                switch taxStore.state {
                case .loading:
                    ProgressView()
                case .loaded(let t?):
                    HStack(spacing: Space.s3) {
                        MetricTile(label: "Federal",
                                   value: formatUSD(t.federalWithheld ?? 0))
                        MetricTile(label: "State",
                                   value: formatUSD(t.stateWithheld ?? 0))
                    }
                    HStack(spacing: Space.s3) {
                        MetricTile(label: "Est. quarterly",
                                   value: formatUSD(t.quarterlyEstimate ?? 0))
                        MetricTile(label: "Platform fees",
                                   value: formatUSD(t.platformFees))
                    }
                    if t.download1099Available == true {
                        CTAButton(title: "Download 1099-NEC") {
                            MeAction.fire("tax.download-1099")
                        }
                    } else {
                        Text("1099 ships each January once your annual total crosses $600.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                case .empty, .loaded(.none), .error:
                    Text("No withholding posted yet.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func formatUSD(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }
}

// MARK: - 3. DVIR

struct MeDvirView: View {
    @Environment(\.palette) var palette
    /// Live DVIR history — `inspections.getDVIRHistory` tRPC via the
    /// shared `InspectionsHistoryStore`. Replaces the 5-row seeded
    /// "Apr 16–19 · Pre-trip / Post-trip" literal list.
    @StateObject private var historyStore = InspectionsHistoryStore()

    var body: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("INSPECTION STREAK")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text("—")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Streak surfaces once your pre + post trip logs start landing.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                ComplianceInlineChip(tag: .eDvir)
                    .padding(.top, 2)
                CTAButton(title: "Start pre-trip DVIR") {
                    MeAction.fire("dvir.start-pretrip")
                    NotificationCenter.default.post(
                        name: .eusoStartPretripDVIR,
                        object: nil
                    )
                }
                .padding(.top, Space.s2)
            }
        }

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recent inspections".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            if historyStore.items.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.shield",
                    title: "No DVIR entries yet",
                    subtitle: "Your pre-trip + post-trip inspections log here the moment they submit."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(historyStore.items.enumerated()), id: \.offset) { idx, e in
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((e.reportType ?? "DVIR").capitalized)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text(e.reportDate ?? "—")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            StatusPill(
                                text: (e.overallCondition ?? "—").capitalized,
                                kind: (e.defectsFound ?? 0) > 0 ? .warning : .success
                            )
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        if idx < historyStore.items.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .eusoCard(radius: Radius.lg)
            }
        }
        .task { await historyStore.refresh() }
    }
}

// MARK: - 4. Availability
//
// Ports the web `availabilityRouter` surface (server/routers/availability.ts)
// into the Me tab. Five regions, top to bottom:
//   • Duty hero — toggle "Accept loads" + "Home-time" + utilization %
//   • Stats tiles (2×2) — available / driving / utilization / home-time days
//   • Weekly grid — 7 × 24 hour cells color-graded per availability band
//   • Upcoming blocks list — ad-hoc PTO / medical / maintenance windows
//   • Home-time countdown + "Export calendar (.ics)" CTA
//
// Numbers are representative; live wiring comes through the availability
// router (`weeklyGrid`, `getUtilization`, `listBlocks`, `exportICS`) in a
// follow-up brick. Cell status enumeration matches the web:
//   .available (diagonal gradient tint) · .duty (success green tint) ·
//   .home (neutral) · .blocked (warning) · .sleep (info/navy blue).

struct MeAvailabilityView: View {
    @Environment(\.palette) var palette
    @State private var dutyOn = true
    @State private var homeTime = false
    @State private var selectedDay: Int = 1 // Mon-focus; loops 0..6 (Sun..Sat)
    @State private var showBlockSheet = false

    private enum Cell: Int, CaseIterable {
        case available, duty, home, blocked, sleep
        /// Tap-to-cycle: available → duty → home → blocked → sleep → available.
        var next: Cell {
            Cell(rawValue: (rawValue + 1) % Cell.allCases.count) ?? .available
        }
    }

    private struct DayKey { let short: String; let full: String }
    private let days: [DayKey] = [
        .init(short: "S", full: "Sun"), .init(short: "M", full: "Mon"),
        .init(short: "T", full: "Tue"), .init(short: "W", full: "Wed"),
        .init(short: "T", full: "Thu"), .init(short: "F", full: "Fri"),
        .init(short: "S", full: "Sat")
    ]

    /// 7 days × 24 hours — mirrors the web `weeklyGrid` procedure response
    /// shape. Apr 20 (Mon) is `selectedDay=1`, and we walk a realistic run:
    /// Monday Dallas→OKC drive, Tuesday OKC→Albuquerque, Wednesday rest
    /// day (home-time after DOT inspection window), Thursday Albuquerque→
    /// Phoenix, Friday maintenance block (PM-B), Saturday rest, Sunday
    /// pre-stage for next week. The ad-hoc blocks below flag specific cells.
    ///
    /// @State so the driver can tap-and-cycle a cell from the weekly heatmap —
    /// this is the lightweight edit path. Heavier block edits go through the
    /// "Add block" sheet which writes into `blocks` below.
    /// Empty 7 × 24 grid — every cell seeded to `.available`. Until the
    /// server-side `availability.weeklyGrid` router ships, the driver
    /// starts with a blank slate and builds their own availability map
    /// through the cell-tap cycle. Previously preseeded with a
    /// Dallas→OKC→Albuquerque→Phoenix run + DOT / PM-B blocked windows.
    ///
    /// TODO(backend): POST /v1/availability/weeklyGrid — returns [[Cell]]
    @State private var grid: [[Cell]] = Array(
        repeating: Array(repeating: Cell.available, count: 24),
        count: 7
    )

    /// Ad-hoc blocked windows surfaced in the "Upcoming blocks" list — these
    /// correspond to the `blocked` cells in `grid` above.
    private struct Block: Identifiable {
        let id: UUID
        let day: String; let hours: String; let reason: String; let kind: Kind
        enum Kind { case maintenance, medical, dot, pto }

        init(id: UUID = UUID(), day: String, hours: String, reason: String, kind: Kind) {
            self.id = id
            self.day = day
            self.hours = hours
            self.reason = reason
            self.kind = kind
        }
    }
    // Live blocks start empty — the server-side `availability.getBlocks`
    // router hasn't shipped yet. Seeded DOT annual, PM-B service, and
    // Dentist entries are gone. Drivers add their own via the
    // block-time editor sheet below.
    //
    // TODO(backend): POST /v1/availability/getBlocks — returns [AvailabilityBlock]
    @State private var blocks: [Block] = []

    // ─── Derived summary ──────────────────────────────────────────────────
    private var availableHrs: Int {
        grid.flatMap { $0 }.reduce(0) { $0 + ($1 == .available ? 1 : 0) }
    }
    private var dutyHrs: Int {
        grid.flatMap { $0 }.reduce(0) { $0 + ($1 == .duty ? 1 : 0) }
    }
    private var homeHrs: Int {
        grid.flatMap { $0 }.reduce(0) { $0 + ($1 == .home ? 1 : 0) }
    }
    private var utilizationPct: Int {
        let workable = dutyHrs + availableHrs
        let total = workable + homeHrs
        guard total > 0 else { return 0 }
        return Int(round(Double(workable) / Double(total) * 100))
    }

    /// Subtitle line under the "NEXT HOME-TIME" countdown. Composes
    /// "Home-base <city> · <reset window> reset window then restart
    /// <day> morning" with em-dash sentinels for parts that aren't
    /// first-class on the canonical surfaces yet.
    ///
    /// 116th firing M2 retrofit (2026-04-26): previous literal
    /// "Home-base Dallas · 2-day reset window then restart Mon
    /// morning" excised. Home-base city is profile metadata that
    /// does not yet exist on `AuthUser`; reset-window length and
    /// restart-day are HOS-derived and must come from the (still-
    /// stub) `availability.weeklyGrid` router. Until both ship the
    /// subtitle renders honest em-dashes rather than fabricating
    /// the driver's home city or schedule. Doctrine: 0% mock data.
    private var homeBaseResetSubtitle: String {
        let homeCity = "—"        // AuthUser.homeBaseCity not yet on the wire.
        let resetWindow = "—"     // availabilityRouter.weeklyGrid not yet on the wire.
        let restartDay = "—"      // HOS-derived; awaits backend.
        return "Home-base \(homeCity) · \(resetWindow) reset window then restart \(restartDay) morning"
    }

    var body: some View {
        // ─── Duty hero ────────────────────────────────────────────────────
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("THIS WEEK · UTILIZATION")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: dutyOn ? "On duty" : "Off duty",
                               kind: dutyOn ? .success : .neutral)
                }
                Text("\(utilizationPct)%")
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(dutyHrs) driving · \(availableHrs) available · \(homeHrs) home · 3-week streak")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                Toggle(isOn: $dutyOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accept loads")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Dispatch routes new offers to you.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .toggleStyle(GradientToggleStyle())

                Toggle(isOn: $homeTime) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Home-time mode")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Pauses offers until you toggle back.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .toggleStyle(GradientToggleStyle())
            }
        }

        // ─── Stats tiles ──────────────────────────────────────────────────
        HStack(spacing: Space.s3) {
            MetricTile(label: "Driving hrs",  value: "\(dutyHrs)", gradientNumeral: true)
            MetricTile(label: "Available hrs", value: "\(availableHrs)")
        }
        HStack(spacing: Space.s3) {
            MetricTile(label: "Home-time",   value: "\(homeHrs / 24)d \(homeHrs % 24)h")
            MetricTile(label: "Blocked",     value: "\(blocks.count) windows")
        }

        // ─── Weekly grid ──────────────────────────────────────────────────
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Weekly grid".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Apr 20 – Apr 26 · local time")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }

            // Compact heatmap: rows = days, columns = 24 hours.
            VStack(spacing: 4) {
                // Header — "12a 6 12p 6" anchors
                HStack(spacing: 0) {
                    Text("").frame(width: 28, alignment: .leading)
                    HStack(spacing: 0) {
                        ForEach(["12a","","","","","","6","","","","","","12p","","","","","","6","","","","",""], id: \.self) { lbl in
                            Text(lbl)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                ForEach(0..<7, id: \.self) { d in
                    HStack(spacing: 0) {
                        // Day label: tap = focus day (lightweight affordance).
                        Text(days[d].short)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(d == selectedDay ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                            .frame(width: 28, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    selectedDay = d
                                }
                            }
                        HStack(spacing: 2) {
                            ForEach(0..<24, id: \.self) { h in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(fill(for: grid[d][h]))
                                    .frame(height: 18)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                            // Tap a cell to cycle its state.
                                            // Single-tap focuses the day too,
                                            // so the expanded strip reflects
                                            // the edit immediately.
                                            selectedDay = d
                                            grid[d][h] = grid[d][h].next
                                        }
                                    }
                                    .accessibilityLabel("\(days[d].full) \(h):00 — \(accessibilityLabel(for: grid[d][h]))")
                                    .accessibilityHint("Tap to cycle duty state")
                            }
                        }
                    }
                }
            }

            // Legend.
            HStack(spacing: Space.s3) {
                legendDot(color: AnyShapeStyle(LinearGradient.diagonal.opacity(0.85)), label: "Available")
                legendDot(color: AnyShapeStyle(Brand.success.opacity(0.85)),          label: "Driving")
                legendDot(color: AnyShapeStyle(palette.tintNeutral),                  label: "Home")
                legendDot(color: AnyShapeStyle(Brand.warning.opacity(0.85)),          label: "Blocked")
            }
            .font(EType.micro)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)

        // ─── Selected day detail — hour strip ────────────────────────────
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(days[selectedDay].full.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(daySummary(selectedDay))
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { h in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(fill(for: grid[selectedDay][h]))
                            .frame(height: 28)
                        if h % 6 == 0 {
                            Text("\(h)")
                                .font(.system(size: 8, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(palette.textTertiary)
                        } else {
                            Text(" ").font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            grid[selectedDay][h] = grid[selectedDay][h].next
                        }
                    }
                    .accessibilityLabel("\(days[selectedDay].full) \(h):00 — \(accessibilityLabel(for: grid[selectedDay][h]))")
                    .accessibilityHint("Tap to cycle duty state")
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)

        // ─── Upcoming blocks ─────────────────────────────────────────────
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Upcoming blocks".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Button { showBlockSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add block")
                            .font(EType.micro).tracking(0.4)
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, b in
                    HStack(spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(blockTint(b.kind))
                            Image(systemName: blockGlyph(b.kind))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(blockIconColor(b.kind))
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.reason)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Text("\(b.day) · \(b.hours)")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                blocks.removeAll { $0.id == b.id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove block \(b.reason)")
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                    if idx < blocks.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
                if blocks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(palette.textTertiary)
                        Text("No upcoming blocks")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s5)
                }
            }
            .eusoCard(radius: Radius.lg)
        }

        // ─── Home-time countdown + Export ICS ────────────────────────────
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("NEXT HOME-TIME")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "Scheduled", kind: .info)
                }
                Text("Fri · 34h 12m")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(homeBaseResetSubtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                CTAButton(title: "Export calendar (.ics)") {
                    // Mint the signed-URL export from the backend then
                    // hand the .ics off to the system so Calendar.app
                    // opens its import sheet. Was firing a notification
                    // only — backend mutation never ran, no URL ever
                    // surfaced, no .ics ever opened. User report:
                    // "ICS calendar export doesn't work".
                    Task { @MainActor in
                        do {
                            let resp = try await EusoTripAPI.shared.availability.exportICS()
                            #if canImport(UIKit)
                            // Resolve the absolute URL against the API
                            // base so the system can fetch + invoke
                            // Calendar's import handler.
                            let base = EusoTripAPI.shared.baseURL
                            let absolute: URL? = resp.url.hasPrefix("http")
                                ? URL(string: resp.url)
                                : base.flatMap { URL(string: resp.url, relativeTo: $0)?.absoluteURL }
                            if let u = absolute {
                                await UIApplication.shared.open(u)
                            }
                            #endif
                            MeAction.fire("availability.export-ics")
                        } catch {
                            MeAction.fire(
                                "availability.export-ics.failed",
                                userInfo: ["error": error.localizedDescription]
                            )
                        }
                    }
                }
                .padding(.top, Space.s2)
            }
        }

        // Block-time modal. On save we append to the local `blocks` list
        // and paint the covered hours `.blocked` in the weekly grid so the
        // heatmap reflects the new window immediately.
        .sheet(isPresented: $showBlockSheet) {
            BlockTimeSheet { reason, start, end in
                let newBlock = Self.buildBlock(reason: reason, start: start, end: end)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    blocks.insert(newBlock, at: 0)
                    paintBlocked(from: start, to: end)
                }
            }
            .environment(\.palette, palette)
        }
    }

    /// Mark every hour cell covered by `start..<end` as `.blocked`. Respects
    /// day boundaries — a block that spans midnight paints both days.
    private func paintBlocked(from start: Date, to end: Date) {
        let cal = Calendar(identifier: .gregorian)
        guard end > start else { return }
        // Walk one hour at a time so we don't miss partial hours.
        var cursor = start
        while cursor < end {
            let weekday = cal.component(.weekday, from: cursor) // 1 = Sun
            let hour    = cal.component(.hour,    from: cursor)
            let d = max(0, min(6, weekday - 1))
            let h = max(0, min(23, hour))
            grid[d][h] = .blocked
            cursor = cal.date(byAdding: .hour, value: 1, to: cursor) ?? end
        }
    }

    // MARK: - Helpers

    private func fill(for c: Cell) -> AnyShapeStyle {
        switch c {
        case .available: return AnyShapeStyle(LinearGradient.diagonal.opacity(0.75))
        case .duty:      return AnyShapeStyle(Brand.success.opacity(0.80))
        case .home:      return AnyShapeStyle(palette.tintNeutral)
        case .blocked:   return AnyShapeStyle(Brand.warning.opacity(0.80))
        // Doctrine §2.1 gradient-not-blue: `.sleep` is a brand-accent rest state
        // (paired with `.available`). Flat Brand.info read as plain blue next to
        // the available gradient; render the same gradient at a lower opacity so
        // the two brand states share visual family. 32nd firing hygiene sweep.
        case .sleep:     return AnyShapeStyle(LinearGradient.diagonal.opacity(0.40))
        }
    }

    private func daySummary(_ d: Int) -> String {
        let row = grid[d]
        let drv = row.reduce(0) { $0 + ($1 == .duty ? 1 : 0) }
        let avl = row.reduce(0) { $0 + ($1 == .available ? 1 : 0) }
        let blk = row.reduce(0) { $0 + ($1 == .blocked ? 1 : 0) }
        if drv > 0 { return "\(drv)h driving · \(avl)h available" }
        if blk > 0 { return "\(blk)h blocked · \(avl)h available" }
        return "Home-time day · \(avl)h available"
    }

    private func blockTint(_ k: Block.Kind) -> Color {
        switch k {
        case .maintenance: return palette.tintInfo
        case .medical:     return palette.tintSuccess
        case .dot:         return palette.tintWarning
        case .pto:         return palette.tintNeutral
        }
    }
    private func blockIconColor(_ k: Block.Kind) -> Color {
        switch k {
        case .maintenance: return Brand.info
        case .medical:     return Brand.success
        case .dot:         return Brand.warning
        case .pto:         return palette.textPrimary
        }
    }
    private func blockGlyph(_ k: Block.Kind) -> String {
        switch k {
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .medical:     return "cross.case.fill"
        case .dot:         return "checkmark.shield.fill"
        case .pto:         return "house.fill"
        }
    }

    @ViewBuilder
    private func legendDot(color: AnyShapeStyle, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label).foregroundStyle(palette.textSecondary)
        }
    }

    private func accessibilityLabel(for c: Cell) -> String {
        switch c {
        case .available: return "Available"
        case .duty:      return "Driving"
        case .home:      return "Home-time"
        case .blocked:   return "Blocked"
        case .sleep:     return "Sleep berth"
        }
    }

    /// Turn a (reason, start, end) tuple from the sheet into a `Block`.
    /// Pre-formats the day + hours strings so the "Upcoming blocks" list
    /// stays single-source-of-truth and doesn't re-derive strings on every
    /// body evaluation.
    private static func buildBlock(reason: String, start: Date, end: Date) -> Block {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        let hr = DateFormatter()
        hr.dateFormat = "HH:mm"
        let day   = df.string(from: start)
        let hours = "\(hr.string(from: start)) – \(hr.string(from: end))"
        let kind: Block.Kind = {
            let r = reason.lowercased()
            if r.contains("maint") { return .maintenance }
            if r.contains("medical") || r.contains("dentist") || r.contains("doctor") { return .medical }
            if r.contains("dot") || r.contains("inspection") { return .dot }
            return .pto
        }()
        return Block(day: day, hours: hours, reason: reason, kind: kind)
    }
}

// MARK: - Block-time editor sheet
//
// Lightweight "add block" form used by MeAvailabilityView. Mirrors the web
// availability.blockTime mutation payload: { reason, startsAt, endsAt }.
// Presented sheet-over-sheet; dismiss-on-save restores the Availability
// sheet with the new block inserted (wiring to live mutation ships in a
// follow-up brick — for now we surface the shape so the tap lands on a
// real form).

private struct BlockTimeSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "Maintenance"
    @State private var startAt = Date()
    @State private var endAt   = Date().addingTimeInterval(3600 * 2)
    private let reasons = ["Maintenance", "Medical", "DOT inspection", "PTO", "Personal"]

    /// Called on "Block this window" tap. Parent handles list-append +
    /// grid repaint. Nil = no-op (preview / SwiftUI canvas).
    var onSave: ((_ reason: String, _ start: Date, _ end: Date) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block time")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("PAUSE DISPATCH FOR A WINDOW")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            IridescentHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("REASON").font(EType.micro).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        VStack(spacing: 0) {
                            ForEach(Array(reasons.enumerated()), id: \.offset) { idx, r in
                                HStack {
                                    Text(r).font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    if reason == r {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(LinearGradient.diagonal)
                                    }
                                }
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s3)
                                .contentShape(Rectangle())
                                .onTapGesture { reason = r }
                                if idx < reasons.count - 1 {
                                    Divider().overlay(palette.borderFaint)
                                }
                            }
                        }
                        .eusoCard(radius: Radius.lg)
                    }

                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("WINDOW").font(EType.micro).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        VStack(spacing: 0) {
                            DatePicker("Start", selection: $startAt)
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s3)
                            Divider().overlay(palette.borderFaint)
                            DatePicker("End", selection: $endAt)
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s3)
                        }
                        .eusoCard(radius: Radius.lg)
                    }

                    CTAButton(title: "Block this window") {
                        onSave?(reason, startAt, endAt)
                        dismiss()
                    }
                    .disabled(endAt <= startAt)
                    .opacity(endAt <= startAt ? 0.5 : 1.0)
                }
                .padding(Space.s5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage)
    }
}

// MARK: - Gradient Toggle Style

struct GradientToggleStyle: ToggleStyle {
    @Environment(\.palette) var palette

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: Space.s3)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        configuration.isOn
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(Color.white.opacity(0.14))
                    )
                    .frame(width: 51, height: 31)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                configuration.isOn
                                ? AnyShapeStyle(Color.clear)
                                : AnyShapeStyle(Color.white.opacity(0.08)),
                                lineWidth: 1
                            )
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - 5. Missions
//
// Ports the web `missionsRouter` surface (server/routers/missions.ts) into
// the Me tab. Five regions:
//   • Hero — XP / level / next-tier progress
//   • Filter chips — All / Daily / Weekly / Monthly / Epic
//   • In-flight list — active missions with progress bars
//   • Available list — uncommitted missions the driver can start
//   • Completed & claimable list — finished missions awaiting reward claim
//
// Mission tiers match the server enum: daily → weekly → monthly → epic →
// seasonal. Each mission carries dual rewards: XP (for tier progression)
// and points (redeemable on the Rewards surface).

struct MeMissionsView: View {
    @Environment(\.palette) var palette

    // Canonical wiring: `gamification.getMissions` (verified via MCP at
    // frontend/server/routers/gamification.ts:679). Backend returns
    // { active, completed, available } with role-filtered rows; we show
    // available + active concatenated.
    @StateObject private var missionsStore = MissionsStore()

    var body: some View {
        switch missionsStore.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).task { await missionsStore.refresh() }
        case .empty:
            EusoEmptyState(
                systemImage: "flag.checkered",
                title: "No missions yet",
                subtitle: "Weekly + monthly tracks unlock here as you drive — first mission lands with your next delivery.",
                comingSoon: false
            )
            .task { await missionsStore.refresh() }
        case .error:
            EusoEmptyState(
                systemImage: "flag.checkered",
                title: "Couldn't load missions",
                subtitle: "Pull to refresh — the mission service will be back momentarily."
            )
            .task { await missionsStore.refresh() }
        case .loaded(let missions):
            VStack(spacing: Space.s3) {
                ForEach(missions) { m in
                    HStack(alignment: .top, spacing: Space.s3) {
                        ZStack {
                            Circle().fill(LinearGradient.diagonal.opacity(0.18))
                                .frame(width: 40, height: 40)
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.title)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            if let sub = m.subtitle {
                                Text(sub)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(2)
                            }
                            if let label = m.rewardLabel {
                                Text(label)
                                    .font(EType.micro).tracking(0.4)
                                    .foregroundStyle(LinearGradient.diagonal)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.lg)
                }
            }
        }
    }
}

// The MeMissionsView body used to render ~14 seeded missions
// (Active · Claimable · Available · Completed) with filter chips, XP
// hero, per-tier tints, and a "Claim" pill. That code is gone; the
// parsing placeholder below keeps the file legal through the bulk
// edit and will be removed in the same PR that lands the live
// achievements router.
private enum _DeletedMissionsBody {
    static let _parserAnchor: [Int] = []
}

// MARK: - 5b. Rewards
//
// Ports the web `rewardsRouter` surface (server/routers/rewards.ts) into
// the Me tab. Drivers earn **points** (spendable currency) and **XP**
// (tier progression) by completing missions; the Rewards sheet is where
// those balances live and get redeemed. Five regions:
//   • Balance hero — points + tier + tier progress
//   • Tier ladder — Bronze → Silver → Gold → Platinum → Diamond
//   • Ready-to-open crates — rarity-graded mystery rewards
//   • Rewards catalog — fuel cards, cash payouts, gear, swag
//   • Recent redemption history
//
// Tier thresholds mirror the server enum (0 / 2,500 / 7,500 / 14,000 /
// 25,000 XP). Crate rarities: common · rare · epic · legendary.

struct MeRewardsView: View {
    @Environment(\.palette) var palette

    // Canonical wiring: `gamification.getRewardsCatalog` (MCP-verified at
    // frontend/server/routers/gamification.ts:377). Returns
    // { availablePoints, rewards: [...], categories }. Role-filtered.
    @StateObject private var rewardsStore = RewardsStore()

    var body: some View {
        switch rewardsStore.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).task { await rewardsStore.refresh() }
        case .empty:
            EusoEmptyState(
                systemImage: "gift",
                title: "No rewards unlocked yet",
                subtitle: "Complete missions and clear loads to earn points. Your catalog surfaces the moment a reward qualifies.",
                comingSoon: false
            )
            .task { await rewardsStore.refresh() }
        case .error:
            EusoEmptyState(
                systemImage: "gift",
                title: "Couldn't load rewards",
                subtitle: "We'll retry when you pull to refresh."
            )
            .task { await rewardsStore.refresh() }
        case .loaded(let rewards):
            VStack(spacing: Space.s3) {
                ForEach(rewards) { r in
                    HStack(alignment: .center, spacing: Space.s3) {
                        ZStack {
                            Circle().fill(LinearGradient.diagonal.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: "gift")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            if let cat = r.category {
                                Text(cat.capitalized)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text("\(r.pointsCost) pts")
                            .font(EType.bodyStrong)
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.lg)
                }
            }
        }
    }
}

// Old Rewards body (tiers + crates + catalog + history) deleted. The
// legacy stub below keeps the file parseable through this PR.
private enum _DeletedRewardsBody {
    static let _parserAnchor: [Int] = []
}

// MARK: - 6. Badges

struct MeBadgesView: View {
    @Environment(\.palette) var palette

    // Live badges store — `gamification.getBadges` (canonical, server-
    // wired). The legacy seeded literal list was retired in the 60th
    // firing.
    @StateObject private var badgesStore = BadgesStore()

    private let cols = [GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)]

    private var earnedCount: Int {
        badgesStore.items.filter { $0.earnedAt != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Header strip — gradient kicker + earned/total tally so the
            // page reads as a real progress dashboard instead of a gray
            // grid of slate cards.
            HStack(spacing: Space.s2) {
                Image(systemName: "rosette")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BADGE COLLECTION")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if !badgesStore.items.isEmpty {
                    Text("\(earnedCount) / \(badgesStore.items.count)")
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(.horizontal, Space.s2)

            if badgesStore.items.isEmpty {
                // Brand-tinted empty hero — a gradient orb + on-brand
                // copy instead of the generic gray EusoEmptyState card.
                VStack(spacing: Space.s3) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.diagonal.opacity(0.18))
                            .frame(width: 96, height: 96)
                        Image(systemName: "rosette")
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text("Your collection starts with the first run")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Loads delivered, safety streaks, and MPG wins all unlock here. Light one up — the rest follow.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
                )
                .task { await badgesStore.refresh() }
            } else {
                LazyVGrid(columns: cols, spacing: Space.s3) {
                    ForEach(badgesStore.items) { b in
                        let earned = b.earnedAt != nil
                        VStack(alignment: .leading, spacing: Space.s2) {
                            ZStack {
                                Circle()
                                    .fill(earned
                                          ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.22))
                                          : AnyShapeStyle(palette.bgCardSoft))
                                    .frame(width: 56, height: 56)
                                Circle()
                                    .strokeBorder(
                                        earned
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)),
                                        lineWidth: earned ? 1.5 : 1
                                    )
                                    .frame(width: 56, height: 56)
                                Image(systemName: b.iconName)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(earned
                                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                                     : AnyShapeStyle(palette.textSecondary))
                            }
                            Text(b.name)
                                .font(EType.bodyStrong)
                                .foregroundStyle(earned ? palette.textPrimary : palette.textSecondary)
                            if let desc = b.description {
                                Text(desc)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(Space.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(
                                    earned
                                        ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.5))
                                        : AnyShapeStyle(palette.borderFaint),
                                    lineWidth: earned ? 1 : 0.5
                                )
                        )
                        .opacity(earned ? 1 : 0.86)
                    }
                }
                .task { await badgesStore.refresh() }
            }
        }
    }
}

// MARK: - 7. Referrals

struct MeReferralsView: View {
    @Environment(\.palette) var palette

    // Legacy Me-sheet referrals surface. Reads the `profile.listReferrals`
    // feed via `DriverReferralsFeedStore` — row shape `DriverReferral`
    // (inviteeName / inviteeEmail / status / bonusAmount). The canonical
    // Invite & Earn surface is brick 088 (`MeReferrals`) which uses the
    // richer `ReferralsStore` bound to the `referrals.*` tRPC namespace.
    //
    // 72nd-firing rename: this caller was renamed from `ReferralsStore` to
    // `DriverReferralsFeedStore` to resolve a duplicate-type compile error
    // introduced when dev team landed the new store without removing the
    // older one.
    @StateObject private var referralsStore = DriverReferralsFeedStore()

    var body: some View {
        switch referralsStore.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).task { await referralsStore.refresh() }
        case .empty, .error:
            EusoEmptyState(
                systemImage: "person.2",
                title: "No referrals yet",
                subtitle: "Invite drivers via the Share tile on your profile — their activations will post here.",
                comingSoon: false
            )
            .task { await referralsStore.refresh() }
        case .loaded(let refs):
            VStack(spacing: Space.s3) {
                ForEach(refs) { r in
                    let label = r.inviteeName ?? r.inviteeEmail ?? "Pending invite"
                    HStack(spacing: Space.s3) {
                        ZStack {
                            Circle().fill(palette.bgCardSoft).frame(width: 40, height: 40)
                            Text(String(label.prefix(1)).uppercased())
                                .font(EType.bodyStrong)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text(r.status.capitalized)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        if let amt = r.bonusAmount {
                            Text("+\(Int(amt))")
                                .font(EType.bodyStrong)
                                .foregroundStyle(LinearGradient.diagonal)
                                .monospacedDigit()
                        }
                    }
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity)
                    .eusoCard(radius: Radius.lg)
                }
            }
        }
    }
}

// MARK: - 8. Zeun (fleet mechanics)

/// Identifiable wrapper for the breakdown-detail sheet binding. iOS
/// `.sheet(item:)` requires an Identifiable; the bare Int reportId
/// can't conform, so we wrap it.
private struct ZeunDetailRoute: Identifiable, Equatable {
    let id: Int
}

struct MeZeunView: View {
    @Environment(\.palette) var palette

    // DVIR inspection history — folded in here per user doctrine
    // (2026-04-20): "zeun is anything mechanical including inspection".
    // Pulls from `inspections.getDVIRHistory` via the shared
    // `InspectionsHistoryStore` — the 5-row seeded "Apr 16–19" list
    // that used to live here is gone.
    @StateObject private var historyStore = InspectionsHistoryStore()

    @StateObject private var breakdownsStore = ZeunBreakdownsStore()

    /// Sheets the Zeun rollup launches into. Each closes the 12-feature
    /// gap report from the comparison agent (reportBreakdown UI,
    /// provider directory, breakdown drill-in, maintenance scheduler).
    @State private var showReporter: Bool = false
    @State private var showProviders: Bool = false
    @State private var openReportId: Int? = nil

    var body: some View {
        // Canonical wiring: `zeunMechanics.getMyBreakdowns` (MCP-verified
        // at frontend/server/routers/zeunMechanics.ts:402). Returns the
        // driver's open + resolved breakdown reports. Empty = "no
        // mechanical issues reported" — an honest zero-state, not
        // coming-soon marketing copy.
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("OPEN BREAKDOWNS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                switch breakdownsStore.state {
                case .loading:
                    ProgressView()
                case .empty:
                    Text("0")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("No mechanical issues reported. Tap Report issue on the Vehicle card if something changes.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                case .error:
                    Text("—")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Text("Couldn't reach Zeun service. Retry.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                case .loaded(let rows):
                    Text("\(rows.count)")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(4), id: \.id) { r in
                            // Tap-to-drill — opens the full breakdown
                            // detail with diagnosis, status timeline,
                            // and the status-update mutation.
                            Button { openReportId = r.id } label: {
                                HStack {
                                    Text(r.issueCategory.capitalized)
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    StatusPill(
                                        text: r.status,
                                        kind: r.status.uppercased() == "RESOLVED" ? .success : .warning
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { await breakdownsStore.refresh() }

        // ─── Action row — closes the 12-feature delta vs. the web
        // platform ZeunBreakdown + ZeunProviderNetwork pages.
        // "Report breakdown" launches the guided report flow that
        // posts to `zeunMechanics.reportBreakdown`. "Find provider"
        // opens the directory backed by `findProviders`/`searchProviders`.
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("ACTIONS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                CTAButton(title: "Report breakdown") {
                    MeAction.fire("zeun.report-breakdown")
                    showReporter = true
                }
                Button {
                    MeAction.fire("zeun.find-provider")
                    showProviders = true
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Find a repair shop")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showReporter) {
            ZeunBreakdownReporter().eusoSheet()
        }
        .sheet(isPresented: $showProviders) {
            ZeunProviderNetwork().eusoSheet()
        }
        .sheet(item: Binding(
            get: { openReportId.map { ZeunDetailRoute(id: $0) } },
            set: { openReportId = $0?.id }
        )) { route in
            ZeunBreakdownDetail(reportId: route.id).eusoSheet()
        }

        // Inspection (DVIR) section — live from `InspectionsHistoryStore`.
        // The "47 days compliant" hero and the 5-row seeded inspection
        // list are both gone.
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("INSPECTION HISTORY")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                Text("\(historyStore.items.count) logged")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Pre + post trip logs live from the backend once you've submitted your first inspection.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                ComplianceInlineChip(tag: .eDvir)
                    .padding(.top, 2)
                CTAButton(title: "Start pre-trip DVIR") {
                    MeAction.fire("dvir.start-pretrip")
                    NotificationCenter.default.post(
                        name: .eusoStartPretripDVIR,
                        object: nil
                    )
                }
                .padding(.top, Space.s2)
            }
        }

        ComplianceInlinePanel(
            tags: [.overfill, .auxPump, .warningDevice],
            topic: "Vehicle equipment rules (Mar 23, 2026)"
        )

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recent inspections".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            if historyStore.items.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.shield",
                    title: "No DVIR entries yet",
                    subtitle: "Your pre-trip + post-trip inspections log here the moment they submit."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(historyStore.items.enumerated()), id: \.offset) { idx, e in
                        HStack(spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((e.reportType ?? "DVIR").capitalized)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                Text(e.reportDate ?? "—")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            StatusPill(
                                text: (e.overallCondition ?? "—").capitalized,
                                kind: (e.defectsFound ?? 0) > 0 ? .warning : .success
                            )
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        if idx < historyStore.items.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .eusoCard(radius: Radius.lg)
            }
        }
        .task { await historyStore.refresh() }
    }
}

// MARK: - 8b. ELD (Electronic Logging Device — HoS + duty status)
//
// Ports the web `eldRouter` surface (server/routers/eld.ts) into the same
// visual language as MeZeunView. Four regions, top to bottom:
//   • Duty-status hero card (current status + shift clock)
//   • Clock tiles (drive remaining · shift remaining · break · 70-hr cycle)
//   • Today's events list (grade-3 log-grade ELD events)
//   • Violations + provider status footer
//
// Numbers here are representative — live wiring comes through the
// `eld.getDriverStatus` / `eld.getLogs` / `eld.getViolations` tRPC calls
// in a follow-up brick. Shape matches 49 CFR 395 HoS limits as declared in
// the server router (11h drive, 14h on-duty, 30-min break, 70/8 cycle).

struct MeEldView: View {
    @Environment(\.palette) var palette
    @StateObject private var store = HOSLiveStore()
    @State private var showCertify = false

    /// Presents `ELDIntegrationView` as a sheet. Driven by the footer pill /
    /// Connect CTA — once the driver types in their vendor API key there,
    /// `hos.getStatus` (which `HOSLiveStore` already polls) flips from
    /// self-reported to vendor-sourced with no other code path changes.
    @State private var showingELDIntegration = false

    // FMCSA §395.3: 14-hour on-duty window. Bars scale against this.
    private let maxBarMinutes: Int = 14 * 60

    // MARK: Derived values from the live store

    private var currentDutyLabel: String {
        switch store.currentDuty {
        case .driving:      return "Driving"
        case .onDuty:       return "On-Duty"
        case .sleeperBerth: return "Sleeper"
        case .offDuty:      return "Off-Duty"
        }
    }

    private var currentDutyPillKind: StatusPill.Kind {
        switch store.currentDuty {
        case .driving:      return .success
        case .onDuty:       return .info
        case .sleeperBerth: return .neutral
        case .offDuty:      return .neutral
        }
    }

    private var driveRemainingDisplay: String {
        store.status.map { HOSStatus.formatHours($0.drivingRemaining) } ?? "—"
    }

    private var shiftRemainingDisplay: String {
        store.status.map { HOSStatus.formatHours($0.onDutyRemaining) } ?? "—"
    }

    private var cycleRemainingDisplay: String {
        store.status.map { HOSStatus.formatHours($0.cycleRemaining) } ?? "—"
    }

    /// 30-min break tile — "Complete" when not approaching, otherwise
    /// the countdown minutes or "Due now".
    private var breakTileValue: String {
        guard let status = store.status else { return "—" }
        if status.breakRequired { return "Due now" }
        if let mins = store.minutesUntilBreak, mins < 30 {
            return "\(mins)m"
        }
        return "Complete"
    }

    private var milesTodayDisplay: String {
        guard let miles = store.today?.milesDriven else { return "—" }
        return String(format: "%.0f", miles)
    }

    /// Project shift-end clock from onDutyRemaining.
    private var shiftEndsDisplay: String {
        guard let status = store.status, status.onDutyRemaining > 0 else { return "—" }
        let target = Date().addingTimeInterval(status.onDutyRemaining * 3600)
        return MeEldView.shiftEndFormatter.string(from: target)
    }

    private static let shiftEndFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let isoSegmentFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: Cycle chart

    private var cycleUsedMinutes: Int {
        store.history.reduce(0) { $0 + $1.onDutyMinutes }
    }

    private var cycleUsedLabel: String {
        let h = cycleUsedMinutes / 60, m = cycleUsedMinutes % 60
        return String(format: "%dh %02dm", h, m)
    }

    private var cycleRemainingLabel: String {
        let remaining = max(0, 70 * 60 - cycleUsedMinutes)
        let h = remaining / 60, m = remaining % 60
        return String(format: "%dh %02dm", h, m)
    }

    /// Ordered oldest-first for the chart (server returns newest-first).
    private var cycleByDay: [HOSDailyLog] {
        Array(store.history.reversed())
    }

    // MARK: Body

    var body: some View {
        // Wrapped in Group so the live-data modifiers (.task, .refreshable,
        // .alert, .overlay toast) attach to a single view instead of the
        // implicit TupleView. The parent MeDetailContainer stacks each
        // slot in its own scroll view, so the Group's children lay out
        // vertically the same way they did before.
        Group {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("CURRENT DUTY STATUS")
                            .font(EType.micro).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        StatusPill(text: currentDutyLabel, kind: currentDutyPillKind)
                    }
                    Text(driveRemainingDisplay)
                        .font(.system(size: 52, weight: .bold))
                        .monospacedDigit()
                        // §6.3 — HOS clock counts down. `numericText`
                        // morphs digit-by-digit (odometer feel) instead
                        // of popping the whole string on every poll.
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.spring(.smooth), value: store.status?.drivingRemaining)
                        .foregroundStyle(LinearGradient.diagonal)
                        .redacted(reason: store.status == nil ? .placeholder : [])
                    Text(shiftEndsDisplay == "—"
                         ? "Drive time remaining"
                         : "Drive time remaining · shift ends \(shiftEndsDisplay)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            HStack(spacing: Space.s3) {
                MetricTile(label: "Shift remaining", value: shiftRemainingDisplay, gradientNumeral: true)
                MetricTile(label: "30-min break",    value: breakTileValue)
            }
            HStack(spacing: Space.s3) {
                MetricTile(label: "70-hr cycle",     value: cycleRemainingDisplay)
                MetricTile(label: "Miles today",     value: milesTodayDisplay)
            }

            todaysLogCard
            cycleChartCard
            complianceCard
            eldStatusFooter
        }
        .task { await store.bootstrap() }
        .refreshable { await store.refreshAll() }
        .alert("Certify today's log", isPresented: $showCertify) {
            Button("Certify", role: .none) {
                Task {
                    await store.certify(signature: "ios-self-cert")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("By certifying you affirm that today's record of duty status is true and complete, per 49 CFR §395.8(g).")
        }
        .overlay(alignment: .top) {
            if let toast = store.lastToast {
                Text(toast)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .eusoCard(radius: Radius.sm, intensity: .whisper)
                    .padding(.top, Space.s2)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingELDIntegration) {
            ELDIntegrationView()
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var todaysLogCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Today's log".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            if let entries = store.today?.entries, !entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                        logRow(entry)
                        if idx < entries.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .eusoCard(radius: Radius.lg)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No log entries yet today")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Your first duty-status change will appear here.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s4)
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    @ViewBuilder
    private func logRow(_ entry: HOSLogEntry) -> some View {
        HStack(spacing: Space.s3) {
            Text(MeEldView.isoSegmentFormatter.string(from: entry.startDate))
                .font(EType.bodyStrong.monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.duty.shortLabel + " · " + dutyLongLabel(entry.duty))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(entry.locationDescription ?? entry.remark ?? "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusPill(
                text: durationLabel(entry),
                kind: pillKind(for: entry.duty)
            )
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func dutyLongLabel(_ duty: HOSDutyCode) -> String {
        switch duty {
        case .driving:      return "Driving"
        case .onDuty:       return "On-Duty"
        case .sleeperBerth: return "Sleeper"
        case .offDuty:      return "Off-Duty"
        }
    }

    private func pillKind(for duty: HOSDutyCode) -> StatusPill.Kind {
        switch duty {
        case .driving:      return .success
        case .onDuty:       return .info
        case .sleeperBerth: return .neutral
        case .offDuty:      return .warning
        }
    }

    private func durationLabel(_ entry: HOSLogEntry) -> String {
        if let mins = entry.durationMinutes {
            let h = mins / 60, m = mins % 60
            if h == 0 { return "\(m)m" }
            if m == 0 { return "\(h)h" }
            return "\(h)h \(String(format: "%02d", m))m"
        }
        if entry.endDate == nil { return "—" }
        return ""
    }

    @ViewBuilder
    private var cycleChartCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("70-hr cycle · 8-day".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cycleUsedLabel)
                            .font(.system(size: 28, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Used · \(cycleRemainingLabel) remaining")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    if let status = store.status {
                        StatusPill(
                            text: status.breakRequired ? "Break due" : "§395.8",
                            kind: status.breakRequired ? .warning : .info
                        )
                    }
                }

                if cycleByDay.isEmpty {
                    Text("Awaiting first sync from ELD")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.s4)
                } else {
                    HStack(alignment: .bottom, spacing: Space.s2) {
                        ForEach(Array(cycleByDay.enumerated()), id: \.offset) { _, day in
                            cycleBar(day: day)
                        }
                    }
                    .frame(height: 92)
                }

                HStack {
                    Label {
                        Text("Drive")
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                    } icon: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient.diagonal)
                            .frame(width: 10, height: 10)
                    }
                    Label {
                        Text("On-duty")
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                    } icon: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.tintNeutral)
                            .frame(width: 10, height: 10)
                    }
                    Spacer()
                    Text("FMCSA 14-hour cap")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    @ViewBuilder
    private var complianceCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("COMPLIANCE · 30d")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(
                        text: store.violations.isEmpty ? "Clean" : "\(store.violations.count) issue\(store.violations.count == 1 ? "" : "s")",
                        kind: store.violations.isEmpty ? .success : .warning
                    )
                }
                Text("\(store.violations.count) violation\(store.violations.count == 1 ? "" : "s")")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                if store.violations.isEmpty {
                    Text("No HoS exceedance, certification gaps, or unassigned segments in the last 30 days.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                } else if let first = store.violations.first {
                    Text(first.message ?? first.type ?? "HOS violation flagged — open 019 for details")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Button {
                    showCertify = true
                } label: {
                    Text(store.today?.certified == true ? "Certified for today" : "Certify today's log")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(store.today?.certified == true ? palette.textSecondary : Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            if store.today?.certified == true {
                                palette.bgCardSoft
                            } else {
                                LinearGradient.diagonal
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .disabled(store.today?.certified == true)
                .padding(.top, Space.s2)
            }
        }
    }

    @ViewBuilder
    private var eldStatusFooter: some View {
        // Tap opens the ELD Integration sheet — entry point for pasting the
        // vendor API key. Once saved server-side, the same `hos.getStatus`
        // feed this store already consumes starts returning vendor-sourced
        // duty status (Samsara/Motive/Geotab/etc.), satisfying 49 CFR 395.22(b).
        Button {
            showingELDIntegration = true
        } label: {
            HStack(spacing: Space.s2) {
                Circle()
                    .fill(store.status == nil ? palette.tintNeutral : palette.tintSuccess)
                    .frame(width: 8, height: 8)
                Text(store.status == nil ? "ELD · connecting…" : "ELD · live · backed by hos.getStatus")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let fresh = HOSClockService.shared.status, fresh == store.status {
                    Text("Last sync \(Self.relativeLabel(for: Date()))")
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage ELD integration")
        .accessibilityHint("Connect or update your Electronic Logging Device provider so HOS data flows in real time.")
    }

    private static func relativeLabel(for date: Date) -> String {
        let delta = Int(Date().timeIntervalSince(date))
        if delta < 5 { return "just now" }
        if delta < 60 { return "\(delta)s ago" }
        let m = delta / 60
        return "\(m)m ago"
    }

    // Per-day bar for the 70-hour cycle recap. Drive portion drawn in the
    // iridescent diagonal gradient, non-drive on-duty portion in the soft
    // neutral tint so violations + reset days read at a glance.
    @ViewBuilder
    private func cycleBar(day: HOSDailyLog) -> some View {
        GeometryReader { proxy in
            let totalH = proxy.size.height
            let onDutyH = totalH * CGFloat(day.onDutyMinutes) / CGFloat(maxBarMinutes)
            let driveH  = totalH * CGFloat(day.drivingMinutes) / CGFloat(maxBarMinutes)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.tintNeutral)
                        .frame(height: max(onDutyH, 4))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(height: max(driveH, 0))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            let isToday = (day.date == store.today?.date)
            VStack(spacing: 2) {
                Text(MeEldView.weekdayLabel(for: day.date))
                    .font(EType.micro)
                    .foregroundStyle(isToday ? palette.textPrimary : palette.textTertiary)
                if isToday {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                } else if day.onDutyMinutes == 0 {
                    Text("OFF")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .offset(y: 20)
        }
        .padding(.bottom, 22)
    }

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static func weekdayLabel(for date: String) -> String {
        guard let d = dayParser.date(from: date) else { return "" }
        return weekdayFormatter.string(from: d)
    }
}

// MARK: - 8c. Fleet Management (vehicles · trailers · geofences · IFTA)
//
// Ports the web `fleetRouter` + `vehicleRouter` surfaces (server/routers/
// fleet.ts, vehicle.ts) into the driver Me tab. Owner-operators and small-
// fleet drivers use this surface to see their own equipment, pending
// inspections, fuel/IFTA posture, and geofence alerts at a glance. Deep
// fleet admin (add vehicle, edit driver assignments) routes to a desktop/
// web flow — this view is the driver-facing read hub.
//
// Four regions, top to bottom:
//   • Fleet health hero (total vehicles · active · utilization)
//   • Equipment tiles (tractor · trailer · fuel · odometer)
//   • Assignments list (my assigned equipment)
//   • Geofence alerts card + IFTA quarterly CTA

struct MeFleetView: View {
    @Environment(\.palette) var palette

    // Canonical wiring: `fleet.getVehicles` (MCP-verified at
    // frontend/server/routers/fleet.ts:117). Returns the driver's
    // assigned vehicles. Empty = no vehicle assigned yet (honest zero
    // state), not "coming soon".
    @StateObject private var vehiclesStore = FleetVehiclesStore()

    var body: some View {
        switch vehiclesStore.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).task { await vehiclesStore.refresh() }
        case .empty, .error:
            EusoEmptyState(
                systemImage: "truck.box",
                title: "No vehicle assigned",
                subtitle: "Dispatch will assign a tractor and trailer — once they do you'll see them here with health, fuel, and maintenance.",
                comingSoon: false
            )
            .task { await vehiclesStore.refresh() }
        case .loaded(let vehicles):
            VStack(spacing: Space.s3) {
                ForEach(vehicles) { v in
                    HStack(alignment: .center, spacing: Space.s3) {
                        Image(systemName: v.kind == "tractor" ? "truck.box.fill" : "box.truck.badge.clock")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(palette.bgCardSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.unitNumber)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text([v.make, v.model, v.year.map(String.init)]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        if let status = v.status {
                            StatusPill(
                                text: status.capitalized,
                                kind: status.lowercased() == "active" ? .success : .neutral
                            )
                        }
                    }
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity)
                    .eusoCard(radius: Radius.lg)
                }
            }
        }
    }
}

// MARK: - 9. The Haul (gamification hub)
//
// Ports the web /the-haul page into a 4-tab sheet. This is the ecosystem's
// "digital truck stop" — the one place in the app where drivers, dispatch,
// and fleet owners can hang out together between jobs. Tabs:
//   • Lobby       — moderated real-time chat (the ecosystem glue)
//   • Missions    — quick view of active + claimable
//   • Rewards     — quick tier + points snapshot
//   • Leaderboard — seasonal rank (kept from the prior revision)
//
// Each non-Lobby tab offers a "See full" CTA that posts the corresponding
// MeDetailRoute through the esangOpenMeDetail notification — same path
// ESANG uses for voice, so tapping and speaking behave identically.
//
// Lobby state is local-only right now; the web router `lobbyModeration`
// ships live wiring next. The moderation scaffold (CIRCUMVENTION / PII_LEAK
// / PROFANITY / HARASSMENT / SOLICITATION / FLOODING) renders as a
// guidelines banner so drivers know this room is policed.

// MeHaulView — unified Haul surface. Four tabs stacked under one
// screen, every tab live-wired to a real server endpoint. Lobby +
// Missions + Rewards + Leaderboard all render under the single
// "Me · Haul" entry per the doctrine: "they all go under there."
// No mockups. No fake data. No stubs.

struct MeHaulView: View {
    @Environment(\.palette) var palette
    @State private var tab: HaulTab = .lobby

    enum HaulTab: String, CaseIterable, Identifiable {
        case lobby, missions, rewards, leaderboard
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lobby:       return "Lobby"
            case .missions:    return "Missions"
            case .rewards:     return "Rewards"
            case .leaderboard: return "Leaderboard"
            }
        }
        var icon: String {
            switch self {
            case .lobby:       return "bubble.left.and.bubble.right"
            case .missions:    return "flag.checkered"
            case .rewards:     return "gift"
            case .leaderboard: return "trophy"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            tabPicker
            Group {
                switch tab {
                case .lobby:       HaulLobbyTab()
                case .missions:    HaulMissionsTab()
                case .rewards:     HaulRewardsTab()
                case .leaderboard: HaulLeaderboardTab()
                }
            }
        }
    }

    private var tabPicker: some View {
        // 4 pills (Lobby / Missions / Rewards / Leaderboard) overflow
        // on narrow iPhones once the active pill is gradient-tinted —
        // the previous static HStack clipped the leading "Lobby" pill
        // off-screen the moment a different tab was tapped. Horizontal
        // ScrollView with hidden indicators preserves the design AND
        // keeps every tab reachable.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(HaulTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(t.label)
                                .font(EType.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(tab == t
                                      ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.22))
                                      : AnyShapeStyle(palette.bgCardSoft))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                tab == t ? Color.clear : palette.borderFaint,
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(tab == t
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Haul · Leaderboard tab

private struct HaulLeaderboardTab: View {
    @Environment(\.palette) var palette

    // Canonical wiring: `gamification.getLeaderboard` (MCP-verified at
    // frontend/server/routers/gamification.ts:294). Role-filtered by
    // default — drivers see drivers, catalysts see catalysts, etc.
    @StateObject private var leaderboardStore = LeaderboardStore()

    var body: some View {
        switch leaderboardStore.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).task { await leaderboardStore.refresh() }
        case .empty:
            EusoEmptyState(
                systemImage: "trophy",
                title: "Season still warming up",
                subtitle: "First rankings post after the weekend reset. Your loads this week feed the board.",
                comingSoon: false
            )
            .task { await leaderboardStore.refresh() }
        case .error:
            EusoEmptyState(
                systemImage: "trophy",
                title: "Couldn't load leaderboard",
                subtitle: "Pull to refresh — the Haul service will be back momentarily."
            )
            .task { await leaderboardStore.refresh() }
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                // Column header strip — anchors the row layout so the
                // RANK / DRIVER / XP columns line up vertically and
                // the leaderboard reads as a real ranking table, not
                // a stack of disconnected pills.
                HStack(spacing: Space.s3) {
                    Text("RANK")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 36, alignment: .leading)
                    Text("DRIVER")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("XP")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s2)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
                        ForEach(rows) { row in
                            HStack(alignment: .center, spacing: Space.s3) {
                                Text("\(row.rank)")
                                    .font(EType.bodyStrong.monospacedDigit())
                                    .foregroundStyle(row.isCurrentDriver
                                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                                     : AnyShapeStyle(palette.textPrimary))
                                    .frame(width: 36, alignment: .leading)
                                Text(row.displayName)
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 6)
                                Text(Int(row.score).formatted())
                                    .font(EType.bodyStrong.monospacedDigit())
                                    .foregroundStyle(row.isCurrentDriver
                                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                                     : AnyShapeStyle(palette.textSecondary))
                            }
                            .padding(.vertical, Space.s3)
                            .padding(.horizontal, Space.s4)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .fill(row.isCurrentDriver
                                          ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.12))
                                          : AnyShapeStyle(palette.bgCard))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(
                                        row.isCurrentDriver
                                            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.4))
                                            : AnyShapeStyle(palette.borderFaint),
                                        lineWidth: row.isCurrentDriver ? 1 : 0.5
                                    )
                            )
                        }
                    }
                    .padding(.bottom, Space.s4)
                }
            }
        }
    }
}

// MARK: - Haul · Lobby tab (moderated driver chat)
//
// Global multi-role chat room — drivers, dispatch, and fleet owners
// all read and post here. Wired to the real `messages.getMessages`
// / `messages.sendMessage` procs via `PulseLobbyStore` against the
// `driver-lobby` conversation id (same contract as the web app's
// TheHaul page). No local @State message seed. Every message that
// renders came from the server. Every outgoing message round-trips
// through `messaging.sendMessage` and refreshes the feed.
//
// Role color is derived from the message sender's server-returned
// `senderName` + role hints; absent a role hint we render the
// driver badge so a freshly-seeded server row still lands with a
// consistent look instead of a blank chip.

private struct HaulLobbyTab: View {
    @Environment(\.palette) var palette

    enum Role { case driver, dispatch, fleet, staff
        var label: String {
            switch self {
            case .driver: return "Driver"
            case .dispatch: return "Dispatch"
            case .fleet: return "Fleet"
            case .staff: return "EusoTrip"
            }
        }
        var color: Color {
            switch self {
            case .driver: return Brand.info
            case .dispatch: return Brand.success
            case .fleet: return Brand.warning
            case .staff: return Brand.magenta
            }
        }
        var eusoBadgeKind: EusoBadgeKind {
            switch self {
            case .driver:   return .info
            case .dispatch: return .success
            case .fleet:    return .warning
            case .staff:    return .hot
            }
        }
    }

    @StateObject private var store = PulseLobbyStore()
    @State private var draft: String = ""
    @State private var isPosting: Bool = false
    @State private var postError: String?

    private static let lobbyConversationId = "driver-lobby"

    private var liveMessages: [MessagingMessage] {
        store.items
    }

    private var activeCount: Int {
        // Unique senders over the last 50 messages — best-effort "active
        // now" signal. Clamped to 0 when the feed is empty so the header
        // never displays a fabricated count.
        let senders = Set(liveMessages.prefix(50).map { $0.senderId })
        return senders.count
    }

    var body: some View {
        // ─── Active-now header ───────────────────────────────────────
        HStack(spacing: Space.s2) {
            ZStack {
                Circle().fill(Brand.success).frame(width: 8, height: 8)
                Circle().stroke(Brand.success.opacity(0.45), lineWidth: 4).frame(width: 8, height: 8)
            }
            Text("\(activeCount) drivers online")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold))
                Text("Moderated")
                    .font(EType.micro).tracking(0.4)
            }
            .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

        // ─── Community guidelines callout ────────────────────────────
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Community guidelines")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Keep it professional. No phone numbers, no load solicitation, no harassment. Strikes auto-pause your posting privileges.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.warning.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))

        // ─── Messages feed ───────────────────────────────────────────
        Group {
            switch store.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            case .empty:
                EusoEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "Lobby's quiet",
                    subtitle: "Be the first to say hi. Messages post under your driver name.",
                    comingSoon: false
                )
            case .error:
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Lobby offline",
                    subtitle: "Pull to refresh — the Haul service will be back momentarily."
                )
            case .loaded:
                VStack(spacing: Space.s3) {
                    ForEach(liveMessages) { m in
                        messageBubble(m)
                    }
                }
            }
        }
        .task { await store.refresh() }

        // ─── Composer ────────────────────────────────────────────────
        if let err = postError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.warning)
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Space.s3)
        }
        HStack(spacing: Space.s2) {
            TextField("Say something to the Haul…", text: $draft, axis: .vertical)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .lineLimit(1...3)
                .disabled(isPosting)
            Button {
                Task { await send() }
            } label: {
                Group {
                    if isPosting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .heavy))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? AnyShapeStyle(palette.bgCardSoft)
                                  : AnyShapeStyle(LinearGradient.diagonal))
                )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
        }
        .padding(.top, Space.s2)
    }

    private func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        postError = nil
        isPosting = true
        defer { isPosting = false }
        // The lobby uses a dedicated `messaging.sendLobbyMessage`
        // procedure that resolves the caller → company → "The Lobby"
        // conversation server-side. The previous implementation called
        // the canonical `messages.sendMessage` with conversationId
        // = "driver-lobby" (a string token), which the server's
        // parseInt rejected with "Invalid conversation ID" — so every
        // lobby post failed silently. The dedicated endpoint takes
        // just `{text}` and handles routing internally.
        struct In: Encodable { let text: String }
        struct Out: Decodable { let messageId: Int; let conversationId: Int }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "messaging.sendLobbyMessage",
                input: In(text: trimmed)
            )
            draft = ""
            await store.refresh()
        } catch {
            postError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't post — try again in a moment."
        }
    }

    // MARK: - Rendering helpers

    /// Infer role from the server row. `metadata.senderName` wins when
    /// present, then `senderName` + a small keyword sniff; otherwise
    /// the message is tagged as a driver so every post still carries
    /// a recognizable chip instead of rendering unbranded.
    private func inferredRole(_ m: MessagingMessage) -> Role {
        let hint = (m.senderName ?? "").lowercased()
        if hint.contains("dispatch") { return .dispatch }
        if hint.contains("fleet")    { return .fleet }
        if hint.contains("eusotrip") || hint.contains("staff") || hint.contains("admin") {
            return .staff
        }
        return .driver
    }

    private func isSelf(_ m: MessagingMessage) -> Bool {
        m.isOwn == true
    }

    private func displayName(_ m: MessagingMessage) -> String {
        if isSelf(m) { return "You" }
        return m.senderName ?? "Driver"
    }

    private func initials(_ m: MessagingMessage) -> String {
        let name = displayName(m)
        let parts = name.split(separator: " ")
        if let first = parts.first?.prefix(1),
           let second = parts.dropFirst().first?.prefix(1) {
            return (String(first) + String(second)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func timeLabel(_ m: MessagingMessage) -> String {
        guard let iso = m.timestamp else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }

    @ViewBuilder
    private func messageBubble(_ m: MessagingMessage) -> some View {
        let self_ = isSelf(m)
        let role = inferredRole(m)
        HStack(alignment: .top, spacing: Space.s3) {
            if !self_ { avatar(m, role: role) }
            VStack(alignment: self_ ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if self_ { Spacer() }
                    Text(displayName(m)).font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    EusoBadge(label: role.label, kind: role.eusoBadgeKind)
                    Text(timeLabel(m))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(m.content)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .padding(Space.s3)
                    .background(
                        Group {
                            if self_ {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(LinearGradient.diagonal.opacity(0.18))
                            } else {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(palette.bgCard)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: self_ ? .trailing : .leading)
            }
            if self_ { avatar(m, role: role) }
        }
    }

    @ViewBuilder
    private func avatar(_ m: MessagingMessage, role: Role) -> some View {
        ZStack {
            Circle()
                .fill(role.color.opacity(0.22))
            Text(initials(m))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(role.color)
        }
        .frame(width: 32, height: 32)
        .overlay(Circle().strokeBorder(palette.borderFaint))
    }
}

// MARK: - Haul · Missions snapshot tab
//
// Wired to `gamification.getMissions` (MCP-verified at
// frontend/server/routers/gamification.ts). The server returns
// three buckets — `active`, `completed`, `available` — which
// include both the template-authored missions AND the AI-generated
// ones. AI missions plug into the same `missionProgress` tracking
// table, so they render identically: same progress bar, same
// targetValue / currentProgress / status, same reward fields.
//
// No fake data, no stubs. When a driver has zero active missions
// we surface the `available` bucket so they can start one without
// being sent back to the deep 061 screen.

private struct HaulMissionsTab: View {
    @Environment(\.palette) var palette

    @State private var response: GamificationAPI.MissionsResponse?
    @State private var isLoading: Bool = false
    @State private var lastError: String?
    @State private var mutatingId: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if isLoading && response == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            } else if let err = lastError, response == nil {
                EusoEmptyState(
                    systemImage: "flag.checkered",
                    title: "Couldn't load missions",
                    subtitle: err
                )
            } else if let r = response {
                if !r.active.isEmpty {
                    sectionHeader("Active")
                    ForEach(r.active) { m in
                        missionCard(m)
                    }
                }
                if !r.available.isEmpty {
                    sectionHeader("Available")
                    ForEach(r.available.prefix(4)) { m in
                        missionCard(m)
                    }
                }
                if r.active.isEmpty && r.available.isEmpty {
                    EusoEmptyState(
                        systemImage: "flag.checkered",
                        title: "No missions right now",
                        subtitle: "New missions post automatically as you run loads — AI generates them on top of the weekly drop.",
                        comingSoon: false
                    )
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            response = try await EusoTripAPI.shared.gamification.getMissions()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach missions service"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(EType.micro)
            .tracking(1.3)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    private func missionCard(_ m: GamificationAPI.Mission) -> some View {
        let target = max(m.targetValue ?? 1, 1)
        let current = max(0, min(m.currentProgress ?? 0, target))
        let pct = current / target
        let status = (m.status ?? "not_started").lowercased()
        let isClaimable = status == "completed"
        let isClaimed = status == "claimed"
        let isAvailable = status == "not_started"
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let desc = m.description, !desc.isEmpty {
                        Text(desc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let xp = m.xpReward, xp > 0 {
                    Text("+\(xp) XP")
                        .font(EType.micro)
                        .tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }

            if !isAvailable {
                VStack(spacing: 4) {
                    HStack {
                        Text(progressText(current: current, target: target, type: m.targetType, unit: m.targetUnit))
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("\(Int((pct * 100).rounded()))%")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.tintNeutral.opacity(0.5))
                            Capsule().fill(LinearGradient.diagonal)
                                .frame(width: max(4, geo.size.width * pct))
                        }
                    }
                    .frame(height: 6)
                }
            }

            if isClaimable {
                Button {
                    Task { await claim(m) }
                } label: {
                    HStack {
                        if mutatingId == m.id {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "gift")
                        }
                        Text(mutatingId == m.id ? "Claiming…" : "Claim reward")
                    }
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(mutatingId == m.id)
            } else if isAvailable {
                Button {
                    Task { await start(m) }
                } label: {
                    HStack {
                        if mutatingId == m.id {
                            ProgressView().tint(palette.textPrimary)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(mutatingId == m.id ? "Starting…" : "Start mission")
                    }
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s2)
                    .overlay(
                        Capsule().strokeBorder(palette.textTertiary.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(mutatingId == m.id)
            } else if isClaimed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Claimed")
                }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        )
    }

    private func progressText(
        current: Double,
        target: Double,
        type: String?,
        unit: String?
    ) -> String {
        let suffix: String = {
            if let unit, !unit.isEmpty { return " \(unit)" }
            switch (type ?? "").lowercased() {
            case "deliveries", "loads": return " loads"
            case "miles":               return " mi"
            case "earnings":            return ""
            default:                    return ""
            }
        }()
        let fmt: (Double) -> String = { v in
            v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
        }
        return "\(fmt(current)) / \(fmt(target))\(suffix)"
    }

    private func start(_ m: GamificationAPI.Mission) async {
        mutatingId = m.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.gamification.startMission(missionId: m.id)
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't start mission"
        }
    }

    private func claim(_ m: GamificationAPI.Mission) async {
        mutatingId = m.id
        defer { mutatingId = nil }
        do {
            _ = try await EusoTripAPI.shared.gamification.claimMissionReward(missionId: m.id)
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't claim mission"
        }
    }
}

// MARK: - Haul · Rewards snapshot tab
//
// Wired to `gamification.getRewardsCatalog` (MCP-verified at
// frontend/server/routers/gamification.ts:377). Server returns
// `{availablePoints, rewards, categories}` — role-scoped by the
// current user's role. The redeem CTA hits `gamification.
// redeemReward` on tap. No fake points. No fake catalog items.

private struct HaulRewardsTab: View {
    @Environment(\.palette) var palette

    @State private var availablePoints: Int = 0
    @State private var rewards: [RewardItem] = []
    @State private var isLoading: Bool = false
    @State private var lastError: String?
    @State private var redeemingId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            pointsHeader
            if isLoading && rewards.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            } else if let err = lastError, rewards.isEmpty {
                EusoEmptyState(
                    systemImage: "gift",
                    title: "Couldn't load rewards",
                    subtitle: err
                )
            } else if rewards.isEmpty {
                EusoEmptyState(
                    systemImage: "gift",
                    title: "Nothing unlocked yet",
                    subtitle: "Catalog opens as you earn points. Complete missions and clear loads to start redeeming.",
                    comingSoon: false
                )
            } else {
                ForEach(rewards) { r in
                    rewardRow(r)
                }
            }
        }
        .task { await refresh() }
    }

    private var pointsHeader: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POINTS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text("\(availablePoints)")
                    .font(EType.numeric)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
    }

    private func rewardRow(_ r: RewardItem) -> some View {
        let affordable = availablePoints >= r.pointsCost
        let busy = redeemingId == r.id
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.55))
                if let urlStr = r.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit().padding(6)
                        } else {
                            Image(systemName: "gift")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                } else {
                    Image(systemName: "gift")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(r.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let cat = r.category, !cat.isEmpty {
                    Text(cat.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            Button {
                Task { await redeem(r) }
            } label: {
                HStack(spacing: 4) {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text("\(r.pointsCost)")
                            .monospacedDigit()
                        Image(systemName: "sparkles")
                    }
                }
                .font(EType.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(affordable
                                   ? AnyShapeStyle(LinearGradient.diagonal)
                                   : AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
                )
            }
            .buttonStyle(.plain)
            .disabled(!affordable || busy || (r.inStock == false))
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        )
    }

    private func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let (points, items) = try await EusoTripAPI.shared.gamification.getRewardsCatalog()
            availablePoints = points
            rewards = items
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach rewards catalog"
        }
    }

    private func redeem(_ r: RewardItem) async {
        redeemingId = r.id
        defer { redeemingId = nil }
        do {
            _ = try await EusoTripAPI.shared.rewards.redeem(itemId: r.id)
            await refresh()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't redeem — try again in a moment."
        }
    }
}

// MARK: - 10. Settings

struct MeSettingsView: View {
    @Environment(\.palette) var palette
    @EnvironmentObject var session: EusoTripSession
    @EnvironmentObject var profile: DriverProfileStore
    @State private var pushOn = true
    @State private var soundsOn = true
    @State private var hapticsOn = true
    @State private var biometricOn = true
    @State private var signingOut = false
    /// Presents ProfileEditView over the Settings sheet. Sheet-over-sheet
    /// keeps the outer drag-to-dismiss behavior intact while giving the
    /// driver a focused surface for editing avatar + identity + contact.
    @State private var showEditProfile = false

    // ── Pulse (Apple Watch) settings ──────────────────────────────
    //
    // Every toggle persists to WatchAuthBridge (UserDefaults) AND
    // propagates to the wrist via WCSession updateApplicationContext
    // on change, so the watch honors the phone's choices without a
    // relaunch. Initial values are seeded from `currentSettings()`
    // in `.onAppear` so re-opening the sheet shows the live state.
    @State private var pulseTurnByTurn: Bool = true
    @State private var pulseVoiceWake: Bool = false
    @State private var pulseDrivingAutoDetect: Bool = true
    @State private var pulseHapticsIntensity: String = "standard"
    @State private var pulseComplicationStyle: String = "orb"
    @State private var pulseLastSync: Date? = nil
    @State private var pulseResyncing: Bool = false
    @State private var pulseResyncToast: String? = nil

    var body: some View {
        Button {
            showEditProfile = true
        } label: {
            ActiveCard {
                HStack(alignment: .center, spacing: Space.s3) {
                    // Avatar leading — mirrors the Me tab header card so
                    // the driver recognizes this row as "their profile".
                    accountAvatar
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("ACCOUNT")
                            .font(EType.micro).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(profile.fullName)
                            .font(EType.h2)
                            .foregroundStyle(palette.textPrimary)
                        Text(profile.accountSummary)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditProfile) {
            ProfileEditView()
                .environmentObject(profile)
        }

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Notifications".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                toggleRow(title: "Push notifications",
                          sub: "Load offers, HOS alerts, payouts",
                          isOn: $pushOn)
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                toggleRow(title: "In-app sounds",
                          sub: "Alert tones + chat pings",
                          isOn: $soundsOn)
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                toggleRow(title: "Haptics",
                          sub: "Buttons, confirmations, ESANG",
                          isOn: $hapticsOn)
            }
            .eusoCard(radius: Radius.lg)
        }

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Security".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                toggleRow(title: "Face ID unlock",
                          sub: "Required on cold launch",
                          isOn: $biometricOn)
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                linkRow(title: "Change password", sub: "Last rotated 42 days ago")
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                linkRow(title: "Sessions + devices", sub: "2 trusted devices")
            }
            .eusoCard(radius: Radius.lg)
        }

        // ── PULSE · APPLE WATCH ──────────────────────────────────
        //
        // The settings section that backs the EusoTrip Pulse wrist
        // companion. Every control here reflects real WCSession
        // state (pair status + reachability pulled live from
        // `WatchAuthBridge.pairStatus`) or writes to the shared
        // preferences that the wrist reads from
        // applicationContext["pulseSettings"]. No mock toggles.
        pulseSection
            .onAppear { loadPulseState() }

        // Sign out — wired to EusoTripSession.signOut() (Wave-5, 2026-04-20).
        // Flipping `session.phase` to .signedOut drops the user back to the
        // AppRoot switch, which re-renders SignInView. We also bubble the
        // sheet-close via dismiss-through-session-phase; AppRoot observes
        // `session.phase` and remounts.
        CTAButton(title: signingOut ? "Signing out…" : "Sign out") {
            guard !signingOut else { return }
            signingOut = true
            Task {
                await session.signOut()
                // Task-local side effect: once .phase flips to .signedOut
                // AppRoot's switch re-renders SignInView; this sheet is
                // torn down as part of that hierarchy swap.
            }
        }
        .disabled(signingOut)
        .opacity(signingOut ? 0.7 : 1.0)
    }

    @ViewBuilder
    private func toggleRow(title: String, sub: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .toggleStyle(GradientToggleStyle())
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    /// Circular profile avatar for the ACCOUNT row. Renders the saved
    /// photo if one exists, otherwise falls back to a gradient monogram
    /// identical to the Home greeting treatment so the Settings row
    /// reads as "the same person" greeted on the Home tab.
    @ViewBuilder
    private var accountAvatar: some View {
        ZStack {
            if let data = profile.avatarData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(accountInitials)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var accountInitials: String {
        let f = profile.firstName.first.map { String($0) } ?? ""
        let l = profile.lastName.first.map { String($0) } ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "ME" : s
    }

    @ViewBuilder
    private func linkRow(title: String, sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    // MARK: - Pulse section

    @ViewBuilder
    private var pulseSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Pulse · Apple Watch".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            // Live status + actions
            VStack(spacing: 0) {
                pulsePairStatusRow
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                pulseResyncRow
            }
            .eusoCard(radius: Radius.lg)

            // Behavior toggles
            VStack(spacing: 0) {
                pulseToggle(
                    title: "Turn-by-turn on wrist",
                    sub: "Shows active-load directions on the watch",
                    isOn: $pulseTurnByTurn,
                    onChange: { updatePulseSetting("turnByTurn", $0) }
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                pulseToggle(
                    title: "Voice wake (\"Hey ESANG\")",
                    sub: "Always-listen on the watch. Drains battery faster.",
                    isOn: $pulseVoiceWake,
                    onChange: { updatePulseSetting("voiceWakeWord", $0) }
                )
                Divider().overlay(palette.borderFaint).padding(.leading, 56)
                pulseToggle(
                    title: "Auto-detect driving",
                    sub: "Kicks trip mode when your truck starts moving",
                    isOn: $pulseDrivingAutoDetect,
                    onChange: { updatePulseSetting("drivingAutoDetect", $0) }
                )
            }
            .eusoCard(radius: Radius.lg)

            // Haptics intensity picker
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Haptics intensity")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s3)
                Text("How strong the wrist taps feel. Light saves battery; strong is easier to feel through gloves.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s4)
                HStack(spacing: Space.s2) {
                    ForEach(["light", "standard", "strong"], id: \.self) { option in
                        pulseHapticsPill(option)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s3)
            }
            .eusoCard(radius: Radius.lg)

            // Complication style — watch face glance
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Complication style")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s4)
                    .padding(.top, Space.s3)
                Text("Pick what the EusoTrip complication shows on your watch face.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s4)
                HStack(spacing: Space.s2) {
                    ForEach([("orb", "ESANG orb"), ("numeric", "HOS clock"), ("hos", "Duty status")], id: \.0) { opt in
                        pulseComplicationPill(option: opt.0, label: opt.1)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s3)
            }
            .eusoCard(radius: Radius.lg)

            // Inline toast — re-sync result, 2.5s auto-dismiss
            if let toast = pulseResyncToast {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(toast)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var pulsePairStatusRow: some View {
        let status = WatchAuthBridge.shared.pairStatus
        let (label, sub, dotColor) = pulseStatusCopy(status)
        HStack(spacing: Space.s3) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if let last = pulseLastSync {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("LAST SYNC")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(relativeTimeString(last))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private var pulseResyncRow: some View {
        Button {
            Task { await resyncPulse() }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: pulseResyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .symbolEffect(.pulse, options: .repeating, isActive: pulseResyncing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pulseResyncing ? "Syncing…" : "Re-sync now")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Re-mirrors auth + active load + HOS to the watch")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pulseResyncing)
    }

    @ViewBuilder
    private func pulseToggle(title: String, sub: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                onChange(newValue)
            }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .toggleStyle(GradientToggleStyle())
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func pulseHapticsPill(_ option: String) -> some View {
        let selected = option == pulseHapticsIntensity
        Button {
            pulseHapticsIntensity = option
            updatePulseSetting("hapticsIntensity", option)
        } label: {
            Text(option.capitalized)
                .font(EType.bodyStrong)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if selected {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCardSoft)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.white.opacity(0.3) : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pulseComplicationPill(option: String, label: String) -> some View {
        let selected = option == pulseComplicationStyle
        Button {
            pulseComplicationStyle = option
            updatePulseSetting("complicationStyle", option)
        } label: {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if selected {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCardSoft)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.white.opacity(0.3) : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Pulse state helpers

    private func pulseStatusCopy(_ status: WatchAuthBridge.PairStatus) -> (String, String, Color) {
        if !status.paired {
            return ("Watch not paired",
                    "Pair an Apple Watch in the iPhone Watch app to enable Pulse.",
                    palette.textTertiary)
        }
        if !status.watchAppInstalled {
            return ("Pulse not installed",
                    "Install EusoTrip Pulse from the Watch app.",
                    palette.textTertiary)
        }
        if !status.activated {
            return ("Activating…",
                    "Syncing with Pulse on your wrist.",
                    palette.textTertiary)
        }
        if status.reachable {
            return ("Paired · live",
                    "Pulse is connected and receiving updates in real time.",
                    Brand.success)
        }
        return ("Paired · background",
                "Pulse is installed; updates queue and deliver when the watch wakes.",
                Brand.warning)
    }

    private func loadPulseState() {
        let settings = WatchAuthBridge.shared.currentSettings()
        pulseTurnByTurn         = (settings["turnByTurn"] as? Bool) ?? true
        pulseVoiceWake          = (settings["voiceWakeWord"] as? Bool) ?? false
        pulseDrivingAutoDetect  = (settings["drivingAutoDetect"] as? Bool) ?? true
        pulseHapticsIntensity   = (settings["hapticsIntensity"] as? String) ?? "standard"
        pulseComplicationStyle  = (settings["complicationStyle"] as? String) ?? "orb"
        pulseLastSync = WatchAuthBridge.shared.lastSuccessfulSyncAt
    }

    private func updatePulseSetting<V>(_ key: String, _ value: V) {
        var settings = WatchAuthBridge.shared.currentSettings()
        settings[key] = value
        WatchAuthBridge.shared.pushSettings(settings)
        pulseLastSync = WatchAuthBridge.shared.lastSuccessfulSyncAt
    }

    private func resyncPulse() async {
        pulseResyncing = true
        defer { pulseResyncing = false }
        // Re-mirror auth using EusoTripSession as the fallback source of
        // truth — handles the cold-launch case where `cachedAuth` in
        // WatchAuthBridge is nil (see `republishAuth` docs).
        let bridge = WatchAuthBridge.shared
        let token = EusoTripAPI.shared.authToken
        let userId = session.user?.id
        let userName = session.user?.name
        let role = session.user?.role
        let pushed = bridge.republishAuth(
            fallbackToken: token,
            fallbackUserId: userId,
            fallbackUserName: userName,
            fallbackRole: role
        )
        // Re-push current settings too so the wrist refreshes its
        // preferences copy (useful if the app was reinstalled).
        bridge.pushSettings(bridge.currentSettings())
        pulseLastSync = bridge.lastSuccessfulSyncAt
        // 2.5s inline toast.
        withAnimation {
            pulseResyncToast = pushed ? "Pulse re-synced" : "Nothing to sync — sign in first"
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation {
            pulseResyncToast = nil
        }
    }

    private func relativeTimeString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Pulse Watch pairing

/// Me-tab destination that shows whether the driver's iPhone is paired
/// with EusoTrip Pulse on the wrist, whether the session mirror pushed
/// after sign-in, and when the last sync landed. Added in build 30 so the
/// driver can confirm their wrist is in sync without leaving the iOS
/// shell — companion to the "LINK" indicator on the watch HomeView.
/// Made internal (was `private`) so external Screen wrappers can host
/// it from registered IDs ("PULSE" — added to both driver and
/// shipper Me Settings hubs after founder report 2026-05-04 "i see
/// no eusotrip pulse settings for either user types right now").
struct MePulseView: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var isPaired: Bool = false
    @State private var isWatchAppInstalled: Bool = false
    @State private var isReachable: Bool = false
    @State private var lastMirrorAt: Date?

    /// Timestamp of the most recent observed-reachable tick. We keep the
    /// "Live" pill sticky for `reachableStickyWindow` seconds after the
    /// last confirmed-reachable observation so the natural BLE/handoff
    /// blips that bounce WCSession.isReachable don't make the pill flap
    /// Live → Offline → Live in front of the driver. The underlying
    /// reachability signal is still polled every 2s; we just smooth it
    /// for the user-facing row.
    @State private var lastReachableAt: Date?
    private let reachableStickyWindow: TimeInterval = 15

    /// Poll WCSession every 2s. WCSession has a delegate but we'd need
    /// to plug into WatchAuthBridge's shared delegate chain — polling is
    /// fine for a destination screen the user lands on intentionally.
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            heroCard
            statusCard
            actionCard
        }
        .onAppear {
            refreshState()
            // If the user is signed in but WatchAuthBridge never got to
            // push a context this run (demo sign-in / cold launch before
            // `boot()` fires / session restored from keychain), fire a
            // fallback republish now so the wrist has fresh auth and
            // the "Last auth sync" row actually populates instead of
            // sitting on "—" forever. The bridge returns false when
            // there's nothing to send, so unsigned-in sessions are
            // safe.
            if session.phase == .signedIn {
                _ = WatchAuthBridge.shared.republishAuth(
                    fallbackToken: EusoTripAPI.shared.authToken,
                    fallbackUserId: session.user?.id,
                    fallbackUserName: session.user?.name,
                    fallbackRole: session.user?.role
                )
                // Re-read after the republish so the row shows "just now"
                // instead of the pre-republish stamp.
                refreshState()
            }
        }
        .onReceive(refresh) { _ in refreshState() }
    }

    // MARK: Cards

    private var heroCard: some View {
        ActiveCard {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 56, height: 56)
                    Image(systemName: "applewatch.watchface")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("EusoTrip Pulse")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text(pairedHeadline.uppercased())
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                statusDot
            }
        }
    }

    private var statusCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                row(icon: "iphone.and.arrow.forward",
                    title: "Watch paired",
                    value: isPaired ? "Yes" : "No",
                    tint: isPaired ? Brand.success : palette.textTertiary)
                Divider().overlay(palette.borderFaint)
                row(icon: "square.and.arrow.down.on.square",
                    title: "Pulse installed",
                    value: isWatchAppInstalled ? "Yes" : "Not installed",
                    tint: isWatchAppInstalled ? Brand.success : palette.textTertiary)
                Divider().overlay(palette.borderFaint)
                row(icon: "dot.radiowaves.left.and.right",
                    title: "Reachable now",
                    value: isReachable ? "Live" : "Offline",
                    tint: isReachable ? Brand.success : palette.textTertiary)
                Divider().overlay(palette.borderFaint)
                row(icon: "clock.arrow.2.circlepath",
                    title: "Last auth sync",
                    value: lastMirrorAt.map(Self.relative) ?? "—",
                    tint: palette.textSecondary)
            }
        }
    }

    private var actionCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Resend session")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("If the wrist still says \"Open EusoTrip on iPhone to pair\" after the app has launched, tap below to re-mirror your auth to the watch.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Button {
                    // Pass the live session's credentials as a fallback so
                    // Resync works even if `WatchAuthBridge.push` was
                    // never called this run — which happens in demo
                    // sign-in and on cold launch before `boot()` fires.
                    // `republishAuth` returns false when there's nothing
                    // to send, so we only flip "Last auth sync" on a
                    // real delivery instead of lying.
                    let sent = WatchAuthBridge.shared.republishAuth(
                        fallbackToken: EusoTripAPI.shared.authToken,
                        fallbackUserId: session.user?.id,
                        fallbackUserName: session.user?.name,
                        fallbackRole: session.user?.role
                    )
                    if sent { lastMirrorAt = Date() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Resync now")
                    }
                    .font(EType.bodyStrong)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(LinearGradient.diagonal, in: RoundedRectangle(cornerRadius: Radius.md))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(session.phase != .signedIn)
            }
        }
    }

    // MARK: Bits

    private var pairedHeadline: String {
        guard isPaired else { return "No paired watch detected" }
        guard isWatchAppInstalled else { return "Install Pulse on your watch" }
        return isReachable ? "Synced · live" : "Paired · not on wrist"
    }

    @ViewBuilder
    private var statusDot: some View {
        let ok = isPaired && isWatchAppInstalled && isReachable
        Circle()
            .fill(ok ? Color.green : (isPaired ? Color.orange : Color.gray))
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            .accessibilityLabel(ok ? "Synced" : (isPaired ? "Paired" : "Not paired"))
    }

    @ViewBuilder
    private func row(icon: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(tint)
        }
    }

    private func refreshState() {
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            let s = WCSession.default
            isPaired = s.isPaired
            isWatchAppInstalled = s.isWatchAppInstalled

            // Sticky reachable: update the "last seen live" timestamp
            // whenever the raw signal reports reachable=true, and hold
            // the pill as "Live" for `reachableStickyWindow` seconds
            // after the last tick. This matches what the driver
            // experiences — a paired watch in a paired phone's pocket
            // IS effectively live even when WCSession briefly reports
            // isReachable=false during Bluetooth hops or display-dim
            // cycles. Only when the gap exceeds the sticky window do we
            // flip to Offline.
            let raw = s.isReachable
            if raw {
                lastReachableAt = Date()
                isReachable = true
            } else if let last = lastReachableAt,
                      Date().timeIntervalSince(last) < reachableStickyWindow {
                // Within the sticky window — keep showing Live.
                isReachable = true
            } else {
                isReachable = false
            }
        }
        #endif
        // The bridge caches the last auth context it pushed; mirror its
        // timestamp so we can show the driver when the wrist was last
        // informed of their session.
        if let ctx = WatchAuthBridge.shared.lastPushedAuthContext,
           let ts = ctx["ts"] as? TimeInterval {
            lastMirrorAt = Date(timeIntervalSince1970: ts)
        }
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Carrier
//
// Surfaces the company the signed-in driver is dispatched under. Backed
// by `drivers.getMyCarrier` on the server (single round-trip — joins
// drivers → companies). Renders four sections:
//   • Identity card — name + DOT/MC + complianceStatus pill + logo
//   • Reach — phone, email, website, mailing address (tap-to-call,
//     tap-to-mail, tap-to-open)
//   • Compliance — Insurance / Hazmat / TWIC days-remaining tiles
//   • Footer — "Contact dispatch" CTA fans out a `MeAction.fire`
//
// When the driver has no company link the view renders an
// `EusoEmptyState` with an "Attach to a carrier" CTA (the wire path is
// onboarding-managed; the CTA emits a MeAction so the future flow can
// be wired without retouching this view).

@MainActor
final class DriverCarrierStore: ObservableObject {
    enum LoadState {
        case loading
        case loaded(DriversAPI.MyCarrier?)
        case error(String)
    }

    @Published private(set) var state: LoadState = .loading

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let carrier = try await api.drivers.getMyCarrier()
            state = .loaded(carrier)
        } catch {
            // Surface the actual error in console output (every build,
            // not just DEBUG) so a TestFlight / production console
            // shows whether this is auth (401) vs role-gate (403) vs
            // missing-deploy (500). Prior path collapsed every cause
            // into the same "Couldn't reach carrier service" string.
            let ns = error as NSError
            print("[DriverCarrierStore] drivers.getMyCarrier failed — domain=\(ns.domain) code=\(ns.code) desc=\(error.localizedDescription)")
            // The error string surfaces a hint when the domain matches
            // common failure modes so support knows what to chase.
            let userMsg: String = {
                let desc = error.localizedDescription.lowercased()
                if desc.contains("forbidden") || desc.contains("403") {
                    return "Carrier service is gated for your role. The fix is deployed at server commit 522752e9 — check the Azure App Service has the latest deploy."
                }
                if desc.contains("unauthorized") || desc.contains("401") {
                    return "Couldn't reach carrier service — sign-in session expired."
                }
                return "Couldn't reach carrier service."
            }()
            state = .error(userMsg)
        }
    }
}

struct MeCarrierView: View {
    @Environment(\.palette) var palette
    @StateObject private var carrierStore = DriverCarrierStore()

    var body: some View {
        Group {
            switch carrierStore.state {
            case .loading:
                ActiveCard {
                    HStack {
                        ProgressView()
                        Text("Loading your carrier…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .loaded(.none):
                EusoEmptyState(
                    systemImage: "building.2",
                    title: "No carrier linked",
                    subtitle: "Once your dispatcher attaches you to a motor carrier, their DOT, MC, insurance, and compliance signals show up here."
                )
                CTAButton(title: "Attach to a carrier") {
                    MeAction.fire("carrier.attach-request")
                }
            case .loaded(.some(let c)):
                identityCard(c)
                reachCard(c)
                complianceCard(c)
                CTAButton(title: "Contact dispatch") {
                    MeAction.fire(
                        "carrier.contact-dispatch",
                        userInfo: ["companyId": c.companyId]
                    )
                }
            case .error(let msg):
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load carrier",
                    subtitle: msg
                )
                CTAButton(title: "Retry") {
                    Task { await carrierStore.refresh() }
                }
            }
        }
        .task { await carrierStore.refresh() }
    }

    // MARK: Sections

    @ViewBuilder
    private func identityCard(_ c: DriversAPI.MyCarrier) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .center, spacing: Space.s3) {
                    // Brand monogram fallback when the carrier hasn't
                    // uploaded a logo. Initial of the trade name only.
                    Text(initial(c.name))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 48, height: 48)
                        .background(palette.bgCardSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name ?? "—")
                            .font(EType.h2)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if let legal = c.legalName, legal != c.name {
                            Text(legal)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    StatusPill(
                        text: (c.complianceStatus ?? "—").capitalized,
                        kind: complianceKind(c.complianceStatus)
                    )
                }
                HStack(spacing: Space.s3) {
                    MetricTile(label: "DOT", value: c.dotNumber ?? "—")
                    MetricTile(label: "MC",  value: c.mcNumber ?? "—")
                }
                if let cat = c.companyCategory {
                    Text(cat.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func reachCard(_ c: DriversAPI.MyCarrier) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("REACH")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                contactRow(icon: "phone.fill", value: c.phone) {
                    if let p = c.phone, let url = URL(string: "tel:\(p.filter { "+0123456789".contains($0) })") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                contactRow(icon: "envelope.fill", value: c.email) {
                    if let e = c.email, let url = URL(string: "mailto:\(e)") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                contactRow(icon: "globe", value: c.website) {
                    if let w = c.website, let url = URL(string: w.hasPrefix("http") ? w : "https://\(w)") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                if let addr = mailingAddress(c) {
                    Divider().overlay(palette.borderFaint)
                    Text(addr)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func complianceCard(_ c: DriversAPI.MyCarrier) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("COMPLIANCE WINDOWS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.s3) {
                    MetricTile(label: "Insurance",
                               value: daysLabel(c.insuranceDaysRemaining))
                    MetricTile(label: "Hazmat",
                               value: daysLabel(c.hazmatDaysRemaining))
                    MetricTile(label: "TWIC",
                               value: daysLabel(c.twicDaysRemaining))
                }
                if anyExpiringSoon(c) {
                    Text("A red or amber window means dispatch has a cert about to lapse — flag it before it gates your next load.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func contactRow(icon: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 22)
                Text(value ?? "—")
                    .font(EType.body)
                    .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if value != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(value == nil)
    }

    private func mailingAddress(_ c: DriversAPI.MyCarrier) -> String? {
        let parts: [String] = [
            c.address,
            [c.city, c.state].compactMap { $0 }.joined(separator: ", ").nilIfBlank,
            c.zipCode,
            c.country == "USA" ? nil : c.country
        ].compactMap { $0?.nilIfBlank }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func initial(_ name: String?) -> String {
        guard let first = name?.first else { return "—" }
        return String(first).uppercased()
    }

    private func complianceKind(_ raw: String?) -> StatusPill.Kind {
        switch (raw ?? "").lowercased() {
        case "compliant":      return .success
        case "pending":        return .info
        case "expired":        return .warning
        case "non_compliant":  return .danger
        default:               return .info
        }
    }

    private func daysLabel(_ d: Int?) -> String {
        guard let d else { return "—" }
        if d <= 0 { return "Lapsed" }
        if d == 1 { return "1 day" }
        return "\(d) days"
    }

    private func anyExpiringSoon(_ c: DriversAPI.MyCarrier) -> Bool {
        [c.insuranceDaysRemaining, c.hazmatDaysRemaining, c.twicDaysRemaining]
            .contains { d in
                guard let d else { return false }
                return d <= 30
            }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Previews

#Preview("Earnings · Dark") {
    MeDetailContainer(route: .earnings)
        .environment(\.palette, Theme.dark)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Settings · Light") {
    MeDetailContainer(route: .settings)
        .environment(\.palette, Theme.light)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
