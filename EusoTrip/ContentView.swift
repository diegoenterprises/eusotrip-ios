//
//  ContentView.swift
//  EusoTrip by Eusorone Technologies, Inc.
//
//  Live production root. Drives a live A→Z walk through the Driver journey
//  (screens 010–022 shipped; remainder rolls in as they land). Swaps between
//  DARK and LIGHT register in-place to preview both registers against the
//  same device bezel.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Register toggle

enum ThemeRegister: String, CaseIterable, Identifiable {
    case dark = "Night"
    case light = "Afternoon"
    var id: String { rawValue }

    var palette: Theme.Palette {
        switch self {
        case .dark:  return Theme.dark
        case .light: return Theme.light
        }
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .dark:  return .dark
        case .light: return .light
        }
    }

    /// Mirror the iOS system colorScheme into our register so the app
    /// launches in whichever mode the user's device is set to.
    init(colorScheme: ColorScheme) {
        self = (colorScheme == .light) ? .light : .dark
    }
}

// MARK: - Screen registry (A→Z walk, expands as more land)

struct ProductionScreen: Identifiable {
    let id: String           // "010", "011", …
    let title: String        // "Driver Home"
    let role: Role
    /// `@MainActor`-isolated so the closure body runs in main-actor
    /// context at invocation. Lets us safely instantiate
    /// `@MainActor`-bound types (like `PostLoadDraft`) without
    /// wrapping each constructor in `MainActor.assumeIsolated` —
    /// also resolves the Swift 6 strict-concurrency warning that
    /// fires on `(Theme.Palette) -> AnyView` because `AnyView`
    /// isn't `Sendable` (an isolated closure doesn't cross actor
    /// boundaries on return).
    let view: @MainActor (Theme.Palette) -> AnyView

    enum Role: String, CaseIterable, Identifiable {
        case driver = "Driver"
        case shipper = "Shipper"
        case carrier = "Carrier"
        case broker = "Broker"
        case catalyst = "Catalyst"
        case escort = "Escort"
        case terminal = "Terminal"
        case admin = "Admin"
        case compliance = "Compliance"
        case dispatch = "Dispatch"
        case railEngineer = "RailEngineer"
        case vesselOperator = "VesselOperator"
        var id: String { rawValue }
    }
}

enum ScreenRegistry {
    static let all: [ProductionScreen] = {
        var list: [ProductionScreen] = [
            .init(id: "010", title: "Driver Home",                role: .driver) { p in AnyView(DriverHomeScreen(theme: p)) },
            .init(id: "011", title: "Pre-trip DVIR",              role: .driver) { p in AnyView(PretripDVIRScreen(theme: p)) },
            .init(id: "012", title: "DVIR Submitted",             role: .driver) { p in AnyView(DvirSubmittedScreen(theme: p)) },
            .init(id: "013", title: "Active — Enroute",           role: .driver) { p in AnyView(ActiveEnrouteScreen(theme: p)) },
            .init(id: "014", title: "Approaching Pickup",         role: .driver) { p in AnyView(ApproachingPickupScreen(theme: p)) },
            .init(id: "015", title: "At Gate · Awaiting Dock",    role: .driver) { p in AnyView(AtGateAwaitingDockScreen(theme: p)) },
            .init(id: "016", title: "Pickup · Loading",           role: .driver) { p in AnyView(PickupLoadingScreen(theme: p)) },
            .init(id: "017", title: "Pickup · BOL Signing",       role: .driver) { p in AnyView(PickupBolSigningScreen(theme: p)) },
            .init(id: "018", title: "Active Enroute · Loaded",    role: .driver) { p in AnyView(ActiveEnrouteLoadedScreen(theme: p)) },
            .init(id: "019", title: "HOS Duty Status",            role: .driver) { p in AnyView(HosDutyStatusScreen(theme: p)) },
            .init(id: "020", title: "Approaching Delivery",       role: .driver) { p in AnyView(ApproachingDeliveryScreen(theme: p)) },
            .init(id: "021", title: "At Receiver Gate",           role: .driver) { p in AnyView(AtReceiverGateScreen(theme: p)) },
            .init(id: "022", title: "Dock Assigned",              role: .driver) { p in AnyView(DockAssignedScreen(theme: p)) },
            .init(id: "023", title: "Backing In",                 role: .driver) { p in AnyView(BackingInScreen(theme: p)) },
            .init(id: "024", title: "Unloading",                  role: .driver) { p in AnyView(UnloadingScreen(theme: p)) },
            .init(id: "025", title: "Paperwork",                  role: .driver) { p in AnyView(PaperworkScreen(theme: p)) },
            .init(id: "026", title: "Off Duty",                   role: .driver) { p in AnyView(OffDutyScreen(theme: p)) },
            .init(id: "027", title: "Next Load Brief",            role: .driver) { p in AnyView(NextLoadBriefScreen(theme: p)) },
            .init(id: "028", title: "Load Locked · Prehaul",      role: .driver) { p in AnyView(LoadLockedPrehaulScreen(theme: p)) },
            .init(id: "029", title: "Pickup Arrival",             role: .driver) { p in AnyView(PickupArrivalScreen(theme: p)) },
            .init(id: "030", title: "Loading in Progress",        role: .driver) { p in AnyView(LoadingInProgressScreen(theme: p)) },
            .init(id: "031", title: "Spectra-Match Verdict",      role: .driver) { p in AnyView(SpectraMatchVerdictScreen(theme: p)) },
            .init(id: "032", title: "Detach Sequence",            role: .driver) { p in AnyView(DetachSequenceScreen(theme: p)) },
            .init(id: "033", title: "BOL Sign-off",               role: .driver) { p in AnyView(BolSignoffScreen(theme: p)) },
            .init(id: "034", title: "Departing Pickup",           role: .driver) { p in AnyView(DepartingPickupScreen(theme: p)) },
            .init(id: "035", title: "En Route Drive",             role: .driver) { p in AnyView(EnRouteDriveScreen(theme: p)) },
            .init(id: "036", title: "ESANG Smart Stop",           role: .driver) { p in AnyView(eSangSmartStopScreen(theme: p)) },
            .init(id: "037", title: "Approaching Receiver",       role: .driver) { p in AnyView(ApproachingReceiverScreen(theme: p)) },
            .init(id: "038", title: "At Receiver Gate · Hazmat",  role: .driver) { p in AnyView(AtReceiverGateFullScreen(theme: p)) },
            .init(id: "039", title: "Backing Assist · Receiver",  role: .driver) { p in AnyView(BackingAssistReceiverScreen(theme: p)) },
            .init(id: "040", title: "Discharge in Progress",      role: .driver) { p in AnyView(DischargeInProgressScreen(theme: p)) },
            .init(id: "041", title: "Discharge Complete",         role: .driver) { p in AnyView(DischargeCompleteScreen(theme: p)) },
            .init(id: "042", title: "Disconnect and Verify",      role: .driver) { p in AnyView(DisconnectAndVerifyScreen(theme: p)) },
            .init(id: "043", title: "Disconnect Confirmed",       role: .driver) { p in AnyView(DisconnectConfirmedScreen(theme: p)) },
            .init(id: "044", title: "Connect Drop Hose",          role: .driver) { p in AnyView(ConnectDropHoseScreen(theme: p)) },
            .init(id: "045", title: "Departing Receiver",         role: .driver) { p in AnyView(DepartingReceiverScreen(theme: p)) },
            .init(id: "046", title: "Sequenced Leg Approach",     role: .driver) { p in AnyView(SequencedLegApproachScreen(theme: p)) },
            .init(id: "047", title: "Arrival Checkpoint",         role: .driver) { p in AnyView(ArrivalCheckpointScreen(theme: p)) },
            .init(id: "048", title: "Arrival-Gate Task Active",   role: .driver) { p in AnyView(ArrivalGateTaskActiveScreen(theme: p)) },
            .init(id: "049", title: "Task Result",                role: .driver) { p in AnyView(TaskResultScreen(theme: p)) },
            .init(id: "050", title: "Next Beat Live",             role: .driver) { p in AnyView(NextBeatLiveScreen(theme: p)) },
            .init(id: "051", title: "Beat Complete",              role: .driver) { p in AnyView(BeatCompleteScreen(theme: p)) },
            .init(id: "052", title: "Ratecon Tender",             role: .driver) { p in AnyView(RateconTenderScreen(theme: p)) },
            .init(id: "053", title: "ESANG Dispatch Chat",         role: .driver) { p in AnyView(eSangDispatchChatScreen(theme: p)) },
            .init(id: "054", title: "HaulPay Settlement",          role: .driver) { p in AnyView(HaulPaySettlementScreen(theme: p)) },
            .init(id: "055", title: "Day Close Wallet",            role: .driver) { p in AnyView(DayCloseWalletScreen(theme: p)) },
            .init(id: "056", title: "Driver Profile",              role: .driver) { p in AnyView(DriverProfileScreen(theme: p)) },
            .init(id: "057", title: "Driver Vehicle Card",         role: .driver) { p in AnyView(DriverVehicleCardScreen(theme: p)) },
            .init(id: "058", title: "Driver Weekly Plan",          role: .driver) { p in AnyView(DriverWeeklyPlanScreen(theme: p)) },
            .init(id: "059", title: "Driver Trips History",        role: .driver) { p in AnyView(DriverTripsHistoryScreen(theme: p)) },
            .init(id: "060", title: "The Haul · Dashboard",         role: .driver) { p in AnyView(TheHaulDashboardScreen(theme: p)) },
            .init(id: "060L", title: "The Haul · Lobby",            role: .driver) { p in AnyView(TheHaulLobbyScreen(theme: p)) },
            .init(id: "074E", title: "ELD Device · Connect",         role: .driver) { p in AnyView(ELDConnectScreen(theme: p)) },
            .init(id: "061", title: "The Haul · Missions",          role: .driver) { p in AnyView(TheHaulMissionsScreen(theme: p)) },
            .init(id: "062", title: "The Haul · Badges",            role: .driver) { p in AnyView(TheHaulBadgesScreen(theme: p)) },
            .init(id: "063", title: "The Haul · Crates",            role: .driver) { p in AnyView(TheHaulCratesScreen(theme: p)) },
            .init(id: "064", title: "The Haul · Leaderboard",       role: .driver) { p in AnyView(TheHaulLeaderboardScreen(theme: p)) },
            .init(id: "065", title: "The Haul · Streaks",           role: .driver) { p in AnyView(TheHaulStreaksScreen(theme: p)) },
            .init(id: "066", title: "The Haul · Cosmetics",         role: .driver) { p in AnyView(TheHaulCosmeticsScreen(theme: p)) },
            .init(id: "067", title: "Me · Profile",                 role: .driver) { p in AnyView(MeProfileScreen(theme: p)) },
            .init(id: "068", title: "Me · Earnings",                role: .driver) { p in AnyView(MeEarnings068(theme: p)) },
            .init(id: "069", title: "Me · Wallet",                  role: .driver) { p in AnyView(MeWalletScreen(theme: p)) },
            .init(id: "070", title: "Me · Settlements",             role: .driver) { p in AnyView(MeSettlementsScreen(theme: p)) },
            .init(id: "071", title: "Me · Tax",                     role: .driver) { p in AnyView(MeTaxScreen(theme: p)) },
            .init(id: "072", title: "Me · Docs",                    role: .driver) { p in AnyView(MeDocsScreen(theme: p)) },
            .init(id: "073", title: "Me · Vehicle",                 role: .driver) { p in AnyView(MeVehicleScreen(theme: p)) },
            .init(id: "074", title: "Me · HOS Logs",                role: .driver) { p in AnyView(MeHOSLogsScreen(theme: p)) },
            .init(id: "075", title: "Me · Safety Score",            role: .driver) { p in AnyView(MeSafetyScoreScreen(theme: p)) },
            .init(id: "076", title: "Me · Training",                role: .driver) { p in AnyView(MeTrainingScreen(theme: p)) },
            .init(id: "077", title: "Me · Payment Methods",         role: .driver) { p in AnyView(MePaymentMethodsScreen(theme: p)) },
            .init(id: "078", title: "Me · Payout Schedule",         role: .driver) { p in AnyView(MePayoutScheduleScreen(theme: p)) },
            .init(id: "079", title: "Me · Earnings Breakdown",      role: .driver) { p in AnyView(MeEarningsBreakdownScreen(theme: p)) },
            .init(id: "080", title: "Me · Tax Documents",           role: .driver) { p in AnyView(MeTaxDocumentsScreen(theme: p)) },
            .init(id: "081", title: "Me · ELD Logs Detail",         role: .driver) { p in AnyView(MeELDLogsDetailScreen(theme: p)) },
            .init(id: "082", title: "Me · Violations Manager",      role: .driver) { p in AnyView(MeViolationsManagerScreen(theme: p)) },
            .init(id: "083", title: "Me · Documents Hub",           role: .driver) { p in AnyView(MeDocumentsHubScreen(theme: p)) },
            .init(id: "084", title: "Me · DataQs Filer",            role: .driver) { p in AnyView(MeDataQsFilerScreen(theme: p)) },
            .init(id: "085", title: "Me · Carrier Scorecard",       role: .driver) { p in AnyView(MeCarrierScorecardScreen(theme: p)) },
            .init(id: "086", title: "Me · Incident Filer",          role: .driver) { p in AnyView(MeIncidentReportFilerScreen(theme: p)) },
            .init(id: "087", title: "Me · Safety Coach",            role: .driver) { p in AnyView(MeSafetyCoachScreen(theme: p)) },
            .init(id: "088", title: "Me · Invite & Earn",           role: .driver) { p in AnyView(MeReferralsScreen(theme: p)) },
            .init(id: "089", title: "Me · Support",                 role: .driver) { p in AnyView(MeSupportScreen(theme: p)) },
            .init(id: "090", title: "Me · IFTA Tax",                role: .driver) { p in AnyView(MeIftaScreen(theme: p)) },
            .init(id: "091", title: "Me · Detention",               role: .driver) { p in AnyView(MeDetentionScreen(theme: p)) },
            .init(id: "092", title: "Me · Permits",                 role: .driver) { p in AnyView(MePermitsScreen(theme: p)) },
            .init(id: "093", title: "Me · DQ File",                 role: .driver) { p in AnyView(MeDQFileScreen(theme: p)) },
            .init(id: "094", title: "Me · Fuel Cards",              role: .driver) { p in AnyView(MeFuelCardsScreen(theme: p)) },
            .init(id: "095", title: "Me · Rate Intel",              role: .driver) { p in AnyView(MeRateIntelScreen(theme: p)) },
            .init(id: "096", title: "Me · ERG",                     role: .driver) { p in AnyView(MeErgScreen(theme: p)) },
            .init(id: "097", title: "Me · Ratings",                 role: .driver) { p in AnyView(MeRatingsScreen(theme: p)) },
            .init(id: "098", title: "Me · Emergency Ops",           role: .driver) { p in AnyView(MeEmergencyOpsScreen(theme: p)) },
            .init(id: "099", title: "Me · Freight Claims",          role: .driver) { p in AnyView(MeFreightClaimsScreen(theme: p)) },
            .init(id: "100", title: "Me · Hot Zones",               role: .driver) { p in AnyView(MeHotZonesScreen(theme: p)) },
            .init(id: "101", title: "Me · Appointments",            role: .driver) { p in AnyView(MeAppointmentsScreen(theme: p)) },
            .init(id: "102", title: "Me · Contacts",                role: .driver) { p in AnyView(MeContactsScreen(theme: p)) },
            .init(id: "103", title: "Me · Agreements",              role: .driver) { p in AnyView(MeAgreementsScreen(theme: p)) },
            .init(id: "104", title: "Me · Rate Sheets",             role: .driver) { p in AnyView(MeRateSheetScreen(theme: p)) },
            .init(id: "105", title: "Me · Authority",               role: .driver) { p in AnyView(MeAuthorityScreen(theme: p)) },
            .init(id: "106", title: "Me · EusoTicket",              role: .driver) { p in AnyView(MeEusoTicketsScreen(theme: p)) },
            .init(id: "107", title: "Me · My Bids",                 role: .driver) { p in AnyView(MeMyBidsScreen(theme: p)) },
            .init(id: "108", title: "Me · LoadBoard",               role: .driver) { p in AnyView(MeLoadBoardScreen(theme: p)) },
            // 2026-05-21 — Driver lifecycle entry trio (SVG 091/092/093).
            // Numbering uses "DL09x" to avoid the 091-108 Me-section
            // collision; iOS already uses 091_MeDetention etc.
            .init(id: "DL091", title: "Driver · Load Offer Detail",  role: .driver) { p in AnyView(DriverLoadOfferDetailScreen(theme: p, loadId: "0")) },
            .init(id: "DL092", title: "Driver · Assignment Receipt", role: .driver) { p in AnyView(DriverAssignmentReceiptScreen(theme: p, loadId: "0")) },
            .init(id: "DL093", title: "Driver · Pickup Approach",    role: .driver) { p in AnyView(DriverPickupApproachScreen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver lifecycle septet (SVG 094-100).
            .init(id: "DL094", title: "Driver · At Gate",            role: .driver) { p in AnyView(DriverAtGateScreen(theme: p, loadId: "0")) },
            .init(id: "DL095", title: "Driver · At Dock",            role: .driver) { p in AnyView(DriverAtDockScreen(theme: p, loadId: "0")) },
            .init(id: "DL096", title: "Driver · Departing",          role: .driver) { p in AnyView(DriverDepartingScreen(theme: p, loadId: "0")) },
            .init(id: "DL097", title: "Driver · Pre-Delivery",       role: .driver) { p in AnyView(DriverPreDeliveryScreen(theme: p, loadId: "0")) },
            .init(id: "DL098", title: "Driver · At Delivery",        role: .driver) { p in AnyView(DriverAtDeliveryScreen(theme: p, loadId: "0")) },
            .init(id: "DL099", title: "Driver · POD Sign",           role: .driver) { p in AnyView(DriverPODSignScreen(theme: p, loadId: "0")) },
            .init(id: "DL100", title: "Driver · Load Closed",        role: .driver) { p in AnyView(DriverLoadClosedScreen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver backhaul + DVIR octet (SVG 101-108).
            .init(id: "DL101", title: "Driver · Backhaul Offer",      role: .driver) { p in AnyView(DriverBackhaulOfferScreen(theme: p, loadId: "0")) },
            .init(id: "DL102", title: "Driver · Backhaul Accepted",   role: .driver) { p in AnyView(DriverBackhaulAcceptedScreen(theme: p, loadId: "0")) },
            .init(id: "DL103", title: "Driver · DVIR Started",        role: .driver) { p in AnyView(DriverDVIRStartedScreen(theme: p, loadId: "0")) },
            .init(id: "DL104", title: "Driver · DVIR Section 3",      role: .driver) { p in AnyView(DriverDVIRSection3Screen(theme: p, loadId: "0")) },
            .init(id: "DL105", title: "Driver · DVIR Section 4",      role: .driver) { p in AnyView(DriverDVIRSection4Screen(theme: p, loadId: "0")) },
            .init(id: "DL106", title: "Driver · DVIR Section 5",      role: .driver) { p in AnyView(DriverDVIRSection5Screen(theme: p, loadId: "0")) },
            .init(id: "DL107", title: "Driver · DVIR Section 6",      role: .driver) { p in AnyView(DriverDVIRSection6Screen(theme: p, loadId: "0")) },
            .init(id: "DL108", title: "Driver · DVIR Section 7",      role: .driver) { p in AnyView(DriverDVIRSection7Screen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver DVIR continuation quintet (SVG 109-113).
            .init(id: "DL109", title: "Driver · DVIR Section 8",      role: .driver) { p in AnyView(DriverDVIRSection8Screen(theme: p, loadId: "0")) },
            .init(id: "DL110", title: "Driver · DVIR Section 9",      role: .driver) { p in AnyView(DriverDVIRSection9Screen(theme: p, loadId: "0")) },
            .init(id: "DL111", title: "Driver · DVIR Section 10",     role: .driver) { p in AnyView(DriverDVIRSection10Screen(theme: p, loadId: "0")) },
            .init(id: "DL112", title: "Driver · DVIR Section 11",     role: .driver) { p in AnyView(DriverDVIRSection11Screen(theme: p, loadId: "0")) },
            .init(id: "DL113", title: "Driver · DVIR Section 12",     role: .driver) { p in AnyView(DriverDVIRSection12Screen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver backhaul-pickup sextet (SVG 114-119).
            .init(id: "DL114", title: "Driver · DVIR Complete",       role: .driver) { p in AnyView(DriverDVIRCompleteScreen(theme: p, loadId: "0")) },
            .init(id: "DL115", title: "Driver · Loaded Departed",     role: .driver) { p in AnyView(DriverLoadedDepartedScreen(theme: p, loadId: "0")) },
            .init(id: "DL116", title: "Driver · Approaching Dest",    role: .driver) { p in AnyView(DriverApproachingDestinationScreen(theme: p, loadId: "0")) },
            .init(id: "DL117", title: "Driver · At Delivery BH",      role: .driver) { p in AnyView(DriverAtDeliveryBHScreen(theme: p, loadId: "0")) },
            .init(id: "DL118", title: "Driver · Docked Loading",      role: .driver) { p in AnyView(DriverDockedLoadingScreen(theme: p, loadId: "0")) },
            .init(id: "DL119", title: "Driver · Loading In Progress", role: .driver) { p in AnyView(DriverLoadingInProgressScreen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver backhaul-close sextet (SVG 120-125).
            .init(id: "DL120", title: "Driver · Loading Tick 2",       role: .driver) { p in AnyView(DriverLoadingTick2Screen(theme: p, loadId: "0")) },
            .init(id: "DL121", title: "Driver · Loading Tick 3",       role: .driver) { p in AnyView(DriverLoadingTick3Screen(theme: p, loadId: "0")) },
            .init(id: "DL122", title: "Driver · BOL Pre-Sign",         role: .driver) { p in AnyView(DriverBOLPreSignScreen(theme: p, loadId: "0")) },
            .init(id: "DL123", title: "Driver · BOL Signed",           role: .driver) { p in AnyView(DriverBOLSignedScreen(theme: p, loadId: "0")) },
            .init(id: "DL124", title: "Driver · BH Paperwork",         role: .driver) { p in AnyView(DriverBHPaperworkScreen(theme: p, loadId: "0")) },
            .init(id: "DL125", title: "Driver · BH Closed",            role: .driver) { p in AnyView(DriverBHClosedScreen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver CEL M-04 septet (SVG 126-132).
            .init(id: "DL126", title: "Driver · CEL Assigned",         role: .driver) { p in AnyView(DriverCELM04AssignedScreen(theme: p, loadId: "0")) },
            .init(id: "DL127", title: "Driver · CEL DVIR S1",          role: .driver) { p in AnyView(DriverCELM04S1Screen(theme: p, loadId: "0")) },
            .init(id: "DL128", title: "Driver · CEL DVIR S2",          role: .driver) { p in AnyView(DriverCELM04S2Screen(theme: p, loadId: "0")) },
            .init(id: "DL129", title: "Driver · CEL DVIR S3",          role: .driver) { p in AnyView(DriverCELM04S3Screen(theme: p, loadId: "0")) },
            .init(id: "DL130", title: "Driver · CEL DVIR S4",          role: .driver) { p in AnyView(DriverCELM04S4Screen(theme: p, loadId: "0")) },
            .init(id: "DL131", title: "Driver · CEL DVIR S5",          role: .driver) { p in AnyView(DriverCELM04S5Screen(theme: p, loadId: "0")) },
            .init(id: "DL132", title: "Driver · CEL DVIR S6",          role: .driver) { p in AnyView(DriverCELM04S6Screen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver CEL M-04 DVIR continuation (SVG 133-140).
            .init(id: "DL133", title: "Driver · CEL DVIR S7",          role: .driver) { p in AnyView(DriverCELM04S7Screen(theme: p, loadId: "0")) },
            .init(id: "DL134", title: "Driver · CEL DVIR S8",          role: .driver) { p in AnyView(DriverCELM04S8Screen(theme: p, loadId: "0")) },
            .init(id: "DL135", title: "Driver · CEL DVIR S9",          role: .driver) { p in AnyView(DriverCELM04S9Screen(theme: p, loadId: "0")) },
            .init(id: "DL136", title: "Driver · CEL DVIR S10",         role: .driver) { p in AnyView(DriverCELM04S10Screen(theme: p, loadId: "0")) },
            .init(id: "DL137", title: "Driver · CEL DVIR S11",         role: .driver) { p in AnyView(DriverCELM04S11Screen(theme: p, loadId: "0")) },
            .init(id: "DL138", title: "Driver · CEL DVIR S12",         role: .driver) { p in AnyView(DriverCELM04S12Screen(theme: p, loadId: "0")) },
            .init(id: "DL139", title: "Driver · CEL DVIR S13",         role: .driver) { p in AnyView(DriverCELM04S13Screen(theme: p, loadId: "0")) },
            .init(id: "DL140", title: "Driver · CEL DVIR Submit",      role: .driver) { p in AnyView(DriverCELM04S14SubmitScreen(theme: p, loadId: "0")) },
            // 2026-05-21 — Driver CEL M-04 close octet (SVG 141-148).
            .init(id: "DL141", title: "Driver · CEL On-Site",          role: .driver) { p in AnyView(DriverCELM04OnSiteScreen(theme: p, loadId: "0")) },
            .init(id: "DL142", title: "Driver · CEL At-Dock",          role: .driver) { p in AnyView(DriverCELM04AtDockScreen(theme: p, loadId: "0")) },
            .init(id: "DL143", title: "Driver · CEL Loading",          role: .driver) { p in AnyView(DriverCELM04LoadingScreen(theme: p, loadId: "0")) },
            .init(id: "DL144", title: "Driver · CEL BOL Sign",         role: .driver) { p in AnyView(DriverCELM04BOLSignScreen(theme: p, loadId: "0")) },
            .init(id: "DL145", title: "Driver · CEL Departed",         role: .driver) { p in AnyView(DriverCELM04DepartedScreen(theme: p, loadId: "0")) },
            .init(id: "DL146", title: "Driver · CEL In Transit",       role: .driver) { p in AnyView(DriverCELM04InTransitScreen(theme: p, loadId: "0")) },
            .init(id: "DL147", title: "Driver · CEL At Delivery",      role: .driver) { p in AnyView(DriverCELM04AtDeliveryScreen(theme: p, loadId: "0")) },
            .init(id: "DL148", title: "Driver · CEL POD Signed",       role: .driver) { p in AnyView(DriverCELM04PODSignedScreen(theme: p, loadId: "0")) },
            .init(id: "149",   title: "Driver · CEL Closed Paid Receipt", role: .driver) { p in AnyView(DriverCELM04PaidReceiptScreen(theme: p, loadId: "0")) },
            .init(id: "109", title: "Me · Bid Detail",              role: .driver) { p in AnyView(MeBidDetailScreen(theme: p, loadId: 0)) },
            .init(id: "110", title: "Me · Auto-Accept",             role: .driver) { p in AnyView(MeAutoAcceptRulesScreen(theme: p)) },
            // 2026-05-21 — Bonus Tracker port (web BonusTracker.tsx → iOS).
            .init(id: "111", title: "Me · Bonus Tracker",           role: .driver) { p in AnyView(DriverBonusTrackerScreen(theme: p)) },
            // Driver Me hub — parent + 7 children mirroring the
            // Shipper 320/320a-g design. Founder feedback 2026-05-04:
            // wanted the same parent-child IA on driver. The catalog
            // (`DriverMeHubCatalog`) drills into existing leaf
            // screens 060-110 with no dead taps.
            .init(id: "067hub", title: "Driver · Me Home",          role: .driver) { p in AnyView(DriverMeHomeScreen(theme: p)) },
            .init(id: "067a",   title: "Driver · Me · Account",     role: .driver) { p in AnyView(DriverMeAccountHubScreen(theme: p)) },
            .init(id: "067b",   title: "Driver · Me · Wallet",      role: .driver) { p in AnyView(DriverMeWalletHubScreen(theme: p)) },
            .init(id: "067c",   title: "Driver · Me · Compliance",  role: .driver) { p in AnyView(DriverMeComplianceHubScreen(theme: p)) },
            .init(id: "067d",   title: "Driver · Me · Vehicle",     role: .driver) { p in AnyView(DriverMeVehicleHubScreen(theme: p)) },
            .init(id: "067e",   title: "Driver · Me · Operations",  role: .driver) { p in AnyView(DriverMeOperationsHubScreen(theme: p)) },
            .init(id: "067f",   title: "Driver · Me · The Haul",    role: .driver) { p in AnyView(DriverMeHaulHubScreen(theme: p)) },
            .init(id: "067g",   title: "Driver · Me · Settings",    role: .driver) { p in AnyView(DriverMeSettingsHubScreen(theme: p)) },
            // EusoTrip Pulse (Apple Watch pairing) — registered for
            // BOTH roles so Driver and Shipper Me Settings hubs both
            // drill into the same canonical surface.
            .init(id: "PULSE",  title: "EusoTrip Pulse",             role: .driver)  { p in AnyView(PulseSettingsScreen(theme: p)) },
            .init(id: "PULSE",  title: "EusoTrip Pulse",             role: .shipper) { p in AnyView(PulseSettingsScreen(theme: p)) },
        ]

        // MARK: Non-driver role placeholders (DEBUG only)
        //
        // Appended behind #if DEBUG so the dev-chrome role tabs activate
        // only in dev builds. In Release (TestFlight / App Store) these
        // entries are not compiled and the registry contains only the
        // shipped driver screens 010–027. Each placeholder renders a
        // gradient orb + role label + numeric id + "Figma port pending"
        // line so it is obvious these are scaffolding, not real screens.
        //
        // Using an immediately-invoked closure + append (rather than
        // `#if DEBUG` directly inside the array literal) because Swift
        // can't parse `#if` around `.init(...) { p in ... }` trailing-
        // closure entries cleanly — the parser treats the block as an
        // expression-form `#if` and fails with "expected expression".
        // 2026-04-24 — eusotrip-killers next-port firing:
        // First real Shipper-track brick lands in production. Lifts
        // id "200" out of the `#if DEBUG` placeholder block below
        // so non-debug builds also get the Shipper Home surface.
        // Backed by `shippers.{getDashboardStats,getActiveLoads,
        // getLoadsRequiringAttention,getRecentLoads}` — see
        // `200_ShipperHome.swift` header for the full doctrine and
        // store wire-up.
        list.append(
            .init(id: "200", title: "Shipper · Home", role: .shipper) { p in
                AnyView(ShipperHomeScreen(theme: p))
            }
        )
        // 2026-04-25 — eusotrip-killers continuation firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Second real Shipper-track brick lands in production. The
        // `Loads` slot in the 200 BottomNav routes here. Backed by
        // `shippers.getActiveLoads` + `shippers.getRecentLoads` via the
        // existing ShipperActiveLoadsStore / ShipperRecentLoadsStore in
        // LiveDataStores.swift — no new backend, no new API surface,
        // 100% live data. Filter chip strip (All · Active · Recent) +
        // in-memory search across loadNumber/origin/destination.
        // Per-row tap presents the brick-202 placeholder sheet
        // (EusoEmptyState `comingSoon: true`) until shipper load
        // detail lands. Doctrine: every Toggle-equivalent surface
        // uses gradient accent (no flat Brand.info / Brand.blue),
        // ternary shape-styles wrapped in AnyShapeStyle, both
        // register previews compile in isolation.
        list.append(
            .init(id: "201", title: "Shipper · Loads", role: .shipper) { p in
                AnyView(ShipperLoadsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 117th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Third real Shipper-track brick lands in production. Routes
        // from the `Me` slot of the 200/201 BottomNav. Backed by
        // `shippers.getProfile` + `shippers.getStats` via the new
        // `ShipperProfileStore` / `ShipperStatsStore` in
        // LiveDataStores.swift — no fixtures, no fallback values,
        // 100% live data per Cohort B day-1 doctrine. Identity card
        // (DOT/MC/verified), contact card (email/phone/address/web),
        // 4-tile lifetime-stats KPI grid, 12-month gradient mini-bar
        // chart, and Edit-profile + Sign-out CTAs. Every blank field
        // surfaces as an em-dash sentinel ("—") rather than a
        // fabricated brand or metric. Doctrine: gradient-only accent
        // (no flat Brand.info / Brand.blue), AnyShapeStyle wrapping
        // for ternary shape-styles, both register previews compile
        // in isolation.
        list.append(
            .init(id: "202", title: "Shipper · Profile", role: .shipper) { p in
                AnyView(ShipperProfileScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 119th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Fourth Shipper-track brick lands in production. Bids inbox
        // for posted loads — load picker chip strip drives a single
        // tRPC call to `shippers.getBidsForLoad(loadId)`, with single
        // tap Accept (`shippers.acceptBid`) and Reject
        // (`shippers.rejectBid`) mutations live on the detail sheet.
        // Cohort B day-1 — no fixtures, no fallbacks, no fabricated
        // data. Server-side empty fields surface as em-dash sentinels
        // ("—"). Backed by `ShipperActiveLoadsStore` (existing) +
        // `ShipperBidsStore` (new, LiveDataStores.swift L3313).
        list.append(
            .init(id: "203", title: "Shipper · Bids", role: .shipper) { p in
                AnyView(ShipperBidsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 121st firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Fifth Shipper-track brick lands in production. Dedicated
        // post-load form behind the 201 "Post a load" CTA. Captures
        // origin / destination / cargo-type / pickup date / weight /
        // rate / notes and posts a fresh row to the loads table via a
        // single `shippers.create` mutation
        // (frontend/server/routers/shippers.ts:18). Backed by the new
        // `ShipperPostLoadStore` (LiveDataStores.swift, mutation phase
        // machine: idle → submitting → success | error). Cohort B
        // day-1 — the form starts blank, no seeded text, no fake
        // defaults beyond the backend's "general" cargoType Zod
        // default. Empty optional fields wire-omit so the backend's
        // `.optional()` defaults apply. Server-emitted `loadNumber`
        // surfaces verbatim in the success banner — no client-side
        // reformatting. Submit button gates on origin / destination
        // non-empty AND not in-flight, so the user can never fire a
        // known-invalid mutation. After success the form clears and
        // the user can post another without remounting.
        list.append(
            .init(id: "204", title: "Shipper · Post Load", role: .shipper) { p in
                AnyView(ShipperPostLoadScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 122nd firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Sixth Shipper-track brick. The 121st firing's Branch B
        // recommendation: 201_ShipperLoads now opens this surface in
        // a sheet on row tap (replacing the `EusoEmptyState
        // (comingSoon:)` placeholder). Detail data flows through
        // `ShipperLoadDetailStore` → `loads.getById`
        // (`frontend/server/routers/loads.ts:1046`); bid count +
        // highest amount reuse the existing `ShipperBidsStore` →
        // `shippers.getBidsForLoad`. Cohort B day-1: every field
        // surfaces verbatim from the server, missing optionals
        // render as em-dash sentinels — never fabricated values.
        // The dev-chrome registry entry uses loadId="0" purely as
        // a placeholder so the next/prev walk doesn't break; the
        // real navigation path is the sheet from 201.
        list.append(
            .init(id: "205", title: "Shipper · Load Detail", role: .shipper) { p in
                AnyView(ShipperLoadDetailScreen(
                    theme: p,
                    loadId: "0",
                    previewLoadNumber: nil,
                    previewLane: nil
                ))
            }
        )
        // 2026-04-26 — eusotrip-killers 124th firing
        // (autonomous scheduled-task `eusotrip-killers`):
        // Seventh real Shipper-track brick lands in production. Per
        // the 123rd firing's recommendation for Branch B: "Code port
        // 206_ShipperSettlements driving shippers.getDeliveryConfirma
        // tions + a settlements summary card." Backed by
        // `shippers.getDeliveryConfirmations` via the new
        // `ShipperDeliveryConfirmationsStore` — see
        // `206_ShipperSettlements.swift` header for the full doctrine
        // and store wire-up. Aggregates (total billed, settled count,
        // average rate, last settlement date) computed client-side
        // from the same verified server array so the screen can never
        // drift between an aggregate and its row list. Tap a row →
        // opens 205_ShipperLoadDetail in a sheet, passing the same
        // `loadId` so the detail surface re-uses the existing
        // `ShipperLoadDetailStore` path.
        list.append(
            .init(id: "206", title: "Shipper · Settlements", role: .shipper) { p in
                AnyView(ShipperSettlementsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 126th firing
        // (autonomous scheduled-task `eusotrip-killers`):
        // Eighth real Shipper-track brick lands in production. Per
        // the 124th firing's hand-off recommendation: "207
        // ShipperReports" — a spend analytics + catalyst performance
        // dashboard backed by two parallel real backend procedures
        // (`shippers.getSpendingAnalytics` returning a single
        // envelope, `shippers.getCatalystPerformance` returning a
        // ranked list). MCP-verified at firing open at
        // `frontend/server/routers/shippers.ts:470` and `:433`.
        // Period selector (Month / Quarter / Year) propagates to
        // BOTH stores so the KPI tiles and the catalyst leaderboard
        // always describe the same time window. Cohort B day-1 — no
        // fixtures, no fake data, no mock fallbacks. Empty windows
        // surface `EusoEmptyState` (zero-spend or zero-catalysts)
        // rather than a confusing "$0 over 0 loads" tile strip.
        list.append(
            .init(id: "207", title: "Shipper · Reports", role: .shipper) { p in
                AnyView(ShipperReportsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 127th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Cohort B day-1 brick — Shipper Payment Methods. Reuses the
        // existing `PaymentMethodsStore` (defined for Driver Me 077)
        // because `payments.getPaymentMethods` is `protectedProcedure`
        // and serves any authenticated user identically — same Stripe
        // Customer lookup, same `card` + `us_bank_account` mix, same
        // `isDefault` stamp. Cross-role store reuse is the doctrine-
        // approved pattern when the backend procedure is role-agnostic
        // (no shipperProcedure or roleProcedure gate). The shipper
        // copy reframes "payouts default" → "funding default" because
        // shippers PAY for loads (the default method funds checkout
        // via `payments.createLoadCheckout` / per-load PaymentIntent)
        // whereas drivers RECEIVE payouts. Backend MCP-verified at
        // firing open: `frontend/server/routers/payments.ts:323`
        // (`getPaymentMethods`), :366 (`setDefaultMethod`), :381
        // (`deletePaymentMethod`). Doctrine: 0 Brand.info|blue real
        // hits (only doctrine-banner comment refs), 0 Toggle widgets
        // (no GradientToggleStyle obligation), AnyShapeStyle wraps
        // on isDefault icon-tint ternary, LinearGradient.diagonal on
        // header, default-banner glyph, default chip, retry CTA, add
        // CTA, toast checkmark.
        list.append(
            .init(id: "208", title: "Shipper · Payment Methods", role: .shipper) { p in
                AnyView(ShipperPaymentMethodsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 127th firing (continued)
        // Cohort B day-1 brick — Shipper Contacts (working-carriers
        // directory). Backed by the new `shippers.getFavoriteCatalysts`
        // tRPC procedure (frontend/server/routers/shippers.ts:500),
        // which is a DERIVED view: no junction table, the server
        // aggregates `loads` rows where `shipperId = ctx.user.id AND
        // status = 'delivered' AND catalystId IS NOT NULL`, groups by
        // catalystId, joins through `companies` for name + dotNumber,
        // and orders DESC by load count, top 10. The "Contacts" framing
        // is doctrine: the most-worked-with carriers ARE the shipper's
        // de-facto contact list — there's no separate "favorited"
        // boolean. Favorite-tap is a no-op acknowledgment server-side
        // (returns {success, catalystId, addedAt}); the UI fires it
        // for future-proofing but doesn't refresh the list. New API
        // surface added: ShipperAPI.FavoriteCatalyst struct +
        // getFavoriteCatalysts() + addFavoriteCatalyst(catalystId:).
        // New store: ShipperFavoriteCatalystsStore in LiveDataStores
        // with row-level acknowledgingId for the optimistic ack-tap
        // spinner. Doctrine: 0 Brand.info|blue real hits (only
        // doctrine-banner comment refs), 0 Toggle widgets (no
        // GradientToggleStyle obligation), AnyShapeStyle wraps on
        // top-3 rank-badge gradient ternary, LinearGradient.diagonal
        // on header, summary-tile glyphs, top-3 rank badges, retry
        // CTA, toast checkmark.
        list.append(
            .init(id: "209", title: "Shipper · Contacts", role: .shipper) { p in
                AnyView(ShipperContactsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 128th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Eleventh shipper-track brick `210_ShipperAnalyticsDeepDive`.
        // Cohort B day-1 — fully dynamic, zero new API/store code.
        // Reuses `ShipperSpendingAnalyticsStore` AND
        // `ShipperCatalystPerformanceStore` (both already shipped in
        // 126th firing for brick 207_ShipperReports). Same backend
        // procedures (`shippers.getSpendingAnalytics:470` +
        // `shippers.getCatalystPerformance:433`), different lens:
        // efficiency tiles + share-of-spend horizontal bars + on-time-
        // rate distribution buckets + programmatically-derived
        // insights callouts (top-3 spend share, avg on-time, vs-market
        // variance). Lane and equipment-type cohort breakdowns render
        // `EusoEmptyState(comingSoon: true)` per the codebase doctrine
        // §13 no-fake-data rule — backend's `byLane`/`byCatalyst`
        // arrays are reserved future fields. The screen owns the
        // canonical SpendingPeriod and propagates to BOTH stores via
        // setPeriod so every lens describes the same window. Doctrine
        // compliance: 0 Brand.info|blue real hits (only doctrine-
        // banner comment refs), 0 Toggle widgets (no GradientToggleStyle
        // obligation), AnyShapeStyle wraps on rank-badge ternary,
        // LinearGradient.diagonal on header glyph, period chip when
        // selected, share-bar fills, on-time bucket bar fills, retry
        // CTA, marketVariance glyph, sparkle insight glyphs.
        list.append(
            .init(id: "210", title: "Shipper · Analytics Deep-Dive", role: .shipper) { p in
                AnyView(ShipperAnalyticsDeepDiveScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 129th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // TWELFTH (final) shipper-track brick lands in production —
        // closes the Shipper anchor sweep at 12-of-12 and brings the
        // 121-spec total to 121 (Driver 96 + Shipper 12 + Carrier 2 +
        // Auth 6 + 5 other-role anchors). Backed by the canonical
        // cross-role notification preferences matrix:
        //   • `users.getNotificationPreferences` — query, returns the
        //     11-boolean matrix (4 channel masters + 7 alert categories).
        //     MCP-verified at `frontend/server/routers/users.ts:1648`.
        //   • `users.updateNotificationPreferences` — mutation, partial
        //     update, returns `{success: true}`. MCP-verified at
        //     `frontend/server/routers/users.ts:1680`.
        //   Both `protectedProcedure` (any authenticated user) so
        //   shippers consume the same envelope shape that Driver Me
        //   eventually migrates to. Account-section rows fall through
        //   to existing shipper bricks (202 Profile, 201 Loads, 208
        //   Payment Methods, 209 Contacts) via the standard
        //   `pushScreenById` env closure. Sign-out wires through
        //   `EusoTripSession.signOut()` → `auth.logout` → AppRoot
        //   `.signedOut`. Default lane configs section renders
        //   `EusoEmptyState(comingSoon:)` per §13 no-fake-data rule
        //   until backend exposes a `shippers.getDefaultLaneConfigs`
        //   procedure. New API surface: `UsersAPI` struct +
        //   `EusoTripAPI.shared.users` accessor (first cross-role
        //   user-scoped endpoint group; `auth.*`, `notifications.*`,
        //   and `preferences.*` are sibling but distinct namespaces).
        //   New store: `NotificationPreferencesStore` (BaseDynamicStore
        //   over the 11-boolean matrix with per-key inflight set for
        //   per-row optimistic-flip discipline). pbxproj 4-section
        //   wiring uses new SK01/SK02 hash suffix consistent with the
        //   prior shipper-block pattern (SH/SL/SP/SB/SC/SD/SE/SF/SG/SI/SJ).
        list.append(
            .init(id: "211", title: "Shipper · Settings", role: .shipper) { p in
                AnyView(ShipperSettingsScreen(theme: p))
            }
        )
        // 2026-04-27 — eusotrip-killers 159th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // 212 Shipper · Control Tower wire-up. The Mac-side dev
        // workstream had landed `212_ShipperControlTower.swift` in the
        // disk + pbxproj after the 158th hygiene close but had not
        // wired the ScreenRegistry entry — the file was reachable by
        // the Swift compiler but unreachable from the dev-chrome
        // next/prev bar (a +1 bijection drift the 158th counter would
        // have caught had the file landed before the audit).
        // Closing that drift now so the bijection holds: registry
        // numbered + auth = disk numbered (130 + 6 = 136 with this
        // brick + the 602 wire-up earlier in this firing). Reads
        // from the live `ControlTowerStore` defined in the screen
        // file. No fixture data ever (doctrine §11 + `MockDataGuard`).
        list.append(
            .init(id: "212", title: "Shipper · Control Tower", role: .shipper) { p in
                AnyView(
                    ShipperControlTower()
                        .environment(\.palette, p)
                )
            }
        )
        // 2026-04-27/28 — eusotrip-killers 160th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // 5-file Shipper orphan drift close. Mac-side dev workstream
        // landed five new shipper bricks on disk + pbxproj between
        // 23:27 and 00:04 (after the 159th close at 23:25):
        //   213_ShipperCatalystScorecard.swift  (689 lines, 23:27)
        //   214_ShipperSustainability.swift     (610 lines, 23:35)
        //   215_ShipperRFP.swift                (1046 lines, 23:44)
        //   216_ShipperCompliance.swift         (663 lines, 23:53)
        //   217_ShipperContracts.swift          (749 lines, 00:04)
        // The five view types compile but are unreachable from the
        // dev-chrome next/prev bar (a +5 bijection drift). Each view
        // uses the same self-driving pattern as 212 (no theme init,
        // `@Environment(\.palette)` reader, `@StateObject` store
        // driven by `.task { await store.refresh() }`), so each
        // registry entry pipes the palette via `.environment(\.palette, p)`.
        // Bijection now holds: 130 (pre) + 5 (these) + 1 (803 next) = 136
        // numbered registry IDs, and 6 Auth files routed via AppRoot
        // remain off-registry. No fixture data — every store is
        // backed by a real `EusoTripAPI` namespace and folds nil/empty
        // payloads to `EusoEmptyState` (doctrine §11 + `MockDataGuard`).
        list.append(
            .init(id: "213", title: "Shipper · Catalyst Scorecard", role: .shipper) { p in
                AnyView(
                    ShipperCatalystScorecard()
                        .environment(\.palette, p)
                )
            }
        )
        list.append(
            .init(id: "214", title: "Shipper · Sustainability", role: .shipper) { p in
                AnyView(
                    ShipperSustainability()
                        .environment(\.palette, p)
                )
            }
        )
        list.append(
            .init(id: "215", title: "Shipper · RFP & Bids", role: .shipper) { p in
                AnyView(
                    ShipperRFP()
                        .environment(\.palette, p)
                )
            }
        )
        list.append(
            .init(id: "216", title: "Shipper · Compliance", role: .shipper) { p in
                AnyView(
                    ShipperCompliance()
                        .environment(\.palette, p)
                )
            }
        )
        list.append(
            .init(id: "217", title: "Shipper · Contracts", role: .shipper) { p in
                AnyView(
                    ShipperContracts()
                        .environment(\.palette, p)
                )
            }
        )
        // 2026-04-28 — eusotrip-killers 161st firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Mid-firing parallel-drift close. Mac-side dev workstream
        // landed `218_ShipperDispatchControl.swift` (696 lines) on
        // disk + pbxproj (4 sections — D2180000000000000021CG/CF) at
        // 00:12 — during this firing's 803 brick-port window. The
        // file lands the same self-driving pattern as 212-217
        // (`@Environment(\.palette)`, `@StateObject`-driven store),
        // so wire it the same way before the bijection drifts back
        // to +1. 137 production registry IDs after this entry; the
        // 803 brick takes us to 138 numbered registry IDs total
        // (138 + 6 Auth = 144 — but disk count after the 218 land
        // is 144, so bijection holds through this firing's close).
        list.append(
            .init(id: "218", title: "Shipper · Dispatch Control", role: .shipper) { p in
                AnyView(
                    ShipperDispatchControl()
                        .environment(\.palette, p)
                )
            }
        )
        // 2026-05-01 — Shipper Phase 3.1 (sweep 219-269): register
        // every in-build Shipper screen so the Shipper surface in
        // `RoleSurfaceRouter` can navigate to all of them. Files
        // 219-230 (Freight Claims / Rate Board / Recurring Loads /
        // Live Tracking / Agreements / Partner Directory / Hot Zones /
        // Document Center / Settlement Detail / BOLs / Allocations /
        // Bid Thread) are bare `Shipper___()` Views without a Screen
        // wrapper struct. Each is wrapped in the canonical Shell +
        // BottomNav via `wrapShipperScreen(palette:currentSlot:)` so
        // the bottom-nav matches the rest of the role and slot taps
        // route through `shipperNavHandler`. The `currentSlot` arg
        // tells the chrome which slot pill to highlight — Loads-ring
        // surfaces (Live Tracking, Rate Board, Recurring) light Loads;
        // compliance / partner / settings / docs surfaces light Me;
        // detail surfaces (227, 230) leave nothing current ("off-ring").
        list.append(.init(id: "219", title: "Shipper · Freight Claims",  role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperFreightClaims() }) })
        list.append(.init(id: "220", title: "Shipper · Rate Board",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperRateBoard() }) })
        list.append(.init(id: "221", title: "Shipper · Recurring Loads", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperRecurringLoads() }) })
        list.append(.init(id: "222", title: "Shipper · Live Tracking",   role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperLiveTracking() }) })
        list.append(.init(id: "223", title: "Shipper · Agreements",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me)    { ShipperAgreements() }) })
        list.append(.init(id: "224", title: "Shipper · Partner Directory", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperPartnerDirectory() }) })
        list.append(.init(id: "225", title: "Shipper · Hot Zones",       role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperHotZones() }) })
        list.append(.init(id: "226", title: "Shipper · Document Center", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperDocumentCenter() }) })
        list.append(.init(id: "227", title: "Shipper · Settlement Detail", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperSettlementDetail() }) })
        list.append(.init(id: "228", title: "Shipper · BOLs",            role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperBOLs() }) })
        list.append(.init(id: "229", title: "Shipper · Allocations",     role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperAllocations() }) })
        list.append(.init(id: "233", title: "Shipper · Market Intelligence", role: .shipper) { p in AnyView(MarketIntelligenceScreen(theme: p)) })
        list.append(.init(id: "223A", title: "Shipper · Agreement Wizard",   role: .shipper) { p in AnyView(AgreementWizardScreen(theme: p)) })
        list.append(.init(id: "230", title: "Shipper · Bid Thread",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperBidThread(loadId: 0) }) })
        // 228b / 229b / 230b — sibling files at the same slot numbers.
        // Now in the build target after the dual-file pbxproj add and
        // the `ShipperWeeklyAllocations` rename in 230 (was previously
        // a duplicate of 229's `ShipperAllocations`). Same `Nb`
        // suffix convention Broker uses for its 401b/402b duals.
        list.append(.init(id: "228b", title: "Shipper · RFP Detail",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperRFPDetail() }) })
        list.append(.init(id: "229b", title: "Shipper · BOL Upload",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperBOLUpload() }) })
        list.append(.init(id: "230b", title: "Shipper · Weekly Allocations", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperWeeklyAllocations() }) })
        // 320 — Shipper Me Home gateway. The canonical landing surface for
        // the bottom-nav "Me" tap (see `ShipperNavRoute.map` → "me" → "320").
        // 320 is the parent hub; 320a-g are child hubs that group the
        // ~30 Me-section surfaces into 7 intuitive buckets so the top
        // page isn't a flat wall of cells. Each child hub drills into
        // registered shipper-role leaf screens — no dead taps. Co-exists
        // with the Carrier-role "320" (CarrierVehiclesListScreen) —
        // `forRole` filters by role first, so IDs are scoped per-chrome.
        list.append(.init(id: "320",  title: "Shipper · Me Home",        role: .shipper) { p in AnyView(MeHomeScreen(theme: p)) })
        list.append(.init(id: "400b", title: "Shipper · Bulk Upload",    role: .shipper) { p in AnyView(BulkUploadShellScreen(theme: p)) })
        list.append(.init(id: "320a", title: "Shipper · Me · Account",   role: .shipper) { p in AnyView(MeAccountHubScreen(theme: p)) })
        list.append(.init(id: "320b", title: "Shipper · Me · Wallet",    role: .shipper) { p in AnyView(MeWalletHubScreen(theme: p)) })
        list.append(.init(id: "320c", title: "Shipper · Me · Operations", role: .shipper) { p in AnyView(MeOperationsHubScreen(theme: p)) })
        list.append(.init(id: "320d", title: "Shipper · Me · Network",   role: .shipper) { p in AnyView(MeNetworkHubScreen(theme: p)) })
        list.append(.init(id: "320e", title: "Shipper · Me · Compliance", role: .shipper) { p in AnyView(MeComplianceHubScreen(theme: p)) })
        list.append(.init(id: "320f", title: "Shipper · Me · Intel",     role: .shipper) { p in AnyView(MeIntelHubScreen(theme: p)) })
        list.append(.init(id: "320g", title: "Shipper · Me · Settings",  role: .shipper) { p in AnyView(MeSettingsHubScreen(theme: p)) })
        // Me-section leaf screens not previously registered. The 280s,
        // 290s, 380s, 390s blocks below already register CatalystDirectory,
        // WalletHome, SettlementsList, PaymentMethods, MonthlyStatement,
        // RfpInbox, ContractList, etc. for shipper — these are the
        // remaining 10 surfaces the Me hubs need: ESANG settings,
        // Profile edit, Tier detail, Insurance, FMCSA SAFER, Hazmat
        // audit, Settings home, Notification prefs, Help, Legal.
        // ESANG chat / voice / assist surfaces — 310-318 were live in
        // `EusoTrip/Views/Shipper/31*_Esang*.swift` but never registered
        // here, so every NotificationCenter.post to "310"/"311"/"313"/
        // "314"/"318" failed RoleAccess.canRender and dropped the user
        // back to home (200). 2026-05-19 — registered under `.shipper`
        // so the chat thread list + per-thread view + voice listening
        // + transcribing + per-bid rank assist + status + forecast +
        // dispatch escalation all reach their actual screens.
        list.append(.init(id: "310", title: "Shipper · ESANG Thread List",     role: .shipper) { p in AnyView(eSangThreadListScreen(theme: p)) })
        list.append(.init(id: "311", title: "Shipper · ESANG Thread",          role: .shipper) { p in AnyView(eSangThreadScreen(theme: p, conversationId: "")) })
        list.append(.init(id: "312", title: "Shipper · ESANG Attachment",      role: .shipper) { p in AnyView(eSangAttachmentPickerScreen(theme: p)) })
        list.append(.init(id: "313", title: "Shipper · ESANG Voice",           role: .shipper) { p in AnyView(eSangVoiceListeningScreen(theme: p)) })
        list.append(.init(id: "314", title: "Shipper · ESANG Transcribing",    role: .shipper) { p in AnyView(eSangTranscribingScreen(theme: p)) })
        list.append(.init(id: "315", title: "Shipper · ESANG Rank Bids",       role: .shipper) { p in AnyView(eSangAssistRankBidsScreen(theme: p, loadId: "")) })
        list.append(.init(id: "316", title: "Shipper · ESANG Assist Status",   role: .shipper) { p in AnyView(eSangAssistStatusScreen(theme: p)) })
        list.append(.init(id: "317", title: "Shipper · ESANG Forecast",        role: .shipper) { p in AnyView(eSangAssistForecastScreen(theme: p)) })
        list.append(.init(id: "318", title: "Shipper · ESANG Dispatch Escalate", role: .shipper) { p in AnyView(eSangDispatchEscalationScreen(theme: p)) })
        list.append(.init(id: "319", title: "Shipper · ESANG Settings",        role: .shipper) { p in AnyView(eSangSettingsScreen(theme: p)) })
        list.append(.init(id: "322", title: "Shipper · Profile Edit",          role: .shipper) { p in AnyView(ProfileEditScreen(theme: p)) })
        list.append(.init(id: "323", title: "Shipper · Tier Detail",           role: .shipper) { p in AnyView(TierDetailScreen(theme: p)) })
        list.append(.init(id: "325", title: "Shipper · Insurance Detail",      role: .shipper) { p in AnyView(InsuranceDetailScreen(theme: p)) })
        list.append(.init(id: "326", title: "Shipper · FMCSA SAFER",           role: .shipper) { p in AnyView(FmcsaSaferMirrorScreen(theme: p)) })
        list.append(.init(id: "327", title: "Shipper · Hazmat Audit",          role: .shipper) { p in AnyView(HazmatAuditScreen(theme: p)) })
        list.append(.init(id: "340", title: "Shipper · Settings Home",         role: .shipper) { p in AnyView(SettingsHomeScreen(theme: p)) })
        list.append(.init(id: "343", title: "Shipper · Notification Prefs",    role: .shipper) { p in AnyView(NotificationPrefsScreen(theme: p)) })
        list.append(.init(id: "347", title: "Shipper · Help & Support",        role: .shipper) { p in AnyView(HelpSupportScreen(theme: p)) })
        list.append(.init(id: "348", title: "Shipper · Legal",                 role: .shipper) { p in AnyView(LegalScreen(theme: p)) })

        // Final pass — remaining shipper screens that have a Screen
        // struct + canonical chrome (Shell + shipperLifecycleNav) but
        // were missing from the registry. Detail screens use sentinel
        // ids/empty strings so the registry walker can paint them; live
        // call sites override with the real value at navigation time.
        // Skipped intentionally:
        //   • 260 (PostedAwaitingBidsScreen) — `#if false` shelved per
        //     the file header doctrine: references LoadsAPI.cancel and
        //     OrbeSang.State.alert, which don't exist on the iOS
        //     client today. Resurrect once those APIs land.
        //   • 324 (ComplianceDashboardScreen) — superseded by 216
        //     ("Shipper · Compliance"), which Me hub 320e routes to.
        //   • 410 LoadsFilterSheetScreen / 411 LoadsSortSheetScreen —
        //     hold @Binding state owned by parent 201_ShipperLoads;
        //     presented modally, never reached via screenId.
        list.append(.init(id: "333", title: "Shipper · Contact Detail",          role: .shipper) { p in AnyView(ContactDetailScreen(theme: p, contactId: "0")) })
        list.append(.init(id: "334", title: "Shipper · Add Contact",             role: .shipper) { p in AnyView(AddContactScreen(theme: p)) })
        list.append(.init(id: "336", title: "Shipper · Grade Detail",            role: .shipper) { p in AnyView(GradeDetailScreen(theme: p)) })
        list.append(.init(id: "341", title: "Shipper · Lane Templates",          role: .shipper) { p in AnyView(LaneTemplatesListScreen(theme: p)) })
        list.append(.init(id: "342", title: "Shipper · Lane Template Editor",    role: .shipper) { p in AnyView(LaneTemplateEditorScreen(theme: p, templateId: "0")) })
        list.append(.init(id: "344", title: "Shipper · Security Sessions",       role: .shipper) { p in AnyView(SecuritySessionsScreen(theme: p)) })
        list.append(.init(id: "345", title: "Shipper · Two-Factor",              role: .shipper) { p in AnyView(TwoFactorManageScreen(theme: p)) })
        list.append(.init(id: "346", title: "Shipper · Connected Apps",          role: .shipper) { p in AnyView(ConnectedAppsScreen(theme: p)) })
        list.append(.init(id: "349", title: "Shipper · Account Export / Delete", role: .shipper) { p in AnyView(AccountExportDeleteScreen(theme: p)) })
        list.append(.init(id: "412", title: "Shipper · Drafts List",             role: .shipper) { p in AnyView(DraftsListScreen(theme: p)) })
        list.append(.init(id: "413", title: "Shipper · Archived Loads",          role: .shipper) { p in AnyView(ArchivedLoadsScreen(theme: p)) })
        list.append(.init(id: "414", title: "Shipper · Bid Detail Sheet",        role: .shipper) { p in AnyView(BidDetailSheetScreen(theme: p, loadId: "0", bidId: "0")) })
        list.append(.init(id: "415", title: "Shipper · Counter-Offer Composer",  role: .shipper) { p in AnyView(CounterOfferComposerScreen(theme: p, loadId: "0", bidId: "0")) })
        list.append(.init(id: "416", title: "Shipper · Bid Reject Sheet",        role: .shipper) { p in AnyView(BidRejectSheetScreen(theme: p, loadId: "0", bidId: "0")) })
        list.append(.init(id: "417", title: "Shipper · Bid Accept Confirmation", role: .shipper) { p in AnyView(BidAcceptConfirmationScreen(theme: p, loadId: "0", bidId: "0")) })
        list.append(.init(id: "418", title: "Shipper · Tender Accept Countdown", role: .shipper) { p in AnyView(TenderAcceptCountdownScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "419", title: "Shipper · Exception Response",      role: .shipper) { p in AnyView(ExceptionResponseScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "420", title: "Shipper · Bid Review Board",        role: .shipper) { p in AnyView(BidReviewBoardScreen(theme: p)) })
        list.append(.init(id: "421", title: "Shipper · Load Consolidation",      role: .shipper) { p in AnyView(LoadConsolidationScreen(theme: p)) })
        list.append(.init(id: "422", title: "Shipper · My Terminals",            role: .shipper) { p in AnyView(MyTerminalsScreen(theme: p)) })
        list.append(.init(id: "423", title: "Shipper · Facility Search",         role: .shipper) { p in AnyView(FacilitySearchScreen(theme: p)) })
        list.append(.init(id: "424", title: "Shipper · Spectra-Match",           role: .shipper) { p in AnyView(SpectraMatchScreen(theme: p)) })
        list.append(.init(id: "425", title: "Shipper · Port Intelligence",       role: .shipper) { p in AnyView(PortIntelligenceScreen(theme: p)) })
        list.append(.init(id: "426", title: "Shipper · Demurrage Charges",       role: .shipper) { p in AnyView(DemurrageChargesScreen(theme: p)) })
        list.append(.init(id: "427", title: "Shipper · Cross-Border Shipping",   role: .shipper) { p in AnyView(CrossBorderShippingScreen(theme: p)) })
        list.append(.init(id: "428", title: "Shipper · Carrier Capacity",        role: .shipper) { p in AnyView(CarrierCapacityScreen(theme: p)) })
        list.append(.init(id: "429", title: "Shipper · Competitive Intelligence", role: .shipper) { p in AnyView(CompetitiveIntelligenceScreen(theme: p)) })
        list.append(.init(id: "430", title: "Shipper · Industry Verticals",      role: .shipper) { p in AnyView(IndustryVerticalsScreen(theme: p)) })
        list.append(.init(id: "431", title: "Shipper · Multi-Modal Transport",   role: .shipper) { p in AnyView(MultiModalTransportScreen(theme: p)) })
        list.append(.init(id: "432", title: "Shipper · Vendor Management",       role: .shipper) { p in AnyView(VendorManagementScreen(theme: p)) })
        list.append(.init(id: "433", title: "Shipper · Recurring Loads Composer", role: .shipper) { p in AnyView(RecurringLoadsComposerScreen(theme: p)) })
        list.append(.init(id: "434", title: "Shipper · Partner Detail",          role: .shipper) { p in AnyView(PartnerDetailScreen(theme: p, partnerId: "0")) })
        list.append(.init(id: "435", title: "Shipper · Partner Agreements",      role: .shipper) { p in AnyView(PartnerAgreementsScreen(theme: p, partnerId: "0")) })
        list.append(.init(id: "436", title: "Shipper · Hot Zone City Detail",    role: .shipper) { p in AnyView(HotZoneCityDetailScreen(theme: p, city: "")) })
        // 231-240 — Arc L iOS-platform integration preview surfaces.
        // These ARE NOT extension targets — they're in-app reference
        // screens that paint what the eventual Widget Extension /
        // ActivityKit Live Activity / WatchKit complication / CarPlay
        // scene / App Intents / etc. would render. The actual
        // extension targets (Widget Extension target, CarPlay scene
        // declaration in Info.plist + entitlement, App Intents
        // metadata bundle) are separate Xcode-target work that ships
        // alongside production launch — see the file-header
        // doctrines in each. Registry entry mounts the preview
        // surface so designers can review the look from inside the
        // app. 231/232 use `wrapShipperScreen` (bare Views without
        // a Screen struct); 233-240 ship `XxxScreen: View` wrappers.
        list.append(.init(id: "231", title: "Shipper · Push Notification Landing", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperPushNotificationLanding() }) })
        list.append(.init(id: "232", title: "Shipper · Lock Screen Live Activity", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperLockScreenLiveActivity() }) })
        list.append(.init(id: "233", title: "Shipper · Watch Complication",        role: .shipper) { p in AnyView(ShipperWatchComplicationScreen(theme: p)) })
        list.append(.init(id: "234", title: "Shipper · Haptic Escalation",         role: .shipper) { p in AnyView(ShipperHapticEscalationScreen(theme: p)) })
        list.append(.init(id: "235", title: "Shipper · Focus Mode Widget",         role: .shipper) { p in AnyView(ShipperFocusModeWidgetScreen(theme: p)) })
        list.append(.init(id: "236", title: "Shipper · Widget Gallery",            role: .shipper) { p in AnyView(ShipperWidgetGalleryScreen(theme: p)) })
        list.append(.init(id: "237", title: "Shipper · App Intents",               role: .shipper) { p in AnyView(ShipperAppIntentsScreen(theme: p)) })
        list.append(.init(id: "238", title: "Shipper · Handoff Continuity",        role: .shipper) { p in AnyView(ShipperHandoffContinuityScreen(theme: p)) })
        list.append(.init(id: "239", title: "Shipper · Apple Pay Wallet",          role: .shipper) { p in AnyView(ShipperApplePayWalletScreen(theme: p)) })
        list.append(.init(id: "240", title: "Shipper · CarPlay Dashboard",         role: .shipper) { p in AnyView(ShipperCarPlayDashboardScreen(theme: p)) })
        // 250-259 PostLoad wizard. 250 owns its own `PostLoadDraft`
        // `@StateObject`; 251-259 take the draft as `@ObservedObject`.
        // The registry closure is `@MainActor`-isolated (see
        // `ProductionScreen.view` declaration), so the closure body
        // runs in main-actor context — `PostLoadDraft()` (which is
        // `@MainActor`-bound) constructs cleanly without an
        // `assumeIsolated` wrap. Each registry-walker entry hands a
        // throwaway draft; production navigation through the wizard
        // always carries the wizard's single shared draft from
        // 250's `@StateObject`.
        list.append(.init(id: "250", title: "Shipper · Post Load · Lane",      role: .shipper) { p in AnyView(PostLoadStep1LaneScreen(theme: p)) })
        list.append(.init(id: "251", title: "Shipper · Post Load · Equipment", role: .shipper) { p in AnyView(PostLoadStep2EquipmentScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "252", title: "Shipper · Post Load · Pricing",   role: .shipper) { p in AnyView(PostLoadStep3PricingScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "253", title: "Shipper · Post Load · Review",    role: .shipper) { p in AnyView(PostLoadStep4ReviewScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "254", title: "Shipper · Post Load · Success",   role: .shipper) { p in AnyView(PostLoadSuccessScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "255", title: "Shipper · Post Load · Multi-Stop", role: .shipper) { p in AnyView(PostLoadMultiStopScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "256", title: "Shipper · Post Load · Address",   role: .shipper) { p in AnyView(PostLoadAddressPickerScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "257", title: "Shipper · Post Load · Hazmat",    role: .shipper) { p in AnyView(PostLoadHazmatSubformScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "258", title: "Shipper · Post Load · Reefer",    role: .shipper) { p in AnyView(PostLoadReeferSubformScreen(theme: p, draft: PostLoadDraft())) })
        list.append(.init(id: "259", title: "Shipper · Post Load · Templates", role: .shipper) { p in AnyView(PostLoadTemplatesScreen(theme: p, draft: PostLoadDraft())) })
        // 260 (PostedAwaitingBids) is shelved (LoadsAPI.cancel missing)
        // and intentionally NOT registered — see the `#if false` wrap
        // in the file header.
        // 261-269 lifecycle surfaces (load-context detail screens).
        // Each takes a `loadId`; we hand `"0"` for registry-walker
        // entry. Production reaches these via load detail or push
        // notification deep-links with the real load ID.
        list.append(.init(id: "261", title: "Shipper · Bidding Live Feed",  role: .shipper) { p in AnyView(BiddingLiveFeedScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "262", title: "Shipper · Awarded · Pre-Pickup", role: .shipper) { p in AnyView(AwardedPrePickupScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "263", title: "Shipper · Pickup · Approaching", role: .shipper) { p in AnyView(PickupApproachingScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "264", title: "Shipper · Pickup · At Gate",     role: .shipper) { p in AnyView(PickupAtGateScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "265", title: "Shipper · Pickup · At Dock",     role: .shipper) { p in AnyView(PickupAtDockScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "266", title: "Shipper · Pickup · BOL Signing", role: .shipper) { p in AnyView(ShipperPickupBolSigningScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "267", title: "Shipper · In-Transit · Live",    role: .shipper) { p in AnyView(InTransitLiveScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "268", title: "Shipper · In-Transit · HOS Pause", role: .shipper) { p in AnyView(InTransitHosPauseScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "269", title: "Shipper · In-Transit · Exception", role: .shipper) { p in AnyView(InTransitExceptionScreen(theme: p, loadId: "0")) })
        // Phase 3.2 (sweep 270-399): rest of the in-build Shipper
        // surface. 270-279 lifecycle (Delivery / Paperwork / Closed /
        // Cancelled / Reefer Excursion) take a `loadId`. 280-289
        // catalyst directory + detail surfaces (catalyst here = the
        // shipper's view of carriers; some take `catalystId`).
        // 290-299 wallet / settlements / payment / sustainability /
        // reports surfaces. 360-369 platform-permission + error
        // states (most are param-less or have all-default args).
        // 380-387 RFP / contract / claims composer (take rfpId /
        // contractId / loadId where required). 390-399 notifications
        // + search + quotes + role-pick + KYB / email-verify states.
        // Every loadId/catalystId/settlementId/etc gets the `"0"`
        // sentinel for registry-walker entry; production reaches
        // these with real IDs via deep-link or push.
        list.append(.init(id: "270", title: "Shipper · Delivery · Approaching",  role: .shipper) { p in AnyView(DeliveryApproachingScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "271", title: "Shipper · Delivery · At Receiver",  role: .shipper) { p in AnyView(DeliveryAtReceiverScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "272", title: "Shipper · Delivery · POD Signed",   role: .shipper) { p in AnyView(DeliveryPodSignedScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "273", title: "Shipper · Paperwork · BOL Final",   role: .shipper) { p in AnyView(PaperworkBolFinalScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "274", title: "Shipper · Paperwork · Accessorials", role: .shipper) { p in AnyView(PaperworkAccessorialsScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "275", title: "Shipper · Closed · Settlement Preview", role: .shipper) { p in AnyView(ClosedSettlementPreviewScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "276", title: "Shipper · Closed · Paid",           role: .shipper) { p in AnyView(ClosedPaidScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "277", title: "Shipper · Cancelled · Pre-Pickup",  role: .shipper) { p in AnyView(CancelledPrePickupScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "278", title: "Shipper · Cancelled · In-Transit",  role: .shipper) { p in AnyView(CancelledInTransitScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "279", title: "Shipper · Reefer Temp Excursion",   role: .shipper) { p in AnyView(ReeferTempExcursionScreen(theme: p, loadId: "0")) })

        // 280-289 — Catalyst (carrier-from-shipper-view) directory
        list.append(.init(id: "280", title: "Shipper · Catalyst Directory",      role: .shipper) { p in AnyView(CatalystDirectoryScreen(theme: p)) })
        list.append(.init(id: "281", title: "Shipper · Catalyst Detail",         role: .shipper) { p in AnyView(CatalystDetailSummaryScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "282", title: "Shipper · Catalyst Loads History",  role: .shipper) { p in AnyView(CatalystLoadsHistoryScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "283", title: "Shipper · Catalyst Ratings",        role: .shipper) { p in AnyView(CatalystRatingsScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "284", title: "Shipper · Catalyst Compliance",     role: .shipper) { p in AnyView(CatalystCompliancePeekScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "285", title: "Shipper · Catalyst Sparkline Trend", role: .shipper) { p in AnyView(CatalystSparklineTrendScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "286", title: "Shipper · Add Favorite Catalyst",   role: .shipper) { p in AnyView(AddFavoriteCatalystScreen(theme: p)) })
        list.append(.init(id: "287", title: "Shipper · Catalyst Risk Flag",      role: .shipper) { p in AnyView(CatalystRiskFlagScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "288", title: "Shipper · Catalyst Contact",        role: .shipper) { p in AnyView(CatalystContactScreen(theme: p, catalystId: "0")) })
        list.append(.init(id: "289", title: "Shipper · Invite Catalyst",         role: .shipper) { p in AnyView(InviteCatalystScreen(theme: p)) })

        // 290-299 — Wallet / Settlements / Reports
        list.append(.init(id: "290", title: "Shipper · Wallet Home",             role: .shipper) { p in AnyView(WalletHomeScreen(theme: p)) })
        list.append(.init(id: "291", title: "Shipper · EusoWallet Detail",       role: .shipper) { p in AnyView(EusoWalletDetailScreen(theme: p)) })
        list.append(.init(id: "292", title: "Shipper · Settlements List",        role: .shipper) { p in AnyView(SettlementsListScreen(theme: p)) })
        list.append(.init(id: "293", title: "Shipper · Settlement Detail",       role: .shipper) { p in AnyView(SettlementDetailScreen(theme: p, settlementId: "0")) })
        list.append(.init(id: "294", title: "Shipper · Dispute Settlement",      role: .shipper) { p in AnyView(DisputeSettlementScreen(theme: p, settlementId: "0")) })
        list.append(.init(id: "295", title: "Shipper · Payment Methods",         role: .shipper) { p in AnyView(PaymentMethodsScreen(theme: p)) })
        list.append(.init(id: "296", title: "Shipper · Add Payment Method",      role: .shipper) { p in AnyView(AddPaymentMethodScreen(theme: p)) })
        list.append(.init(id: "297", title: "Shipper · Monthly Statement",       role: .shipper) { p in AnyView(MonthlyStatementScreen(theme: p)) })
        list.append(.init(id: "298", title: "Shipper · Sustainability",          role: .shipper) { p in AnyView(SustainabilityScreen(theme: p)) })
        list.append(.init(id: "299", title: "Shipper · Reports",                 role: .shipper) { p in AnyView(ReportsScreen(theme: p)) })

        // 360-369 — Platform / permissions / error states. These are
        // mostly transient surfaces presented over the role surface
        // (push permission ask, biometric unlock, force-update) —
        // registered so deep-links (notification re-presentation,
        // network failure recovery) can still target them.
        list.append(.init(id: "360", title: "Shipper · Push Permission",         role: .shipper) { p in AnyView(PushPermissionScreen(theme: p)) })
        list.append(.init(id: "361", title: "Shipper · Location Permission",     role: .shipper) { p in AnyView(LocationPermissionScreen(theme: p)) })
        list.append(.init(id: "362", title: "Shipper · Camera Permission",       role: .shipper) { p in AnyView(CameraPermissionScreen(theme: p)) })
        list.append(.init(id: "363", title: "Shipper · Mic Permission",          role: .shipper) { p in AnyView(MicPermissionScreen(theme: p)) })
        list.append(.init(id: "364", title: "Shipper · Offline Banner",          role: .shipper) { p in AnyView(OfflineBannerScreen(theme: p)) })
        list.append(.init(id: "365", title: "Shipper · Network Error Retry",     role: .shipper) { p in AnyView(NetworkErrorRetryScreen(theme: p)) })
        list.append(.init(id: "366", title: "Shipper · Force Update",            role: .shipper) { p in AnyView(ForceUpdateScreen(theme: p)) })
        list.append(.init(id: "367", title: "Shipper · Account Suspended",       role: .shipper) { p in AnyView(AccountSuspendedScreen(theme: p)) })
        list.append(.init(id: "368", title: "Shipper · KYB Rejected",            role: .shipper) { p in AnyView(KybRejectedScreen(theme: p)) })
        list.append(.init(id: "369", title: "Shipper · Background Biometric",    role: .shipper) { p in AnyView(BackgroundBiometricScreen(theme: p)) })

        // 380-387 — RFP / Contracts / Claims / Reconciliation
        list.append(.init(id: "380", title: "Shipper · RFP Inbox",               role: .shipper) { p in AnyView(RfpInboxScreen(theme: p)) })
        list.append(.init(id: "381", title: "Shipper · RFP Detail",              role: .shipper) { p in AnyView(RfpDetailScreen(theme: p, rfpId: "0")) })
        list.append(.init(id: "382", title: "Shipper · Contract List",           role: .shipper) { p in AnyView(ContractListScreen(theme: p)) })
        list.append(.init(id: "383", title: "Shipper · Contract Detail",         role: .shipper) { p in AnyView(ContractDetailScreen(theme: p, contractId: "0")) })
        list.append(.init(id: "384", title: "Shipper · Bulk Retender",           role: .shipper) { p in AnyView(BulkRetenderScreen(theme: p)) })
        list.append(.init(id: "385", title: "Shipper · Batch Tender",            role: .shipper) { p in AnyView(BatchTenderScreen(theme: p)) })
        list.append(.init(id: "386", title: "Shipper · Freight Claim Composer",  role: .shipper) { p in AnyView(FreightClaimComposerScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "387", title: "Shipper · Finance Reconciliation",  role: .shipper) { p in AnyView(FinanceReconciliationScreen(theme: p)) })

        // 390-399 — Notifications / search / quotes / role-pick / KYB / email-verify
        list.append(.init(id: "390", title: "Shipper · Notifications Inbox",     role: .shipper) { p in AnyView(NotificationsInboxScreen(theme: p)) })
        list.append(.init(id: "391", title: "Shipper · Notification Detail",     role: .shipper) { p in AnyView(NotificationDetailScreen(theme: p, notificationId: "0")) })
        list.append(.init(id: "392", title: "Shipper · Search Everything",       role: .shipper) { p in AnyView(SearchEverythingScreen(theme: p)) })
        list.append(.init(id: "393", title: "Shipper · Search Results",          role: .shipper) { p in AnyView(SearchResultsScreen(theme: p, query: "")) })
        list.append(.init(id: "394", title: "Shipper · Quote · Instant",         role: .shipper) { p in AnyView(QuoteInstantScreen(theme: p)) })
        list.append(.init(id: "395", title: "Shipper · Quote · Saved",           role: .shipper) { p in AnyView(QuoteSavedScreen(theme: p)) })
        list.append(.init(id: "396", title: "Shipper · Home · Empty State",      role: .shipper) { p in AnyView(HomeEmptyStateScreen(theme: p)) })
        list.append(.init(id: "397", title: "Shipper · Role Pick",               role: .shipper) { p in AnyView(RolePickScreen(theme: p)) })
        list.append(.init(id: "398", title: "Shipper · KYB Legal Entity",        role: .shipper) { p in AnyView(KybLegalEntityScreen(theme: p)) })
        list.append(.init(id: "399", title: "Shipper · Email Verify Pending",    role: .shipper) { p in AnyView(EmailVerifyPendingScreen(theme: p)) })
        // 2026-04-25 — eusotrip-killers 100th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // First real Carrier-track brick lands in production. Lifts
        // id "300" out of the `#if DEBUG` placeholder block below so
        // non-debug builds also get the Carrier Home surface. Backed
        // by `carriers.{getDashboardStats,getActiveLoads,
        // getLoadsRequiringAttention,getRecentLoads}` — see
        // `300_CarrierHome.swift` header for the full doctrine and
        // store wire-up. Name disambiguation against the existing
        // Driver-Me brick 085 `CarrierScorecardStore` is documented
        // in `LiveDataStores.swift` (the home stores use the prefix
        // `CarrierHome*` / `CarrierActiveLoads*` / `CarrierAlerts*`
        // / `CarrierRecentLoads*` to avoid collision).
        list.append(
            .init(id: "300", title: "Carrier · Home", role: .carrier) { p in
                AnyView(CarrierHomeScreen(theme: p))
            }
        )
        // 2026-04-25 — eusotrip-killers 100th firing (continued):
        // Second Carrier-track brick. Mirror of 201 Shipper · Loads
        // swung to the carrier side: `carriers.getActiveLoads` +
        // `carriers.getRecentLoads` via the existing
        // `CarrierActiveLoadsStore` / `CarrierRecentLoadsStore` (no
        // new stores or API namespaces needed). Tap-detail surfaces
        // `EusoEmptyState(comingSoon:)` placeholder labeled "brick
        // 302" — no fabricated detail data per the no-mock pledge.
        list.append(
            .init(id: "301", title: "Carrier · Loads", role: .carrier) { p in
                AnyView(CarrierLoadsScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 130th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Third real Carrier-track brick lands in production. Per the
        // 129th firing's hand-off recommendation: "Code-port fallback
        // if A still blocked: pivot from anchor sweep to second-screen
        // depth — highest-value next ports per backend coverage are
        // 302 (Carrier loads detail — carriers.* router has many live
        // procedures)." The 301 row tap previously surfaced an
        // EusoEmptyState placeholder; with 302 live, that placeholder
        // is replaced with the real CarrierLoadDetailScreen on row
        // tap. Backed by `CarrierLoadDetailStore` (LiveDataStores.swift,
        // added in this firing) → `loads.getById` (verified at
        // frontend/server/routers/loads.ts:1046, protectedProcedure).
        // Same backend procedure that powers 205_ShipperLoadDetail —
        // the role distinction is in framing: carrier reframes the
        // Shipper "bids count" panel as "assignment + counterparty +
        // settlement" cards because the carrier perspective is who
        // they're hauling for and what they collect, not who they're
        // paying. Cohort B day-1 — every field surfaces verbatim from
        // the server. When the load is partially filled (no driver
        // assigned yet, no actual delivery date, no rate posted) the
        // screen renders em-dash neutral states — never fabricated
        // values. The dev-chrome registry entry uses loadId="0" purely
        // as a placeholder so the next/prev walk doesn't break; the
        // real navigation path is the sheet from 301.
        list.append(
            .init(id: "302", title: "Carrier · Load Detail", role: .carrier) { p in
                AnyView(CarrierLoadDetailScreen(
                    theme: p,
                    loadId: "0",
                    previewLoadNumber: nil,
                    previewLane: nil,
                    previewStatus: nil,
                    previewDriver: nil,
                    previewCounterparty: nil,
                    previewRate: nil,
                    previewIsActive: true
                ))
            }
        )
        // 2026-04-27 — eusotrip-killers 144th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Fourth Carrier-track brick lands in production. Per the 143rd
        // firing's hand-off recommendation: "Driver=117, Shipper=12,
        // Carrier=3 — Carrier is the deepest gap among production roles.
        // The next high-leverage port is 303_CarrierDispatchBoard — the
        // carrier-side dispatch screen that closes the carrier→driver
        // dispatch loop and pairs with the existing carriers.* tRPC
        // procedures (loads-lifecycle slice §16-02)." Backed by the
        // existing `CarrierActiveLoadsStore` + `CarrierAlertsStore` —
        // no new tRPC procedure needed. The dispatch axis is a
        // *projection* over `carriers.getActiveLoads` rows binned by
        // `driver`/`status`, joined onto `carriers.getLoadsRequiringAttention`
        // by `loadNumber`. Per doctrine §13 (no fabricated values) +
        // §17 (work together with the dev team), composing existing
        // procedures keeps the client/server contract unchanged.
        // Cohort B day-1 — every value paints from the server. Row tap
        // routes to `CarrierLoadDetailScreen` (brick 302) so the
        // dispatch board → load detail loop is closed without
        // duplicating the detail surface.
        list.append(
            .init(id: "303", title: "Carrier · Dispatch Board", role: .carrier) { p in
                AnyView(CarrierDispatchBoardScreen(theme: p))
            }
        )
        // 2026-04-27 — eusotrip-killers 145th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Fifth Carrier-track brick. Closes the dispatch-loop driver-
        // roster axis the 303 board references via the UNASSIGNED chip.
        // Roster is a *projection* over `carriers.getActiveLoads` —
        // every unique non-empty driver name becomes a roster entry,
        // with per-driver active-load count + lane summary aggregated
        // from the same rows. When the dev team ships a real
        // `carriers.getRoster` (or `drivers.list`), the projection
        // swap is one line in `CarrierDriverRosterRow.project(from:)`
        // — the UI surface stays unchanged. Per doctrine §13 +§17,
        // composing existing endpoints (instead of inventing a server
        // contract) keeps parallel dev-team work conflict-free.
        list.append(
            .init(id: "304", title: "Carrier · Drivers", role: .carrier) { p in
                AnyView(CarrierDriversScreen(theme: p))
            }
        )
        // 2026-05-01 — Carrier surface knock-down: register the
        // remaining 16 carrier screens (305-320) so the carrier role
        // surface in `RoleSurfaceRouter` can navigate to every screen
        // the file tree already ships. Each screen wrapper is real
        // (live store under it, no stubs) and ships with the
        // `theme: Theme.Palette` signature the registry calls through.
        // RBAC (`RoleAccess.canRender`) gates every cross-role swap.
        list.append(.init(id: "305", title: "Carrier · Counter Response",  role: .carrier) { p in AnyView(CarrierCounterResponseScreen(theme: p)) })
        list.append(.init(id: "306", title: "Carrier · Marketplace",       role: .carrier) { p in AnyView(CarrierMarketplaceScreen(theme: p)) })
        // 307/310/311 take a `loadId` because they're context-dependent
        // surfaces (bid against this load, assign a driver to this
        // load, drill into this active load). When the registry walker
        // mounts them with no upstream load, the `"0"` sentinel
        // surfaces an honest empty state — matches 302's pattern.
        // Production navigation always reaches these screens with a
        // real loadId via sheet/push handoff from 301 or 306.
        list.append(.init(id: "307", title: "Carrier · Bid Compose",       role: .carrier) { p in AnyView(CarrierBidComposeScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "308", title: "Carrier · My Bids",           role: .carrier) { p in AnyView(CarrierMyBidsScreen(theme: p)) })
        list.append(.init(id: "309", title: "Carrier · Awarded Loads",     role: .carrier) { p in AnyView(CarrierAwardedLoadsScreen(theme: p)) })
        list.append(.init(id: "310", title: "Carrier · Assign Driver",     role: .carrier) { p in AnyView(CarrierAssignDriverScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "311", title: "Carrier · Active Load",       role: .carrier) { p in AnyView(CarrierActiveLoadScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "312", title: "Carrier · Earnings",          role: .carrier) { p in AnyView(CarrierEarningsHomeScreen(theme: p)) })
        list.append(.init(id: "313", title: "Carrier · Settlements",       role: .carrier) { p in AnyView(CarrierSettlementsListScreen(theme: p)) })
        list.append(.init(id: "314", title: "Carrier · Fuel Card",         role: .carrier) { p in AnyView(CarrierFuelCardScreen(theme: p)) })
        list.append(.init(id: "315", title: "Carrier · Maintenance",       role: .carrier) { p in AnyView(CarrierMaintenanceScreen(theme: p)) })
        list.append(.init(id: "316", title: "Carrier · Compliance Dash",   role: .carrier) { p in AnyView(CarrierComplianceDashScreen(theme: p)) })
        list.append(.init(id: "317", title: "Carrier · Authority",         role: .carrier) { p in AnyView(CarrierAuthorityScreen(theme: p)) })
        list.append(.init(id: "318", title: "Carrier · ELD",               role: .carrier) { p in AnyView(CarrierELDScreen(theme: p)) })
        list.append(.init(id: "319", title: "Carrier · Drivers List",      role: .carrier) { p in AnyView(CarrierDriversListScreen(theme: p)) })
        list.append(.init(id: "320", title: "Carrier · Vehicles List",     role: .carrier) { p in AnyView(CarrierVehiclesListScreen(theme: p)) })
        list.append(.init(id: "350", title: "Carrier · Me",                role: .carrier) { p in AnyView(CarrierMeScreen(theme: p)) })
        // 2026-04-25 — eusotrip-killers 99th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // First real Broker-track brick lands in production. Lifts id
        // "400" out of the `#if DEBUG` placeholder block below so non-
        // debug builds also get the Broker Home surface. Backed by
        // `brokers.{getDashboardStats,getOpenTenders,
        // getLoadsRequiringAttention,getRecentLoads}` — see
        // `400_BrokerHome.swift` header for the full doctrine and
        // store wire-up. The broker sits between the shipper
        // (originator) and the carrier (mover); the home re-frames
        // the four-card hierarchy around tender flow + margin rather
        // than active-load count, so `OpenTenders` replaces the
        // Carrier's `ActiveLoads` slot and `grossMarginThisWeek`
        // replaces `weeklyRevenue`.
        list.append(
            .init(id: "400", title: "Broker · Home", role: .broker) { p in
                AnyView(BrokerHomeScreen(theme: p))
            }
        )
        // 2026-04-26 — eusotrip-killers 131st firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Second brick on the Broker role track lands. Lifts id "401"
        // out of the `#if DEBUG` placeholder block below so non-debug
        // builds also get the Broker Tenders board. Backed by the
        // existing `BrokerOpenTendersStore` (LiveDataStores.swift,
        // shipped at the 99th firing for 400_BrokerHome) but with
        // the store's `limit` bumped to 50 inside `.task` so the full
        // board renders, not just the home strip's 10. Tap on a row
        // surfaces an honest `EusoEmptyState(comingSoon: true)`
        // sheet for 402_BrokerTenderDetail until that brick ships —
        // never fabricated detail data per §13 no-fake-data doctrine.
        // First port off the 130th firing's "24-user 3-screen-per-
        // role expansion track" — Broker now has 2 of 6 anchors,
        // matching Carrier's first non-anchor depth (302).
        list.append(
            .init(id: "401", title: "Broker · Tenders", role: .broker) { p in
                AnyView(BrokerTendersScreen(theme: p))
            }
        )
        // 2026-04-27 — eusotrip-killers 132nd firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Second-screen depth on the Broker role — 402_BrokerTenderDetail
        // ships as the natural follow-on to 401. Mirrors the carrier
        // 302 pattern: backed by `BrokerTenderDetailStore`
        // (LiveDataStores.swift:3909) which calls the same
        // `loads.getById` procedure (frontend/server/routers/loads.ts:1046)
        // already powering 205_ShipperLoadDetail and 302_CarrierLoadDetail.
        // Role distinction is in framing only — the broker reframes
        // "load" as "tender" and emphasises the target-rate vs. market-
        // range spread + responding-carrier count rather than driver
        // assignment. Carrier shortlist + award CTA render as honest
        // placeholders until `brokers.getTenderResponses` /
        // `brokers.awardTender` ship server-side. With this brick,
        // Broker reaches 3 of 6 anchors — same depth as Carrier (300 +
        // 301 + 302) per the 24-user 3-screen-per-role expansion track.
        list.append(
            .init(id: "402", title: "Broker · Tender Detail", role: .broker) { p in
                AnyView(
                    BrokerTenderDetailScreen(
                        theme: p,
                        tenderId: "0"
                    )
                )
            }
        )
        // 2026-05-01 — Broker surface knock-down: register the 5
        // remaining broker screens. Slots 401 and 402 already hold a
        // canonical screen each (Tenders board and Tender Detail), so
        // sibling surfaces use the `Nb` suffix (`401b`, `402b`) the
        // same way Shipper handles 228/229/230 dual-file slots. 402b
        // and 403 take a `loadId` (and 403 a `catalystId`); we pass
        // the `"0"` sentinel for registry-walker entry — production
        // navigation always reaches them with real IDs via sheet /
        // push handoff from 401 or 402.
        list.append(.init(id: "401b", title: "Broker · Load Board",       role: .broker) { p in AnyView(BrokerLoadBoardScreen(theme: p)) })
        list.append(.init(id: "402b", title: "Broker · Carrier Vet",      role: .broker) { p in AnyView(BrokerCarrierVetScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "403",  title: "Broker · Tender to Carrier", role: .broker) { p in AnyView(BrokerTenderToCarrierScreen(theme: p, loadId: "0", catalystId: "0")) })
        list.append(.init(id: "404",  title: "Broker · Commission Queue", role: .broker) { p in AnyView(BrokerCommissionQueueScreen(theme: p)) })
        list.append(.init(id: "405",  title: "Broker · Active Brokerages", role: .broker) { p in AnyView(BrokerActiveBrokeragesScreen(theme: p)) })
        // 2026-05-21 — eusotrip-killers screen porting sweep. CatalystVetting.tsx
        // (web) lands as 406 — the catalyst-onboarding review queue. Server
        // stubs in `brokers.{getVettingStats, approveCatalyst, rejectCatalyst}`
        // upgraded to real DB writes in the same commit pair so the buttons
        // are not dead.
        list.append(.init(id: "406",  title: "Broker · Catalyst Vetting", role: .broker) { p in AnyView(BrokerCatalystVettingScreen(theme: p)) })
        // 2026-05-21 — 407 drill-down (web CatalystVettingDetails.tsx port).
        // catalystId routes through BrokerNavContext.latestCatalystId so
        // the row tap from 406 hands off correctly.
        list.append(.init(id: "407",  title: "Broker · Catalyst Vetting Details", role: .broker) { p in
            AnyView(BrokerCatalystVettingDetailsScreen(theme: p, catalystId: BrokerNavContext.latestCatalystId))
        })
        // 2026-04-25 — eusotrip-killers 102nd firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // First real Catalyst-track brick lands in production. Lifts
        // id "500" out of the `#if DEBUG` placeholder block below so
        // non-debug builds also get the Catalyst Home surface. Backed
        // by `catalysts.{getDashboardStats,getActiveMatches,
        // getLoadsRequiringAttention,getRecentMatches}` — see
        // `500_CatalystHome.swift` header for the full doctrine and
        // store wire-up. Catalyst is the AI-augmented dispatch /
        // SpectraMatch operator role per §16 intelligence slice
        // (Autopilot 7-layer cortex, 52 agents); the home re-frames
        // the four-card hierarchy around match flow + fit-score
        // rather than tender flow or active-load count, so
        // `ActiveMatches` replaces the Broker's `OpenTenders` slot
        // and `gmvThisWeek` replaces `grossMarginThisWeek`.
        list.append(
            .init(id: "500", title: "Catalyst · Home", role: .catalyst) { p in
                AnyView(CatalystHomeScreen(theme: p))
            }
        )
        // 2026-05-22 — Catalyst 300 owner-op Home (wireframe slot 300).
        // Sister surface to 500 — single-truck owner-op flow with
        // Drive-mode toggle, active haul card, tender-queue accept.
        // Backed by catalysts.{getProfile, getDashboardStats,
        // getActiveLoads, getAvailableLoads, submitBid}.
        list.append(
            .init(id: "300", title: "Catalyst · Owner-Op Home", role: .catalyst) { p in
                AnyView(CatalystOwnerOpHome(theme: p))
            }
        )
        // 2026-05-22 — Catalyst 348 outbound-counter receipt (§270).
        // Post-acceptance read-only surface; load context via loads.getById.
        list.append(
            .init(id: "348", title: "Catalyst · Counter Receipt", role: .catalyst) { p in
                AnyView(CatalystShipperCounterReceiptScreen(theme: p, loadId: BrokerNavContext.latestLoadId, onDone: {}))
            }
        )
        // 2026-05-22 — Catalyst 349 awarded confirmation (§271).
        // Sister to 348; post-award read-only surface. Buttons:
        // Assign driver → routes to Dispatch 532 (M-05 Assign Driver).
        list.append(
            .init(id: "349", title: "Catalyst · Awarded Confirmation", role: .catalyst) { p in
                AnyView(CatalystAwardedConfirmationScreen(theme: p, loadId: BrokerNavContext.latestLoadId, onAssignDriver: {}, onDone: {}))
            }
        )
        // 2026-05-22 — Catalyst 377 paperwork settlement prep (§403).
        // Read-only consumer between POD-signed and paid; factoring
        // autopilot drives the state machine server-side.
        list.append(
            .init(id: "377", title: "Catalyst · Paperwork Prep", role: .catalyst) { p in
                AnyView(CatalystPaperworkSettlementPrepScreen(theme: p, loadId: BrokerNavContext.latestLoadId))
            }
        )
        // 2026-05-22 — Catalyst 378 closed payout (§407).
        // Post-paid catalyst vantage; consumes loadLifecycle paid
        // fan-out. Sister to Driver 149.
        list.append(
            .init(id: "378", title: "Catalyst · Closed Payout", role: .catalyst) { p in
                AnyView(CatalystClosedPayoutScreen(theme: p, loadId: BrokerNavContext.latestLoadId, onViewSettlement: {}, onDone: {}))
            }
        )
        // 2026-05-22 — Catalyst CV379-CV382 M-05 bidding quartet.
        // Enum-driven shared body; loads.getById drives every value.
        list.append(.init(id: "379", title: "Catalyst · M-05 First Bid",     role: .catalyst) { p in AnyView(CatalystM05FirstBidScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) })
        list.append(.init(id: "380", title: "Catalyst · M-05 Competing Quote", role: .catalyst) { p in AnyView(CatalystM05CompetingQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) })
        list.append(.init(id: "381", title: "Catalyst · M-05 Third Quote",   role: .catalyst) { p in AnyView(CatalystM05ThirdQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) })
        list.append(.init(id: "382", title: "Catalyst · M-05 Awarded Aurora", role: .catalyst) { p in AnyView(CatalystM05AwardedAuroraScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) })
        // 2026-05-29 — Catalyst growth band 391-398 (port wave 13).
        // Bespoke ports of `03 Catalyst/Code/` canonical bricks, wired to real
        // routers (detention, documentManagement, rateSheet) with honest // WIRE:
        // markers where no iOS client method exists yet. Role-prefixed Cat391-Cat398 ids.
        list.append(.init(id: "Cat391", title: "Catalyst · Detention Alerts",       role: .catalyst) { p in AnyView(CatalystDetentionAlertsScreen(theme: p)) })
        list.append(.init(id: "Cat392", title: "Catalyst · Cargo Insurance",        role: .catalyst) { p in AnyView(CatalystCargoInsuranceScreen(theme: p)) })
        list.append(.init(id: "Cat393", title: "Catalyst · Document Ingest",        role: .catalyst) { p in AnyView(CatalystDocumentIngestScreen(theme: p)) })
        list.append(.init(id: "Cat394", title: "Catalyst · Factoring",             role: .catalyst) { p in AnyView(CatalystFactoringScreen(theme: p)) })
        list.append(.init(id: "Cat395", title: "Catalyst · Fuel Surcharge Schedule", role: .catalyst) { p in AnyView(CatalystFuelSurchargeScheduleScreen(theme: p)) })
        list.append(.init(id: "Cat396", title: "Catalyst · Lane Rate Sheet",        role: .catalyst) { p in AnyView(CatalystLaneRateSheetScreen(theme: p)) })
        list.append(.init(id: "Cat397", title: "Catalyst · Carrier Tier",           role: .catalyst) { p in AnyView(CatalystCarrierTierScreen(theme: p)) })
        list.append(.init(id: "Cat398", title: "Catalyst · Backhaul Optimizer",     role: .catalyst) { p in AnyView(CatalystBackhaulOptimizerScreen(theme: p)) })
        // 2026-04-27 — eusotrip-killers 134th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Second Catalyst-track brick lands in production. The Matches
        // nav slot on 500's bottom-nav (and the Active Matches card's
        // "View all" CTA) now route to a real production surface
        // instead of a `RolePlaceholderScreen` stub. Backed by
        // `catalysts.getActiveMatches` via `CatalystActiveMatchesStore`
        // — see `501_CatalystMatches.swift` header for the full
        // doctrine and SpectraMatch fit-score envelope reframing
        // (Broker `targetRate` -> Catalyst `bestFitScore`, Broker
        // `respondingCarriers` -> Catalyst `candidateCount`, Broker
        // `shipper` -> Catalyst `agentName`). Closes the Catalyst
        // role's second-screen-depth track and brings the 24-role
        // 3-screen-per-role expansion track from 22 -> 21 remaining.
        // The 502_CatalystMatchDetail brick replaces the prior
        // `matchDetailComingSoonSheet` placeholder with a real
        // production surface (see registry row "502" below — shipped
        // 2026-04-27 in the 136th firing). Both row tap and 500's
        // "View all" CTA now route to live data per §13 no-fake-data
        // doctrine.
        list.append(
            .init(id: "501", title: "Catalyst · Matches", role: .catalyst) { p in
                AnyView(CatalystMatchesScreen(theme: p))
            }
        )
        // 2026-04-27 — eusotrip-killers 136th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Third Catalyst-track brick lands in production. The row tap
        // on 501's match board (and any deep-link landing on a
        // specific match) now route to a real production detail
        // surface instead of an `EusoEmptyState(comingSoon:)`
        // placeholder. Backed by `loads.getById` via
        // `CatalystMatchDetailStore` (LiveDataStores.swift) — same
        // procedure already powering 205 / 302 / 402; the role
        // distinction is in framing only. The catalyst reframes
        // "load" as "match" and emphasises SpectraMatch fit score,
        // candidate count, and agent-in-the-loop rather than tender
        // rate spread or driver assignment. Candidate shortlist +
        // override-to-manual CTA render as honest placeholders until
        // `catalysts.getMatchCandidates` / `catalysts.overrideMatch`
        // ship server-side. Closes the Catalyst role's third-screen-
        // depth track and brings the 24-role 3-screen-per-role
        // expansion track from 21 -> 20 remaining. Catalyst now
        // reaches structural parity with Carrier (300+301+302) and
        // Broker (400+401+402): three production screens per role.
        list.append(
            .init(id: "502", title: "Catalyst · Match Detail", role: .catalyst) { p in
                AnyView(
                    CatalystMatchDetailScreen(
                        theme: p,
                        matchId: "0"
                    )
                )
            }
        )
        // 2026-05-06 — Catalyst EusoTicket Renderer (Figma 313 light +
        // dark) lands. Pixel-faithful port of the Catalyst-side BOL ·
        // POD · run-ticket · haul-receipt rendering surface — sole-driver
        // Catalyst (Eusotrans LLC · Michael Eusorone) reviews the as-
        // rendered EusoTicket document for the active load before
        // dispatching to the shipper-of-record (Diego Usoro · Eusorone
        // Technologies) and the receiver. Wired to `loads.getById` for
        // the previewed load + `eusoTicket.generateBOLPDF` on Send;
        // QR uses the canonical `EusoQRView` (kind `.eusoTicket(.bol)`,
        // role `.carrier`) so the same QR scans into the iOS deep-link
        // handler and the web router.
        list.append(
            .init(id: "313", title: "Catalyst · EusoTicket Renderer", role: .catalyst) { p in
                AnyView(CatalystEusoTicketRendererScreen(theme: p, loadId: "0"))
            }
        )
        // 2026-05-06 — Catalyst Fleet Drivers (Figma 304 light + dark)
        // lands. The carrier's driver roster — canonical Catalyst↔Driver
        // relationship lens. Hero card for the active driver +
        // endorsements strip + DQ files quarter strip + onboarding/DQ
        // alerts feed + additional drivers list. Wired to
        // `catalysts.getMyDrivers` (real DB joins for status / current
        // load / hours remaining / GPS location), plus the active hero
        // adjuncts via `driverQualification.getOverview`,
        // `driverQualification.getDocuments`, and
        // `driverQualification.getExpiringItems` (60-day company-scoped
        // expiry watchlist, filtered to the hero driver). All four
        // procedures are real — no stubs / no mock data; tiles collapse
        // to "—" when a per-driver datum isn't yet on file.
        list.append(
            .init(id: "304", title: "Catalyst · Fleet · Drivers", role: .catalyst) { p in
                AnyView(CatalystFleetDriversScreen(theme: p))
            }
        )
        // 2026-05-06 — Catalyst Load Detail (Figma 305 light + dark)
        // lands. FLAGSHIP Catalyst-side load detail mirroring 205
        // ShipperLoadDetail with two Catalyst-specific delta cards
        // added per §57.4 / §58.4 candidate-queue lead doctrine:
        //
        //   • ASSIGNMENT card — joins the live `loads.driverId` ↔
        //     `catalysts.getMyDrivers` row so HOS countdown + status
        //     pill + driver location paint with REAL data, never a
        //     synthetic label. REASSIGN action emits the canonical
        //     `eusoCatalystReassignDriver` notification for the
        //     dispatch reassign flow. Honest "Pending assignment" /
        //     "Cross-fleet relay" empty states when the driver isn't
        //     in the catalyst's roster.
        //   • SHIPPER-OF-RECORD card — Diego Usoro · Eusorone
        //     Technologies for §11 flagship companyId 1; generic
        //     "Shipper #N" line for any other shipperId — never a
        //     fabricated name.
        //
        // Wired to `loads.getById` for the load envelope and
        // `catalysts.getMyDrivers` for the assigned driver row. 8-stage
        // canonical lifecycle strip with status-aware progress.
        list.append(
            .init(id: "305", title: "Catalyst · Load Detail", role: .catalyst) { p in
                AnyView(CatalystLoadDetailScreen(theme: p, loadId: "0"))
            }
        )
        // 2026-05-06 — Catalyst Driver Performance Scorecard (Figma 320
        // light + dark) lands. The catalyst→driver scorecard surface —
        // same letter-grade engine as 213 Catalyst Scorecard (shipper→
        // catalyst vantage), pivoted to the catalyst→driver vantage
        // per §63.6 doctrine. Closes the cross-track scorecard symmetry:
        // shippers grade catalysts, catalysts grade drivers, both with
        // the same A+/A/A−/B-tier engine. Wired to the REAL
        // `drivers.getPerformanceMetrics(driverId, period)` (drivers.ts:544)
        // which joins loads + inspections + hosLogs + fuelTransactions
        // for the named period. The composite letter grade is computed
        // client-side per §9.1 formula (on-time × 0.5 + completion × 0.3
        // + log₁₀(loads+1)/log₁₀(50) × 0.2). Defaults to the catalyst's
        // primary driver via `catalysts.getMyDrivers` when no driverId
        // is passed. Honest empty / zero envelope when the driver has no
        // loads in the window — never fabricated metrics.
        list.append(
            .init(id: "320", title: "Catalyst · Driver Scorecard", role: .catalyst) { p in
                AnyView(CatalystDriverScorecardScreen(theme: p, driverId: ""))
            }
        )
        // 2026-05-06 — Catalyst Driver Compliance (Figma 326 light +
        // dark) lands. Per-driver federal compliance dashboard — pairs
        // with 317 Catalyst Compliance (carrier-level aggregate) at the
        // per-driver scanline. Five federal regulatory axes: CSA BASIC
        // · §395 HOS · MCSAP roadside · §391.41 Medical · §382 Drug
        // pool. Wired to REAL endpoints — every status pill is
        // computed from the driver's own tables: compliance status +
        // safety from `compliance.getDriverComplianceList`, DQ score
        // from `driverQualification.getOverview`, expiry windows from
        // `driverQualification.getExpiringItems`, drug-screen presence
        // from `driverQualification.getDocuments`, HOS + roadside pass
        // rates from `drivers.getPerformanceMetrics`. When a federal
        // axis isn't yet wired iOS-side (CSA carrier-level), the row
        // surfaces "Not yet wired · check 317 compliance home" rather
        // than a fabricated value. §382 row cross-references the same
        // drug-test document records 322 Documents and 325 Onboarding
        // read — three surfaces over the §382 trinity.
        list.append(
            .init(id: "326", title: "Catalyst · Driver Compliance", role: .catalyst) { p in
                AnyView(CatalystDriverComplianceScreen(theme: p, driverId: ""))
            }
        )
        // 2026-05-21 — eusotrip-killers screen-porting sweep. iOS port of
        // web CommissionEnginePage.tsx. Server contract was broken on the
        // web (called `commissionEngine.calculate` which doesn't exist);
        // the paired web commit fixes it to `calculateSplit` with the
        // right field names so both surfaces read off the same shape.
        list.append(
            .init(id: "331", title: "Catalyst · Commission Engine", role: .catalyst) { p in
                AnyView(CatalystCommissionEngineScreen(theme: p))
            }
        )
        // 2026-05-21 — eusotrip-killers SVG-faithful port. Catalyst
        // Fleet · Vehicles (303). Wire contract: vehicles.list +
        // iftaCalculator.calculateQuarter × 4 + maintenance.{getUpcoming,
        // getAlerts}. Bottom nav frozen per doctrine — content only.
        list.append(.init(id: "301", title: "Catalyst · Dispatch Board", role: .catalyst) { p in AnyView(CatalystDispatchBoardScreen(theme: p)) })
        list.append(.init(id: "302", title: "Catalyst · Profile",        role: .catalyst) { p in AnyView(CatalystProfileScreen(theme: p)) })
        list.append(.init(id: "303", title: "Catalyst · Fleet · Vehicles", role: .catalyst) { p in AnyView(CatalystFleetVehiclesScreen(theme: p)) })
        list.append(.init(id: "309", title: "Catalyst · Bids Outbound",  role: .catalyst) { p in AnyView(CatalystBidsOutboundScreen(theme: p)) })
        list.append(.init(id: "318", title: "Catalyst · RFP Inbound",    role: .catalyst) { p in AnyView(CatalystRFPInboundScreen(theme: p)) })
        list.append(.init(id: "307", title: "Catalyst · Reports",          role: .catalyst) { p in AnyView(CatalystReportsScreen(theme: p)) })
        list.append(.init(id: "310", title: "Catalyst · Driver Pay Setup", role: .catalyst) { p in AnyView(CatalystDriverPaySetupScreen(theme: p)) })
        list.append(.init(id: "311", title: "Catalyst · Settings",         role: .catalyst) { p in AnyView(CatalystSettingsScreen(theme: p)) })
        list.append(.init(id: "323", title: "Catalyst · Driver Performance", role: .catalyst) { p in
            AnyView(CatalystDriverPerformanceScreen(theme: p, driverId: "001"))
        })
        list.append(.init(id: "324", title: "Catalyst · Driver Ledger",    role: .catalyst) { p in
            AnyView(CatalystDriverSettlementLedgerScreen(theme: p, driverId: "001", driverName: "Owner-op"))
        })
        // 2026-05-21 — closes Catalyst 300-326 SVG range.
        list.append(.init(id: "315", title: "Catalyst · Lease-on / Lease-out", role: .catalyst) { p in AnyView(CatalystLeaseOnOutScreen(theme: p)) })
        list.append(.init(id: "316", title: "Catalyst · Drive Mode",          role: .catalyst) { p in AnyView(CatalystDriveModeScreen(theme: p)) })
        list.append(.init(id: "325", title: "Catalyst · Driver Onboarding",   role: .catalyst) { p in
            AnyView(CatalystDriverOnboardingScreen(theme: p, driverId: "001", driverName: "Owner-op"))
        })
        // 2026-05-21 — Shipper lifecycle counterparty SVG batch.
        list.append(.init(id: "241", title: "Shipper · Counter Review",      role: .shipper) { p in
            AnyView(ShipperCounterReviewScreen(theme: p, loadId: "0"))
        })
        list.append(.init(id: "242", title: "Shipper · Awarded Confirmation", role: .shipper) { p in
            AnyView(ShipperAwardedConfirmationScreen(theme: p, loadId: "0"))
        })
        list.append(.init(id: "248", title: "Shipper · POD Receipt",         role: .shipper) { p in
            AnyView(ShipperPODReceiptScreen(theme: p, loadId: "0"))
        })
        // 2026-05-21 — Shipper lifecycle sextet (243-247 + 249).
        list.append(.init(id: "243", title: "Shipper · At Gate",        role: .shipper) { p in AnyView(ShipperAtGateScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "244", title: "Shipper · At Dock",        role: .shipper) { p in AnyView(ShipperAtDockScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "245", title: "Shipper · Departing",      role: .shipper) { p in AnyView(ShipperDepartingScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "246", title: "Shipper · Pre-Delivery",   role: .shipper) { p in AnyView(ShipperPreDeliveryScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "247", title: "Shipper · At Delivery",    role: .shipper) { p in AnyView(ShipperAtDeliveryScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "249", title: "Shipper · Load Closed",    role: .shipper) { p in AnyView(ShipperLoadClosedScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "306", title: "Catalyst · Driver Payroll", role: .catalyst) { p in AnyView(CatalystDriverPayrollScreen(theme: p)) })
        list.append(.init(id: "308", title: "Catalyst · Authority + Insurance", role: .catalyst) { p in AnyView(CatalystAuthorityInsuranceScreen(theme: p)) })
        list.append(.init(id: "312", title: "Catalyst · Hot Zones",        role: .catalyst) { p in AnyView(CatalystHotZonesScreen(theme: p)) })
        list.append(.init(id: "314", title: "Catalyst · Maintenance Zeun", role: .catalyst) { p in AnyView(CatalystMaintenanceZeunScreen(theme: p)) })
        list.append(.init(id: "319", title: "Catalyst · Wallet",           role: .catalyst) { p in AnyView(CatalystWalletScreen(theme: p)) })
        // 2026-05-21 — Load board trio (web → iOS port).
        list.append(.init(id: "340", title: "Catalyst · Matched Loads",  role: .catalyst) { p in AnyView(MatchedLoadsScreen(theme: p)) })
        list.append(.init(id: "341", title: "Catalyst · Find Loads",     role: .catalyst) { p in AnyView(FindLoadsScreen(theme: p)) })
        list.append(.init(id: "342", title: "Catalyst · Assigned Loads", role: .catalyst) { p in AnyView(AssignedLoadsScreen(theme: p)) })
        // 2026-05-06 — Catalyst Driver Documents (Figma 322 light + dark)
        // lands. The catalyst-side document vault for a single driver —
        // the file binaries behind 321 Driver Profile's credential pills
        // (CDL · MEDICAL · DQ FILE · MVR/DRUG). Wired to REAL endpoints:
        // `driverQualification.getDocuments(driverId)` for the file
        // list (newest first) and `driverQualification.getOverview` for
        // the KPI strip (valid / expiring / expired / DQ score).
        // Filter chips bucket via type-name matchers — same matcher
        // 326 Driver Compliance uses for its federal axis status,
        // keeping the §382 / §391.41 / §383 taxonomy consistent across
        // all three §391 surfaces. Empty / loading / per-filter-empty
        // states are honest — no fabricated PDF placeholder rows ever.
        list.append(
            .init(id: "322", title: "Catalyst · Driver Documents", role: .catalyst) { p in
                AnyView(CatalystDriverDocumentsScreen(theme: p, driverId: ""))
            }
        )
        // 2026-05-06 — Catalyst Driver Profile (Figma 321 light + dark)
        // lands. The catalyst-side detail view of one driver — the
        // canonical catalyst→driver record. Pairs with 304 Fleet
        // Drivers (roster) and 322 Driver Documents (file vault).
        // Wired to REAL `drivers.getById(id)` (drivers.ts:378) for the
        // full profile envelope (CDL · medical · current load · monthly
        // stats), `catalysts.getMyDrivers` for the live HOS countdown +
        // GPS location, and `driverQualification.getOverview` for the
        // DQ compliance score. Tap-to-call / SMS / email use real
        // `tel:` / `sms:` / `mailto:` URLs against the live
        // `users.phone` and `users.email` columns. Quick-actions row
        // navigates to 322 (Documents), 326 (Compliance), 320
        // (Scorecard) — closing the catalyst→driver deep-dive trio.
        list.append(
            .init(id: "321", title: "Catalyst · Driver Profile", role: .catalyst) { p in
                AnyView(CatalystDriverProfileScreen(theme: p, driverId: ""))
            }
        )
        // 2026-05-06 — Catalyst Compliance (carrier-level companion to
        // 326 driver compliance) lands. Wired to REAL endpoints:
        // `compliance.getCatalystCompliance` (companies row → score +
        // MC + DOT + insurance + safety rating), `fmcsa.lookupSelf`
        // (live FMCSA SAFER pull cached via Redis + MySQL), and
        // `compliance.getDriverComplianceList` for the per-driver
        // roster strip. Closes the empty state I left on 326 ("Not yet
        // wired · check 317 carrier compliance home"). Action ribbon
        // surfaces the next remediation: insurance renewal → SAFER
        // remediation → MC filing → driver gaps → quarterly report.
        list.append(
            .init(id: "317", title: "Catalyst · Compliance", role: .catalyst) { p in
                AnyView(CatalystComplianceScreen(theme: p))
            }
        )
        // 2026-04-25 — eusotrip-killers 103rd firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // First real Escort-track brick lands in production. Lifts
        // id "600" out of the `#if DEBUG` placeholder block below so
        // non-debug builds also get the Escort Home surface. Backed
        // by `escorts.{getDashboardStats,getActiveAssignments,
        // getLoadsRequiringAttention,getRecentAssignments}` — see
        // `600_EscortHome.swift` header for the full doctrine and
        // store wire-up. Escort is the regulated-corridor pilot-car /
        // safety-escort operator role per §16 compliance-safety slice
        // (escortOverview, escort_* tables, bridge clearance); the
        // home re-frames the four-card hierarchy around live
        // assignment flow + corridor coverage rather than match flow,
        // so `ActiveAssignments` replaces the Catalyst's
        // `ActiveMatches` slot and `revenueThisWeek` replaces
        // `gmvThisWeek`.
        list.append(
            .init(id: "600", title: "Escort · Home", role: .escort) { p in
                AnyView(EscortHomeScreen(theme: p))
            }
        )
        // 2026-04-27 — eusotrip-killers 147th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Second real Escort-track brick lands. The 600 home's
        // active-assignment row tap (previously a no-op) now routes
        // to a real production detail surface — `601_EscortAssignmentDetail`.
        // Backed by `EscortAssignmentDetailStore` (LiveDataStores.swift)
        // → `escorts.getActiveAssignmentDetail` (input `{ id: string }`)
        // for the read and `escorts.confirmRoute` for the route-commit
        // mutation. Every blank server field renders as an em-dash
        // sentinel per §13 no-fake-data doctrine. The CTA disables
        // while the detail fetch is loading, while the mutation is
        // in flight, and once `routeConfirmed: true` flips. Closes
        // the Escort role's two-screen-depth track and brings the
        // 24-role 3-screen-per-role expansion track one step further.
        // Escort now reaches partial parity with Carrier (300+301+302),
        // Broker (400+401+402), and Catalyst (500+501+502): two
        // production screens shipped with the home → detail tap path
        // wired end-to-end.
        list.append(
            .init(id: "601", title: "Escort · Assignment Detail", role: .escort) { p in
                AnyView(
                    EscortAssignmentDetailScreen(
                        theme: p,
                        assignmentId: "0"
                    )
                )
            }
        )
        // 2026-04-27 — eusotrip-killers 159th firing
        // (Cowork-mode autonomous run, scheduled-task `eusotrip-killers`):
        // Third real Escort-track brick lands. Brings Escort to
        // three-screen depth, achieving the "all 8 of 8 non-driver
        // roles ≥ 3-deep" milestone the 2027 motivation directive
        // points at. Drilled into from
        // 601_EscortAssignmentDetail's "View corridor →" sheet CTA —
        // exposes the full corridor topology (legs + milestones +
        // geofences + lead/chase pairing + KPIs) in a single
        // server-shaped envelope. Backend wiring:
        // `escorts.getCorridor` (input `{ id: string }`) — single
        // read, server-shaped payload mirroring `terminals.getYardMap`
        // convention. If the parallel router has not landed yet, the
        // store resolves to `.error` and the screen surfaces an
        // honest retry banner. No fixture data ever — em-dash
        // sentinels for any nullable field on the wire (doctrine §11
        // + `MockDataGuard`). Closes the role-by-role 3-deep parity
        // gap from the 158th firing report (Escort was the only
        // 2-deep non-driver role before this brick).
        list.append(
            .init(id: "602", title: "Escort · Corridor Map", role: .escort) { p in
                AnyView(
                    EscortCorridorMapScreen(
                        theme: p,
                        assignmentId: "0"
                    )
                )
            }
        )

        // 2026-05-01 — lifted Terminal 700-702 + Admin 800-803 OUT
        // of the previous `#if DEBUG` block. Both role tracks have
        // shipped real bricks against real backend procedures
        // (`terminals.*` / `admin.*`); leaving the registry entries
        // DEBUG-only meant signed-in Terminal Manager + Admin users
        // saw an empty `ScreenRegistry.forRole(.terminal/.admin)` in
        // Release builds, so `RoleSurfaceRouter`'s
        // TerminalSurface / AdminSurface fell back to mounting just
        // the home screen with no navigability. They now always
        // register so the surfaces can navigate the full set in
        // Release. Same fix landed for Compliance below (900-902).
        list.append(contentsOf: [
            // 700 Terminal Home — first real brick on the Terminal Manager
            // role track (107th eusotrip-killers firing). Replaced the
            // RolePlaceholderScreen stub. Backend wiring: `terminals.*`
            // tRPC namespace; if the parallel router has not landed yet,
            // every card resolves to `.error` and offers retry — no
            // placeholder data is ever shown (doctrine §11 + MockDataGuard).
            .init(id: "700", title: "Terminal · Home",                role: .terminal) { p in AnyView(TerminalHomeScreen(theme: p)) },
            // 701 Terminal · Gate Queue — second real brick on the Terminal
            // Manager role track (150th eusotrip-killers firing). The 700
            // home's "ACTIVE MOVEMENTS" section header now routes to this
            // deep gate-queue surface instead of being read-only chrome.
            // Backend: `terminals.getGateQueue` (read) + `terminals.assignDock`
            // (per-row mutation). Each row owns its own in-flight + error
            // state so a failed assign on row B doesn't disturb row A's
            // idle CTA. Closes the Terminal role's two-screen-depth track,
            // bringing parity with Escort 600 → 601 (147th firing).
            .init(id: "701", title: "Terminal · Gate Queue",          role: .terminal) { p in AnyView(TerminalGateQueueScreen(theme: p)) },
            // 702 Terminal · Yard Map — third real brick on the Terminal
            // Manager role track (154th eusotrip-killers firing). Drilled
            // into from 700_TerminalHome's "Yard" trailing nav slot —
            // exposes the full yard occupancy by zone with each slot
            // rendered as a tile (free / occupied) and a per-slot
            // "Release" mutation when a truck departs and the slot is
            // clear. Backend: `terminals.getYardMap` (read) +
            // `terminals.releaseSlot` (per-slot mutation). Each slot
            // owns its own in-flight + error state. Brings Terminal to
            // three-screen depth, parity with the upcoming 3-deep
            // tracks for Escort/Admin (and overshooting Broker/Catalyst
            // until they reach 3).
            .init(id: "702", title: "Terminal · Yard Map",            role: .terminal) { p in AnyView(TerminalYardMapScreen(theme: p)) },
            // 800 Admin Home — first real brick on the Admin role track
            // (108th eusotrip-killers firing). Replaced the
            // RolePlaceholderScreen stub. Backend wiring: `admin.*` tRPC
            // namespace; if the parallel router has not landed yet,
            // every card resolves to `.error` and offers retry — no
            // placeholder data is ever shown (doctrine §11 + MockDataGuard).
            // This brick closes the role-anchor sweep so all 8 of 24
            // distinct role surfaces have at least one shipped screen.
            .init(id: "800", title: "Admin · Home",                   role: .admin)    { p in AnyView(AdminHomeScreen(theme: p)) },
            // 801 — Admin · Control Tower (156th eusotrip-killers firing).
            // Closes the 800→802 leapfrog gap. Third screen on the
            // Admin role track (800s) — drilled into from 800's new
            // "PLATFORM CONTROL TOWER" section header via the
            // "Open tower →" CTA. Reads
            // `admin.controlTower.getOverview` +
            // `admin.controlTower.getExceptions` through
            // `AdminControlTowerOverviewStore` +
            // `AdminControlTowerExceptionsStore` — never any fixture
            // data; if the backend hasn't shipped these procedures,
            // the stores resolve to `.error` and the screen surfaces
            // an honest retry banner (doctrine §11 + MockDataGuard).
            // Brings Admin to three-screen depth, parity with Terminal
            // 700/701/702 and Catalyst 500/501/502.
            .init(id: "801", title: "Admin · Control Tower",          role: .admin)    { p in AnyView(AdminControlTowerScreen(theme: p)) },
            // 802 — Admin · Tenants (151st eusotrip-killers firing).
            // Second screen on the Admin role track (800s). Drilled
            // into from 800's "ACTIVE TENANTS" section header via the
            // "View all →" CTA. Reads `admin.listTenants` through
            // `AdminTenantsStore` — never any fixture data; if the
            // backend hasn't shipped the procedure, the store
            // resolves to `.error` and the screen surfaces a retry
            // banner (doctrine §11 + MockDataGuard). Brings Admin to
            // two-screen depth, parity with Terminal/Escort/Catalyst/
            // Carrier/Broker.
            .init(id: "802", title: "Admin · Tenants",                role: .admin)    { p in AnyView(AdminTenantsScreen(theme: p)) },
            // 803 — Admin · Tenant Detail (161st eusotrip-killers firing).
            // Fourth screen on the Admin role track (800s). Drilled
            // into from 802's per-row "View detail →" CTA via a
            // `.sheet([.large])` presenter. Reads `admin.getTenantDetail`
            // through `AdminTenantDetailStore` — every nullable column
            // surfaces as a neutral em-dash, every empty sub-section
            // (contacts / usage / audit) surfaces an honest empty
            // sub-card. No fixture data ever (doctrine §11 +
            // MockDataGuard); if the backend hasn't shipped the
            // procedure, the store resolves to `.error` and the
            // screen offers retry. Lifts Admin to 4-deep parity
            // with Driver / Shipper / Carrier. The registry-style
            // wrapper passes a blank tenant id so the surface
            // honestly renders the empty / loading state when
            // accessed via the dev-chrome next/prev bar; the real
            // production path is 802 → sheet → AdminTenantDetail
            // (which carries the row's tenant id + preview hint).
            .init(id: "803", title: "Admin · Tenant Detail",          role: .admin)    { p in AnyView(AdminTenantDetailScreen(theme: p)) },

            // Compliance Officer surface (900-902). Was previously
            // shelved behind `#if false` in the source files due to
            // an `OrbeSang.State.alert` reference (the canonical enum
            // ships `.idle / .listening / .thinking`). Resurrected
            // 2026-05-01; orb cue mapped to `.idle` with the violation
            // severity carried by per-row chips.
            .init(id: "900", title: "Compliance · Home",             role: .compliance) { p in AnyView(ComplianceOfficerHomeScreen(theme: p)) },
            .init(id: "901", title: "Compliance · Expiring Docs",    role: .compliance) { p in AnyView(ComplianceExpiringDocsScreen(theme: p)) },
            .init(id: "902", title: "Compliance · Violations",       role: .compliance) { p in AnyView(ComplianceViolationsScreen(theme: p)) },

            // Dispatch surface (Dpch700-Dpch712). The 13 Dispatch
            // files were previously 10 shelved (#if false wrap due to
            // design-token drift against an older `Theme.Palette` /
            // `EType` / `OrbeSang.State`) + 3 in-build but
            // unregistered. Tokens normalized 2026-05-01 and all 13
            // landed in the registry with role: .dispatch. The slot
            // numbers (700-712) collide with Terminal 700-702 in the
            // Dispatch source files — the registry IDs prefix with
            // `Dpch` to disambiguate (since `ScreenRegistry.forRole`
            // filters by role, the IDs only need to be unique
            // within their own role bucket; the prefix makes the
            // disambiguation visible to anyone reading the registry
            // directly). Each takes `theme: Theme.Palette` only.
            .init(id: "Dpch700", title: "Dispatch · Home",             role: .dispatch) { p in AnyView(DispatchHomeScreen(theme: p)) },
            .init(id: "Dpch701", title: "Dispatch · Driver Board",     role: .dispatch) { p in AnyView(DispatchDriverBoardScreen(theme: p)) },
            .init(id: "Dpch702", title: "Dispatch · Load Assignment",  role: .dispatch) { p in AnyView(DispatchLoadAssignmentScreen(theme: p)) },
            .init(id: "Dpch703", title: "Dispatch · Exception Triage", role: .dispatch) { p in AnyView(DispatchExceptionTriageScreen(theme: p)) },
            .init(id: "Dpch704", title: "Dispatch · HOS Alerts",       role: .dispatch) { p in AnyView(DispatchHOSAlertsScreen(theme: p)) },
            .init(id: "Dpch705", title: "Dispatch · Route Optimization", role: .dispatch) { p in AnyView(DispatchRouteOptimizationScreen(theme: p)) },
            .init(id: "Dpch706", title: "Dispatch · Driver Chat",      role: .dispatch) { p in AnyView(DispatchDriverChatScreen(theme: p)) },
            .init(id: "Dpch707", title: "Dispatch · Daily KPI",        role: .dispatch) { p in AnyView(DispatchDailyKPIScreen(theme: p)) },
            .init(id: "Dpch708", title: "Dispatch · Kanban Board",     role: .dispatch) { p in AnyView(DispatchKanbanBoardScreen(theme: p)) },
            .init(id: "Dpch709", title: "Dispatch · Bulk Upload Kanban", role: .dispatch) { p in AnyView(DispatchBulkUploadKanbanScreen(theme: p)) },
            .init(id: "Dpch710", title: "Dispatch · Run Ticket Capture", role: .dispatch) { p in AnyView(DispatchRunTicketCaptureScreen(theme: p)) },
            .init(id: "Dpch711", title: "Dispatch · Price Book",       role: .dispatch) { p in AnyView(DispatchPriceBookScreen(theme: p)) },
            .init(id: "Dpch712", title: "Dispatch · Reports Hub",      role: .dispatch) { p in AnyView(DispatchReportsHubScreen(theme: p)) },
            // 2026-05-21 dead-button fix — dedicated Dispatch Me hub. The
            // bottom-nav "Me" slot used to map to Dpch700 (Home), a
            // functional dead-end. Now points here. Links to all 13
            // registered dispatch screens via .eusoDispatchNavSwap.
            .init(id: "Dpch713", title: "Dispatch · Me",               role: .dispatch) { p in AnyView(DispatchMeScreen(theme: p)) },
            // 2026-05-21 — eusotrip-killers screen-porting sweep.
            // Three dispatch flagship screens land bundled in one
            // Swift file (Dpch714_DispatchTrio.swift): Command Center,
            // Fleet Map, Performance.
            .init(id: "Dpch714", title: "Dispatch · Command Center",   role: .dispatch) { p in AnyView(DispatchCommandCenterScreen(theme: p)) },
            .init(id: "Dpch715", title: "Dispatch · Fleet Map",        role: .dispatch) { p in AnyView(DispatchFleetMapScreen(theme: p)) },
            .init(id: "Dpch716", title: "Dispatch · Performance",      role: .dispatch) { p in AnyView(DispatchPerformanceScreen(theme: p)) },
            // 2026-05-21 — SVG-port sweep (403/405/411).
            .init(id: "Dpch720", title: "Dispatch · Tender Queue",     role: .dispatch) { p in AnyView(DispatcherTenderQueueScreen(theme: p)) },
            .init(id: "Dpch721", title: "Dispatch · Comms Hub",        role: .dispatch) { p in AnyView(DispatcherCommsHubScreen(theme: p)) },
            .init(id: "Dpch722", title: "Dispatch · BOL Mismatch",     role: .dispatch) { p in AnyView(DispatcherBOLMismatchScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Dispatcher exception flow quartet (412/415/418/419).
            .init(id: "Dpch724", title: "Dispatch · HOS Reassignment",  role: .dispatch) { p in AnyView(DispatcherHOSReassignmentScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch725", title: "Dispatch · Cancel Load",       role: .dispatch) { p in AnyView(DispatcherCancelLoadWizardScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch726", title: "Dispatch · Late Pickup",       role: .dispatch) { p in AnyView(DispatcherLatePickupScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch727", title: "Dispatch · Dock Mismatch",     role: .dispatch) { p in AnyView(DispatcherDockMismatchScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Dispatcher ops quartet (406/407/408/414).
            .init(id: "Dpch730", title: "Dispatch · Yard Slots",         role: .dispatch) { p in AnyView(DispatcherYardSlotsScreen(theme: p)) },
            .init(id: "Dpch731", title: "Dispatch · Reassignment Sheet", role: .dispatch) { p in AnyView(DispatcherReassignmentSheetScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch732", title: "Dispatch · Quick-Tender",       role: .dispatch) { p in AnyView(DispatcherQuickTenderScreen(theme: p)) },
            .init(id: "Dpch733", title: "Dispatch · Escort Republish",   role: .dispatch) { p in AnyView(DispatcherEscortRepublishScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Dispatcher control quartet (409/413/416/417).
            .init(id: "Dpch734", title: "Dispatch · Settings",            role: .dispatch) { p in AnyView(DispatcherSettingsScreen(theme: p)) },
            .init(id: "Dpch735", title: "Dispatch · Weather Reroute",     role: .dispatch) { p in AnyView(DispatcherWeatherRerouteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch736", title: "Dispatch · Reload Offer",        role: .dispatch) { p in AnyView(DispatcherReloadOfferScreen(theme: p, driverId: BrokerNavContext.latestCatalystId)) },
            .init(id: "Dpch737", title: "Dispatch · Fuel-Policy Override",role: .dispatch) { p in AnyView(DispatcherFuelPolicyOverrideScreen(theme: p, driverId: BrokerNavContext.latestCatalystId)) },
            // 2026-05-21 — Dispatcher driver-detail octet (SVG 420-427).
            .init(id: "Dpch740", title: "Dispatch · Driver Review",       role: .dispatch) { p in AnyView(DispatcherDriverReviewScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch741", title: "Dispatch · Driver Lane",         role: .dispatch) { p in AnyView(DispatcherDriverLaneDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch742", title: "Dispatch · Driver Incident Log", role: .dispatch) { p in AnyView(DispatcherDriverIncidentLogScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch743", title: "Dispatch · Driver Performance",  role: .dispatch) { p in AnyView(DispatcherDriverPerformanceDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch744", title: "Dispatch · Driver HOS",          role: .dispatch) { p in AnyView(DispatcherDriverHOSDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch745", title: "Dispatch · Driver Onboarding",   role: .dispatch) { p in AnyView(DispatcherDriverOnboardingStepDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch746", title: "Dispatch · Driver Compliance",   role: .dispatch) { p in AnyView(DispatcherDriverComplianceRowDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            .init(id: "Dpch747", title: "Dispatch · Driver Quarter",      role: .dispatch) { p in AnyView(DispatcherDriverQuarterDetailScreen(theme: p, driverId: BrokerNavContext.latestDriverId)) },
            // 2026-05-21 — Dispatcher shipper-detail octet (SVG 440-447).
            .init(id: "Dpch750", title: "Dispatch · Shipper Review",      role: .dispatch) { p in AnyView(DispatcherShipperReviewScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch751", title: "Dispatch · Shipper Pull-Volume", role: .dispatch) { p in AnyView(DispatcherShipperPullVolumeScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch752", title: "Dispatch · Shipper Tender-Win",  role: .dispatch) { p in AnyView(DispatcherShipperTenderWinScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch753", title: "Dispatch · Shipper Payment",     role: .dispatch) { p in AnyView(DispatcherShipperPaymentBehaviorScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch754", title: "Dispatch · Shipper Lane-Win",    role: .dispatch) { p in AnyView(DispatcherShipperLaneWinScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch755", title: "Dispatch · Shipper Health",      role: .dispatch) { p in AnyView(DispatcherShipperAccountHealthScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch756", title: "Dispatch · Shipper Onboarding",  role: .dispatch) { p in AnyView(DispatcherShipperOnboardingStepScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "Dpch757", title: "Dispatch · Shipper Quarter",     role: .dispatch) { p in AnyView(DispatcherShipperQuarterScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            // 2026-05-21 — Dispatcher vehicle-detail octet (SVG 460-467).
            .init(id: "Dpch760", title: "Dispatch · Vehicle Review",      role: .dispatch) { p in AnyView(DispatcherVehicleReviewScreen(theme: p)) },
            .init(id: "Dpch761", title: "Dispatch · Vehicle Utilization", role: .dispatch) { p in AnyView(DispatcherVehicleUtilizationScreen(theme: p)) },
            .init(id: "Dpch762", title: "Dispatch · Vehicle Maintenance", role: .dispatch) { p in AnyView(DispatcherVehicleMaintenanceScreen(theme: p)) },
            .init(id: "Dpch763", title: "Dispatch · Vehicle On-Time",     role: .dispatch) { p in AnyView(DispatcherVehicleOnTimeScreen(theme: p)) },
            .init(id: "Dpch764", title: "Dispatch · Vehicle Inspection",  role: .dispatch) { p in AnyView(DispatcherVehicleInspectionScreen(theme: p)) },
            .init(id: "Dpch765", title: "Dispatch · Vehicle Deadhead",    role: .dispatch) { p in AnyView(DispatcherVehicleDeadheadScreen(theme: p)) },
            .init(id: "Dpch766", title: "Dispatch · Vehicle Onboarding",  role: .dispatch) { p in AnyView(DispatcherVehicleOnboardingScreen(theme: p)) },
            .init(id: "Dpch767", title: "Dispatch · Vehicle Quarter",     role: .dispatch) { p in AnyView(DispatcherVehicleQuarterScreen(theme: p)) },
            // 2026-05-21 — Dispatcher settlement-detail octet (SVG 500-507).
            .init(id: "Dpch770", title: "Dispatch · Settlement Review",   role: .dispatch) { p in AnyView(DispatcherSettlementReviewScreen(theme: p)) },
            .init(id: "Dpch771", title: "Dispatch · Settlement DSO",      role: .dispatch) { p in AnyView(DispatcherSettlementDSOScreen(theme: p)) },
            .init(id: "Dpch772", title: "Dispatch · Settlement QPAY",     role: .dispatch) { p in AnyView(DispatcherSettlementQPAYScreen(theme: p)) },
            .init(id: "Dpch773", title: "Dispatch · Settlement Ledger",   role: .dispatch) { p in AnyView(DispatcherSettlementOpenLedgerScreen(theme: p)) },
            .init(id: "Dpch774", title: "Dispatch · Settlement Clean",    role: .dispatch) { p in AnyView(DispatcherSettlementCleanRateScreen(theme: p)) },
            .init(id: "Dpch775", title: "Dispatch · Settlement Onboard",  role: .dispatch) { p in AnyView(DispatcherSettlementOnboardingScreen(theme: p)) },
            .init(id: "Dpch776", title: "Dispatch · Settlement Audit",    role: .dispatch) { p in AnyView(DispatcherSettlementComplianceScreen(theme: p)) },
            .init(id: "Dpch777", title: "Dispatch · Settlement Quarter",  role: .dispatch) { p in AnyView(DispatcherSettlementQuarterScreen(theme: p)) },
            // 2026-05-21 — Dispatcher Comms-detail octet (SVG 480-487).
            .init(id: "Dpch780", title: "Dispatch · Comms Review",        role: .dispatch) { p in AnyView(DispatcherCommsReviewScreen(theme: p)) },
            .init(id: "Dpch781", title: "Dispatch · Comms Response",      role: .dispatch) { p in AnyView(DispatcherCommsResponseTimeScreen(theme: p)) },
            .init(id: "Dpch782", title: "Dispatch · Comms SLA",           role: .dispatch) { p in AnyView(DispatcherCommsSLAScreen(theme: p)) },
            .init(id: "Dpch783", title: "Dispatch · Comms Escalation",    role: .dispatch) { p in AnyView(DispatcherCommsEscalationScreen(theme: p)) },
            .init(id: "Dpch784", title: "Dispatch · Comms Closure",       role: .dispatch) { p in AnyView(DispatcherCommsClosureScreen(theme: p)) },
            .init(id: "Dpch785", title: "Dispatch · Comms Volume",        role: .dispatch) { p in AnyView(DispatcherCommsVolumeScreen(theme: p)) },
            .init(id: "Dpch786", title: "Dispatch · Comms FTR",           role: .dispatch) { p in AnyView(DispatcherCommsFTRScreen(theme: p)) },
            .init(id: "Dpch787", title: "Dispatch · Comms Quarter",       role: .dispatch) { p in AnyView(DispatcherCommsQuarterScreen(theme: p)) },
            // 2026-05-21 — Dispatcher lane/RFP/contract sextet (SVG 508-513).
            .init(id: "Dpch790", title: "Dispatch · Lane Board",          role: .dispatch) { p in AnyView(DispatcherLaneBoardScreen(theme: p)) },
            .init(id: "Dpch791", title: "Dispatch · Lane Drill",          role: .dispatch) { p in AnyView(DispatcherLaneDrillScreen(theme: p)) },
            .init(id: "Dpch792", title: "Dispatch · Haul Detail",         role: .dispatch) { p in AnyView(DispatcherHaulDetailScreen(theme: p)) },
            .init(id: "Dpch793", title: "Dispatch · RFP Inbox",           role: .dispatch) { p in AnyView(DispatcherRFPInboxScreen(theme: p)) },
            .init(id: "Dpch794", title: "Dispatch · Match-Up",            role: .dispatch) { p in AnyView(DispatcherMatchUpScreen(theme: p)) },
            .init(id: "Dpch795", title: "Dispatch · Contract Write",      role: .dispatch) { p in AnyView(DispatcherContractWriteScreen(theme: p)) },
            // 2026-05-21 — Dispatcher BH-card duodecet (SVG 514-525).
            .init(id: "Dpch800", title: "Dispatch · BH Reassign",         role: .dispatch) { p in AnyView(DispatcherBHReassignScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch801", title: "Dispatch · BH Tender Resolved",  role: .dispatch) { p in AnyView(DispatcherBHTenderResolvedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch802", title: "Dispatch · BH Pickup Armed",     role: .dispatch) { p in AnyView(DispatcherBHPickupArmedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch803", title: "Dispatch · BH Pickup Fired",     role: .dispatch) { p in AnyView(DispatcherBHPickupFiredScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch804", title: "Dispatch · BH In-Transit",       role: .dispatch) { p in AnyView(DispatcherBHInTransitScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch805", title: "Dispatch · BH Approach",         role: .dispatch) { p in AnyView(DispatcherBHDeliveryApproachScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch806", title: "Dispatch · BH At Delivery",      role: .dispatch) { p in AnyView(DispatcherBHAtDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch807", title: "Dispatch · BH Docked Loading",   role: .dispatch) { p in AnyView(DispatcherBHDockedLoadingScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch808", title: "Dispatch · BH BOL Pre-Sign",     role: .dispatch) { p in AnyView(DispatcherBHBOLPreSignScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch809", title: "Dispatch · BH BOL Signed",       role: .dispatch) { p in AnyView(DispatcherBHBOLSignedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch810", title: "Dispatch · BH Paperwork",        role: .dispatch) { p in AnyView(DispatcherBHPaperworkScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch811", title: "Dispatch · BH Closed",           role: .dispatch) { p in AnyView(DispatcherBHClosedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Dispatcher M-04 kanban quintet (SVG 526-530).
            .init(id: "Dpch820", title: "Dispatch · M-04 Awarded Kanban", role: .dispatch) { p in AnyView(DispatcherM04AwardedKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch821", title: "Dispatch · M-04 Pickup Kanban",  role: .dispatch) { p in AnyView(DispatcherM04PickupKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch822", title: "Dispatch · M-04 Transit Kanban", role: .dispatch) { p in AnyView(DispatcherM04InTransitKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch823", title: "Dispatch · M-04 Delivery Kanban",role: .dispatch) { p in AnyView(DispatcherM04AtDeliveryKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch824", title: "Dispatch · M-04 Paper Kanban",   role: .dispatch) { p in AnyView(DispatcherM04PaperworkKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "531",     title: "Dispatch · M-04 Closed Kanban",  role: .dispatch) { p in AnyView(DispatcherM04ClosedKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "532",     title: "Dispatch · M-05 Assign Driver",  role: .dispatch) { p in AnyView(DispatcherM05AssignDriverScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Catalyst Vehicle B-variant deep-drill octet (SVG 330B-337B).
            .init(id: "CV330B", title: "Catalyst · Vehicle Score Axis",   role: .catalyst) { p in AnyView(CatalystVehicleScoreAxisScreen(theme: p)) },
            .init(id: "CV331B", title: "Catalyst · Vehicle Tier",         role: .catalyst) { p in AnyView(CatalystVehicleProfileTierScreen(theme: p)) },
            .init(id: "CV332B", title: "Catalyst · Vehicle Document",     role: .catalyst) { p in AnyView(CatalystVehicleDocumentDetailScreen(theme: p)) },
            .init(id: "CV333B", title: "Catalyst · Vehicle Analytic",     role: .catalyst) { p in AnyView(CatalystVehicleAnalyticDetailScreen(theme: p)) },
            .init(id: "CV334B", title: "Catalyst · Vehicle Settlement",   role: .catalyst) { p in AnyView(CatalystVehicleSettlementDetailScreen(theme: p)) },
            .init(id: "CV335B", title: "Catalyst · Vehicle Step",         role: .catalyst) { p in AnyView(CatalystVehicleStepDetailScreen(theme: p)) },
            .init(id: "CV336B", title: "Catalyst · Vehicle Comp Row",     role: .catalyst) { p in AnyView(CatalystVehicleComplianceRowScreen(theme: p)) },
            .init(id: "CV337B", title: "Catalyst · Vehicle Quarter",      role: .catalyst) { p in AnyView(CatalystVehicleQuarterDetailScreen(theme: p)) },
            // 2026-05-21 — Catalyst Driver B-variant deep-drill octet (SVG 320B-327B).
            .init(id: "CV320B", title: "Catalyst · Driver Score Axis",    role: .catalyst) { p in AnyView(CatalystDriverScoreAxisScreen(theme: p)) },
            .init(id: "CV321B", title: "Catalyst · Driver Tier",          role: .catalyst) { p in AnyView(CatalystDriverProfileTierScreen(theme: p)) },
            .init(id: "CV322B", title: "Catalyst · Driver Document",      role: .catalyst) { p in AnyView(CatalystDriverDocumentDetailScreen(theme: p)) },
            .init(id: "CV323B", title: "Catalyst · Driver Analytic",      role: .catalyst) { p in AnyView(CatalystDriverAnalyticDetailScreen(theme: p)) },
            .init(id: "CV324B", title: "Catalyst · Driver Settlement",    role: .catalyst) { p in AnyView(CatalystDriverSettlementDetailScreen(theme: p)) },
            .init(id: "CV325B", title: "Catalyst · Driver Step",          role: .catalyst) { p in AnyView(CatalystDriverStepDetailScreen(theme: p)) },
            .init(id: "CV326B", title: "Catalyst · Driver Comp Row",      role: .catalyst) { p in AnyView(CatalystDriverComplianceRowScreen(theme: p)) },
            .init(id: "CV327B", title: "Catalyst · Driver Quarter",       role: .catalyst) { p in AnyView(CatalystDriverQuarterDetailScreen(theme: p)) },
            // 2026-05-21 — Catalyst Shipper B-variant deep-drill octet (SVG 340B-347B).
            .init(id: "CV340B", title: "Catalyst · Customer Score Axis",  role: .catalyst) { p in AnyView(CatalystShipperScoreAxisScreen(theme: p)) },
            .init(id: "CV341B", title: "Catalyst · Customer Tier",        role: .catalyst) { p in AnyView(CatalystShipperProfileTierScreen(theme: p)) },
            .init(id: "CV342B", title: "Catalyst · Customer Document",    role: .catalyst) { p in AnyView(CatalystShipperDocumentDetailScreen(theme: p)) },
            .init(id: "CV343B", title: "Catalyst · Customer Analytic",    role: .catalyst) { p in AnyView(CatalystShipperAnalyticDetailScreen(theme: p)) },
            .init(id: "CV344B", title: "Catalyst · Customer Settlement",  role: .catalyst) { p in AnyView(CatalystShipperSettlementDetailScreen(theme: p)) },
            .init(id: "CV345B", title: "Catalyst · Customer Step",        role: .catalyst) { p in AnyView(CatalystShipperStepDetailScreen(theme: p)) },
            .init(id: "CV346B", title: "Catalyst · Customer Comp Row",    role: .catalyst) { p in AnyView(CatalystShipperComplianceRowScreen(theme: p)) },
            .init(id: "CV347B", title: "Catalyst · Customer Quarter",     role: .catalyst) { p in AnyView(CatalystShipperQuarterDetailScreen(theme: p)) },
            // 2026-05-22 — Catalyst Quarterly History A-variants (SVG 327 + 337).
            .init(id: "CV327", title: "Catalyst · Driver Q-History",      role: .catalyst) { p in AnyView(CatalystDriverQuarterlyHistoryScreen(theme: p)) },
            .init(id: "CV337", title: "Catalyst · Vehicle Q-History",     role: .catalyst) { p in AnyView(CatalystVehicleQuarterlyHistoryScreen(theme: p)) },
            // 2026-05-21 — Catalyst vehicle scorecard septet (SVG 330-336).
            .init(id: "CV330", title: "Catalyst · Vehicle Scorecard",     role: .catalyst) { p in AnyView(CatalystVehicleScorecardScreen(theme: p)) },
            .init(id: "CV331", title: "Catalyst · Vehicle Profile",       role: .catalyst) { p in AnyView(CatalystVehicleProfileScreen(theme: p)) },
            .init(id: "CV332", title: "Catalyst · Vehicle Documents",     role: .catalyst) { p in AnyView(CatalystVehicleDocumentsScreen(theme: p)) },
            .init(id: "CV333", title: "Catalyst · Vehicle Analytics",     role: .catalyst) { p in AnyView(CatalystVehicleAnalyticsScreen(theme: p)) },
            .init(id: "CV334", title: "Catalyst · Vehicle Settlements",   role: .catalyst) { p in AnyView(CatalystVehicleSettlementsScreen(theme: p)) },
            .init(id: "CV335", title: "Catalyst · Vehicle Onboarding",    role: .catalyst) { p in AnyView(CatalystVehicleOnboardingScreen(theme: p)) },
            .init(id: "CV336", title: "Catalyst · Vehicle Compliance",    role: .catalyst) { p in AnyView(CatalystVehicleComplianceScreen(theme: p)) },
            // 2026-05-21 — Catalyst customer scorecard octet (SVG 340-347).
            .init(id: "CV340", title: "Catalyst · Customer Scorecard",    role: .catalyst) { p in AnyView(CatalystShipperScorecardScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV341", title: "Catalyst · Customer Profile",      role: .catalyst) { p in AnyView(CatalystShipperProfileScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV342", title: "Catalyst · Customer Documents",    role: .catalyst) { p in AnyView(CatalystShipperDocumentsScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV343", title: "Catalyst · Customer Analytics",    role: .catalyst) { p in AnyView(CatalystShipperAnalyticsScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV344", title: "Catalyst · Customer Ledger",       role: .catalyst) { p in AnyView(CatalystShipperSettlementsScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV345", title: "Catalyst · Customer Onboarding",   role: .catalyst) { p in AnyView(CatalystShipperOnboardingScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV346", title: "Catalyst · Customer Compliance",   role: .catalyst) { p in AnyView(CatalystShipperComplianceScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            .init(id: "CV347", title: "Catalyst · Customer Quarterly",    role: .catalyst) { p in AnyView(CatalystShipperQuarterScreen(theme: p, shipperId: BrokerNavContext.latestShipperId)) },
            // 2026-05-21 — Catalyst outbound lifecycle septet (SVG 350-356).
            .init(id: "CV350", title: "Catalyst · At Gate",               role: .catalyst) { p in AnyView(CatalystAtGateScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV351", title: "Catalyst · At Dock",               role: .catalyst) { p in AnyView(CatalystAtDockScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV352", title: "Catalyst · Departing",             role: .catalyst) { p in AnyView(CatalystDepartingScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV353", title: "Catalyst · Pre-Delivery",          role: .catalyst) { p in AnyView(CatalystPreDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV354", title: "Catalyst · At Delivery",           role: .catalyst) { p in AnyView(CatalystAtDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV355", title: "Catalyst · POD Receipt",           role: .catalyst) { p in AnyView(CatalystPODReceiptScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV356", title: "Catalyst · Load Closed",           role: .catalyst) { p in AnyView(CatalystLoadClosedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Catalyst backhaul-ack septet (SVG 357-363).
            .init(id: "CV357", title: "Catalyst · BH Tender",             role: .catalyst) { p in AnyView(CatalystBackhaulTenderScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV358", title: "Catalyst · BH Accepted",           role: .catalyst) { p in AnyView(CatalystBackhaulAcceptedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV359", title: "Catalyst · BH Pickup Watch",       role: .catalyst) { p in AnyView(CatalystBackhaulPickupWatchScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV360", title: "Catalyst · BH On-Site",            role: .catalyst) { p in AnyView(CatalystBackhaulOnSiteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV361", title: "Catalyst · BH In-Transit",         role: .catalyst) { p in AnyView(CatalystBackhaulInTransitScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV362", title: "Catalyst · BH Approach",           role: .catalyst) { p in AnyView(CatalystBackhaulDeliveryApproachScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV363", title: "Catalyst · BH At Delivery",        role: .catalyst) { p in AnyView(CatalystBackhaulAtDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Catalyst backhaul-close quintet (SVG 364-368).
            .init(id: "CV364", title: "Catalyst · BH Docked Loading",     role: .catalyst) { p in AnyView(CatalystBackhaulDockedLoadingScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV365", title: "Catalyst · BH BOL Pre-Sign",       role: .catalyst) { p in AnyView(CatalystBackhaulBOLPreSignScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV366", title: "Catalyst · BH BOL Signed",         role: .catalyst) { p in AnyView(CatalystBackhaulBOLSignedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV367", title: "Catalyst · BH Paperwork",          role: .catalyst) { p in AnyView(CatalystBackhaulPaperworkScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV368", title: "Catalyst · BH Closed Stage",       role: .catalyst) { p in AnyView(CatalystBackhaulClosedStageScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Catalyst M-04 multi-broker bidding sextet (SVG 369-374).
            .init(id: "CV369", title: "Catalyst · M-04 First Bid",        role: .catalyst) { p in AnyView(CatalystM04FirstBidScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV370", title: "Catalyst · M-04 Second Quote",     role: .catalyst) { p in AnyView(CatalystM04SecondQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV371", title: "Catalyst · M-04 Third Quote",      role: .catalyst) { p in AnyView(CatalystM04ThirdQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV372", title: "Catalyst · M-04 Fourth Quote",     role: .catalyst) { p in AnyView(CatalystM04FourthQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV373", title: "Catalyst · M-04 Awarded CEL",      role: .catalyst) { p in AnyView(CatalystM04AwardedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV374", title: "Catalyst · M-04 On-Site CEL",      role: .catalyst) { p in AnyView(CatalystM04OnSiteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Catalyst M-04 fleet-track pair (SVG 375-376).
            .init(id: "CV375", title: "Catalyst · M-04 In-Transit Track",  role: .catalyst) { p in AnyView(CatalystM04InTransitTrackScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "CV376", title: "Catalyst · M-04 At-Delivery Track", role: .catalyst) { p in AnyView(CatalystM04AtDeliveryTrackScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Shipper backhaul-echo sextet (SVG 250-255).
            .init(id: "SH250", title: "Shipper · BH Eyebrow",            role: .shipper) { p in AnyView(ShipperBackhaulEyebrowScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH251", title: "Shipper · BH Awarded",            role: .shipper) { p in AnyView(ShipperBackhaulAwardedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH252", title: "Shipper · BH Pickup Annex",       role: .shipper) { p in AnyView(ShipperBackhaulPickupAnnexScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH253", title: "Shipper · BH Pickup Fired",       role: .shipper) { p in AnyView(ShipperBackhaulPickupFiredScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH254", title: "Shipper · BH In-Transit",         role: .shipper) { p in AnyView(ShipperBackhaulInTransitScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH255", title: "Shipper · BH Delivery",           role: .shipper) { p in AnyView(ShipperBackhaulDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Shipper backhaul-echo close quintet (SVG 256-260).
            .init(id: "SH256", title: "Shipper · BH Docked Loading",     role: .shipper) { p in AnyView(ShipperBackhaulDockedLoadingScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH257", title: "Shipper · BH BOL Pre-Sign",       role: .shipper) { p in AnyView(ShipperBackhaulBOLPreSignScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH258", title: "Shipper · BH BOL Signed",         role: .shipper) { p in AnyView(ShipperBackhaulBOLSignedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH259", title: "Shipper · BH Paperwork",          role: .shipper) { p in AnyView(ShipperBackhaulPaperworkScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH260", title: "Shipper · BH Closed Seal",        role: .shipper) { p in AnyView(ShipperBackhaulClosedSealScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Shipper M-04 observed nonet (SVG 261-269).
            .init(id: "SH261", title: "Shipper · M-04 Posted",           role: .shipper) { p in AnyView(ShipperM04FreshPostedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH262", title: "Shipper · M-04 First Quote",      role: .shipper) { p in AnyView(ShipperM04FirstQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH263", title: "Shipper · M-04 Second Quote",     role: .shipper) { p in AnyView(ShipperM04SecondQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH264", title: "Shipper · M-04 Third Quote",      role: .shipper) { p in AnyView(ShipperM04ThirdQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH265", title: "Shipper · M-04 Fourth Quote",     role: .shipper) { p in AnyView(ShipperM04FourthQuoteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH266", title: "Shipper · M-04 Awarded",          role: .shipper) { p in AnyView(ShipperM04AwardedScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH267", title: "Shipper · M-04 On-Site",          role: .shipper) { p in AnyView(ShipperM04OnSiteScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH268", title: "Shipper · M-04 In-Transit",       role: .shipper) { p in AnyView(ShipperM04InTransitScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "SH269", title: "Shipper · M-04 At Delivery",      role: .shipper) { p in AnyView(ShipperM04AtDeliveryScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
        ])

        // Rail Engineer surface (Rail550–552).
        list.append(contentsOf: [
            .init(id: "Rail550", title: "Rail Engineer · Home",       role: .railEngineer) { p in AnyView(RailEngineerHomeScreen(theme: p)) },
            .init(id: "Rail551", title: "Rail Engineer · Shipments",  role: .railEngineer) { p in AnyView(RailShipmentsScreen(theme: p)) },
            .init(id: "Rail552", title: "Rail Engineer · Compliance", role: .railEngineer) { p in AnyView(RailComplianceScreen(theme: p)) },
        ])

        // Vessel Operator surface (Vesl650–652).
        list.append(contentsOf: [
            .init(id: "Vesl650", title: "Vessel Operator · Home",       role: .vesselOperator) { p in AnyView(VesselOperatorHomeScreen(theme: p)) },
            .init(id: "Vesl651", title: "Vessel Operator · Shipments",  role: .vesselOperator) { p in AnyView(VesselShipmentsScreen(theme: p)) },
            .init(id: "Vesl652", title: "Vessel Operator · Compliance", role: .vesselOperator) { p in AnyView(VesselComplianceScreen(theme: p)) },
        ])

        return list
    }()

    static func forRole(_ r: ProductionScreen.Role) -> [ProductionScreen] {
        all.filter { $0.role == r }
    }
}

// MARK: - Role placeholder screen
//
// Minimal "nothing ported here yet" surface for non-driver roles. Exists so
// the chrome role tabs aren't stranded behind the `hasContent` guard until
// their real Figma ports land. Deliberately neutral — no fake data, no mock
// CTAs — per SKILL.md §13 ("every backend stub gap has a neutral empty
// state on the client; no fake data"). Brand-gradient orb + role kicker +
// title + id + "Figma port pending" line. Renders identically in both
// registers; palette comes through the initializer like all shipped screens.

#if DEBUG
// Phase 1 audit (eusotrip-killers §6, 2026-04-23):
// Surface is now composed through `EusoEmptyState` with `comingSoon: true`.
// This preserves the doctrine: "every backend stub gap has a neutral empty
// state on the client; no fake data." The gradient-orb heritage layout is
// retained as the header chip (role initial on gradient circle) because
// EusoEmptyState's default glyph is a neutral-tint square — the per-role
// gradient orb gives the role-switcher demo a clearer visual identity.
private struct RolePlaceholderScreen: View {
    let theme: Theme.Palette
    let role: ProductionScreen.Role
    let id: String
    let title: String
    let systemImage: String

    var body: some View {
        ZStack {
            theme.bgPage.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Space.s4) {
                    // Role identity chip (gradient orb w/ role initial)
                    ZStack {
                        Circle()
                            .fill(LinearGradient.diagonal)
                            .frame(width: 72, height: 72)
                        Text(String(role.rawValue.prefix(1)))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )

                    Text(role.rawValue.uppercased())
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(theme.textTertiary)

                    // Canonical empty-state primitive — keeps every stub
                    // surface visually identical to every other "backend
                    // missing / no data yet" pane across the app.
                    EusoEmptyState(
                        systemImage: systemImage,
                        title: title,
                        subtitle: "Screen \(id) · Figma port pending. The \(role.rawValue.lowercased()) role tab activates in dev chrome; the production surface ships in Phase 6.",
                        comingSoon: true
                    )
                    .environment(\.palette, theme)
                    .padding(.horizontal, Space.s4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s8)
            }
        }
    }
}

#Preview("RolePlaceholder · Shipper · Night") {
    RolePlaceholderScreen(theme: Theme.dark, role: .shipper, id: "200", title: "Shipper home", systemImage: "shippingbox.circle")
        .preferredColorScheme(.dark)
}

#Preview("RolePlaceholder · Carrier · Afternoon") {
    RolePlaceholderScreen(theme: Theme.light, role: .carrier, id: "300", title: "Carrier home", systemImage: "truck.box")
        .preferredColorScheme(.light)
}
#endif

// MARK: - Root

struct ContentView: View {
    /// iOS system appearance. We mirror this into `register` at launch and
    /// whenever the system flips, so the EusoTrip UI follows Settings →
    /// Display & Brightness by default. A manual tap in the dev-chrome
    /// register switch flips `userOverrodeRegister = true` and stops the
    /// mirroring, letting the reviewer pin Night or Afternoon for a
    /// design-fidelity walk.
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var register: ThemeRegister = .dark
    @State private var userOverrodeRegister: Bool = false

    /// The signed-in user's role drives every dispatch decision in this
    /// view. Read once per render, then routed through
    /// `RoleSurfaceRouter` for non-driver roles. Defaults to .driver
    /// only as a transient fallback during sign-out — `AppRoot` blocks
    /// `phase != .signedIn` from reaching ContentView, so by the time
    /// this evaluates the user is non-nil in the steady state.
    @EnvironmentObject private var session: EusoTripSession
#if DEBUG
    // Dev-chrome-only state. In Release builds these have no representation
    // because the chrome surface (role tabs, prev/next walker, register
    // pin) is entirely compiled out.
    @State private var selectedRole: ProductionScreen.Role = .driver
    @State private var currentIndex: Int = 0
#endif

    /// Shared driver-mode nav state. Owns the top-level BottomNav tab
    /// (home | trips | wallet | me) and the ESANG coach sheet toggle.
    /// Every `BottomNav` rendered anywhere under this ContentView reads
    /// the injected `driverNavHandler` env value and routes taps here —
    /// fixing the wiring gap where all 010-023 `driverNavLeading_NNN()`
    /// helpers created NavSlots with no-op onTap closures.
    @StateObject private var nav = DriverNavController()

    /// Owns the driver's trip phase — which ScreenRegistry id the Home
    /// tab should render right now. Replaces the old `currentIndex`-as-
    /// linear-cycle approach with a real state machine; lifecycle CTAs
    /// call `trip.advance()` and the Home view reads `trip.phase`.
    /// See `TripPhase` in DriverNavController.swift for the happy-path
    /// transition table.
    @StateObject private var trip = DriverTripController()

    // MARK: - 49th firing · dead-stub wiring state
    //
    // Backing state for the 10 ambient driver env handlers declared by the
    // 45th firing in DriverNavController.swift (driverDialPhone,
    // driverOpenMessages, driverOpenDocDrawer, driverOpenTripLog,
    // driverShareLink, driverShowHelp, driverUploadPhoto, driverReportIssue,
    // driverToggleVoiceMute, driverToggleMapLayers). Those keys were declared
    // but never injected, so every `Button { } label: { ... }` site that
    // reached for them silently no-op'd. This state + the .sheet presenters
    // in `body` below are what make those 61 dead-stub taps do real work.

    /// Phone number the user is about to dial. `nil` = no confirmation sheet
    /// showing; non-nil = present a `.confirmationDialog` that either calls
    /// `tel://<digits>` or cancels.
    @State private var dialConfirmationNumber: String? = nil

    /// When non-nil, `DriverMessagingSheet` is presented over the current
    /// surface. A `nil` threadId means "open the inbox"; a non-nil value
    /// means "open this specific conversation".
    @State private var messagingSheetTarget: MessagingSheetTarget? = nil

    /// When `true`, the document drawer sheet is presented — lists active
    /// load documents (BOL, Rate Con, POD) sourced from the real backend via
    /// the drivers / documentManagement routers. No mock data is shown; if
    /// no documents are linked yet, an `EusoEmptyState` renders.
    @State private var docDrawerActive: Bool = false

    /// When `true`, the trip log sheet is presented, showing the driver's
    /// lifecycle event stream for the current load. Events come from the
    /// real backend via `loadLifecycle.getEventLog` (falls back to empty
    /// state when `currentLoad` is nil).
    @State private var tripLogActive: Bool = false

    /// Payload handed to iOS `ShareLink`. `nil` = no share sheet; non-nil =
    /// present the system share sheet wrapping the URL / string.
    @State private var shareItem: DriverShareItem? = nil

    /// When `true`, `PhotosPicker` is presented for defect / POD / damage
    /// photo capture. Selected images upload through `dvir.attachPhoto` or
    /// `documentManagement.uploadPOD` depending on the active phase.
    @State private var photoPickerActive: Bool = false

    /// When non-nil, the raise-exception sheet is presented. The `context`
    /// string identifies which screen fired it so the backend can attribute
    /// the exception to the right lifecycle phase.
    @State private var reportIssueContext: String? = nil

    /// Voice-coach mute state — persisted to UserDefaults so it survives app
    /// launches. Read by `eSangVoiceInput` and the 035 on-screen controls.
    @AppStorage("com.eusorone.EusoTrip.voice.muted") private var voiceCoachMuted: Bool = false

    /// Map layers overlay visibility — persisted. Read by 013 / 018 map
    /// backgrounds to decide whether the traffic/weather overlays render.
    @AppStorage("com.eusorone.EusoTrip.map.layersVisible") private var mapLayersVisible: Bool = true

#if DEBUG
    private var screens: [ProductionScreen] {
        ScreenRegistry.forRole(selectedRole)
    }
    private var current: ProductionScreen? {
        screens.indices.contains(currentIndex) ? screens[currentIndex] : nil
    }

    /// Dev chrome (role tabs / register toggle / prev-next / title) is hidden
    /// by default — the app renders the current screen edge-to-edge so it
    /// matches the Figma verbatim. Swipe down from the top-right corner, or
    /// two-finger tap, to reveal the chrome sheet. DEBUG-only — never
    /// compiles into TestFlight / App Store.
    @State private var showChrome: Bool = false
#endif

    var body: some View {
        ZStack {
            register.palette.bgPage.ignoresSafeArea()

            // MARK: Current surface — edge-to-edge
            //
            // In Driver mode we branch on `nav.currentTab`: .home renders
            // the active lifecycle screen (010-023 via the ScreenRegistry,
            // each of which bakes its own BottomNav into its body); the
            // other three tabs render the dedicated panes from
            // DriverTabPanes.swift with a shared BottomNav overlay so the
            // pill stays visible and the env-routed tap handler keeps the
            // user able to flip back to Home at any point.
            //
            // Non-driver roles still render the ScreenRegistry placeholder
            // untouched, preserving the existing chrome-walk behavior.
            Group {
                // Production role-aware dispatch (replaces the previous
                // Driver-only hardcode + DEBUG-chrome role walker).
                // `session.user.roleEnum` decides which surface
                // mounts. The Driver branch stays inline because it
                // owns this view's `nav` / `trip` `@StateObject`s,
                // sheet presenters, and orb state machine — moving
                // it to a separate type would unwire all of that.
                // Every other role goes through `RoleSurfaceRouter`,
                // which also handles RBAC + the web-continuation
                // landing for roles whose native iOS surface ships
                // in a later release.
                let role = session.user?.roleEnum ?? .driver
                if role == .driver {
                    driverSurface
                } else {
                    RoleSurfaceRouter(palette: register.palette)
                        .id("role-\(role.rawValue)")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Propagate the active register's palette to every descendant
            // (DriverTripsPane / DriverWalletPane / DriverMePane and the
            // shared BottomNav all read `@Environment(\.palette)`).
            .environment(\.palette, register.palette)
            // Single source of truth for every Driver BottomNav slot +
            // center orb tap. Routes to the nav controller and — for
            // .home — resets the trip phase to `.idle` so tapping Home
            // always returns to the dashboard, not the mid-trip screen
            // the driver was last on. Mid-trip state is preserved if
            // they tap back into the trip (future: dedicated "resume
            // trip" affordance); for now, Home is the dashboard surface.
            .environment(\.driverNavHandler) { label in
                switch label.lowercased() {
                case "home":
                    // Tapping Home from another tab: just switch to Home
                    // (preserves the current trip phase so the driver
                    // picks up mid-trip from where they left off).
                    // Tapping Home while already on Home: rewind to the
                    // dashboard — standard "take me to the top" gesture.
                    if nav.currentTab == .home {
                        trip.jump(to: .idle)
                    } else {
                        nav.currentTab = .home
                    }
                case "trips":
                    nav.currentTab = .trips
                case "loads", "wallet":
                    // Request 3: the former "Wallet" slot was renamed to
                    // "Loads". The Tab enum case name stays `.wallet` for
                    // backward-compat; the label mapping is here so both
                    // labels route correctly.
                    nav.currentTab = .wallet
                case "me":
                    nav.currentTab = .me
                case "esang", "orb":
                    nav.showeSang = true
                default:
                    break
                }
            }
            // Shipper-mode tap router. Mirror of `driverNavHandler`.
            // Resolves the slot label to the matching ScreenRegistry id
            // (Home → 200, Create Load → 204, Loads → 201, Me → 320)
            // and flips `currentIndex` so the screen swap is local —
            // no NotificationCenter round-trip needed when ContentView
            // already owns the index. Founder direction 2026-04-28:
            // make the shipper bottom nav actually navigate.
            .environment(\.shipperNavHandler) { label in
#if DEBUG
                let key = label.lowercased()
                if ShipperNavRoute.orbLabels.contains(key) {
                    nav.showeSang = true
                    return
                }
                guard let screenId = ShipperNavRoute.map[key] else { return }
                let shipperScreens = ScreenRegistry.forRole(.shipper)
                if let idx = shipperScreens.firstIndex(where: { $0.id == screenId }) {
                    // currentIndex is dev-chrome-only state; the shipper
                    // surface only renders in DEBUG builds via the
                    // ScreenRegistry walker. In Release the shipper
                    // chrome is unreachable today (driver-only
                    // production target), so this branch is the right
                    // place to wire the swap.
                    if selectedRole != .shipper { selectedRole = .shipper }
                    currentIndex = idx
                }
#endif
            }
            // Lifecycle forward-advance handler. Any `LifecycleCTAButton`
            // rendered within a driver lifecycle screen (010 → 027) reads
            // this env closure and calls it when tapped, triggering the
            // trip controller's happy-path state transition. The state
            // machine owns the sequence — looping back to `.idle` after
            // `.nextLoadBrief` so a completed trip returns to the
            // dashboard.
            //
            // Backend bridge (Wave-5, 2026-04-20): after the local state
            // flip we ask the origin phase for the transitionId matching
            // the `(from, to)` pair; if it returns a non-nil id AND the
            // controller has a currentLoad, we fire
            // `loadLifecycle.executeTransition` in a background Task so
            // the server's `loads.status` tracks the driver's lived
            // state. UI-only hops (pretrip DVIR, off-duty, next-load
            // brief) short-circuit here and leave the backend untouched,
            // which is the correct behavior — those phases don't
            // correspond to a real `loadStatus`.
            .environment(\.lifecycleAdvance) { [api = EusoTripAPI.shared] in
                let from = trip.phase
                trip.advance()
                let to = trip.phase
                guard let transitionId = from.transitionId(to: to),
                      let loadId = trip.currentLoad?.id else { return }
                Task {
                    _ = try? await api.loadLifecycle.executeTransition(
                        loadId: String(loadId),
                        transitionId: transitionId
                    )
                }
            }
            // Lifecycle exit handler. Pre-trip DVIR (and future screens
            // that expose an X / Cancel chip) read this env closure to
            // rewind the trip state machine back to `.idle` — which
            // re-renders the Home dashboard without disturbing the
            // driver's currentLoad or duty status.
            .environment(\.lifecycleExit) {
                trip.phase = .idle
                trip.preTripGate = .notStarted
            }
            // Nav-back handler. Every 010+ top-bar chevron.left button
            // reads this closure and taps `trip.stepBack()` — the
            // controller walks `phase` backward along `happyPathPrev`
            // (a no-op from `.idle`). Wired here so a single injection
            // drives all back buttons across the 40+ shipped screens,
            // which previously shipped with `Button { } label: { ... }`
            // empty closures (doctrine violation the 44th firing ledger
            // hygiene pass surfaced and fixed).
            .environment(\.driverNavBack) {
                trip.stepBack()
            }
            // MARK: - 49th firing · 10 ambient driver env handlers
            //
            // The 45th firing declared these env keys in
            // DriverNavController.swift but never injected them here, so
            // every `Button { action } label:` site that reached for them
            // silently no-op'd. These injections + the `.sheet(...)` and
            // `.confirmationDialog(...)` presenters below make all 61
            // previously-dead stubs across 011-045 fire real behavior —
            // tel:// opens, tRPC mutations, document-drawer sheets, iOS
            // share sheet, PhotosPicker, UNUserNotificationCenter reminders,
            // and state-machine transitions.

            // Dial a phone number. Uses iOS tel:// URL scheme; we first
            // present a confirmation dialog so misclicks can't trigger a
            // live call. Digits-only normalization protects against users
            // passing "(555) 123-4567" — iOS doesn't dial with punctuation.
            .environment(\.driverDialPhone) { number in
                let digits = number.filter { $0.isNumber || $0 == "+" }
                guard !digits.isEmpty else { return }
                dialConfirmationNumber = digits
            }
            // Open the messaging surface. `nil` threadId means "open the
            // inbox" — the sheet then lists conversations from the canonical
            // `messages.ts` router (§16 messaging-docs). A non-nil value
            // jumps straight into that conversation. Backend: real tRPC
            // calls to `messages.getConversations` / `messages.sendMessage`.
            .environment(\.driverOpenMessages) { threadId in
                messagingSheetTarget = MessagingSheetTarget(threadId: threadId)
            }
            // Open the document drawer for the active load. Sheet pulls
            // BOL / Rate Con / POD from the real backend via
            // `drivers.getRateConURL` and `documentManagement.*`. When no
            // active load or no docs are linked yet, an EusoEmptyState
            // renders inside the sheet — no fake data.
            .environment(\.driverOpenDocDrawer) {
                docDrawerActive = true
            }
            // Open the trip log — lifecycle event stream for the current
            // load. Source of truth is the phase state machine plus any
            // logged wizard step transitions; both are real (no mocks).
            .environment(\.driverOpenTripLog) {
                tripLogActive = true
            }
            // Present the iOS system share sheet. Wrapper around ShareLink
            // / UIActivityViewController — the raw string is used as the
            // shared item; if it parses as a URL we share a URL, else the
            // raw text.
            .environment(\.driverShareLink) { raw in
                shareItem = DriverShareItem(raw: raw)
            }
            // Open the ESANG coach sheet, passing the context topic so
            // ESANG can tailor the prompt. Routes through the same
            // `nav.showeSang` flag the orb tap uses; we also stash the topic
            // in a notification so eSangAutopilot can pick it up on open.
            .environment(\.driverShowHelp) { topic in
                NotificationCenter.default.post(
                    name: .esangOpenHelp,
                    object: topic
                )
                nav.showeSang = true
            }
            // Launch the photo-capture flow. Opens iOS PhotosPicker; the
            // selected image is uploaded through `dvir.attachPhoto` when the
            // active phase is a DVIR surface, or through
            // `documentManagement.uploadPOD` when we're in a delivery leg.
            .environment(\.driverUploadPhoto) {
                photoPickerActive = true
            }
            // Raise an exception. Presents a reason picker + note sheet;
            // submits via the current wizard's `abort(reason:)` when one is
            // active, or through a dispatcher message otherwise. No silent
            // no-op — even without backend wiring this fires a real tRPC
            // mutation.
            .environment(\.driverReportIssue) {
                reportIssueContext = trip.phase.rawValue
            }
            // Toggle the in-cab voice-coach mute. Persisted to UserDefaults
            // under `com.eusorone.EusoTrip.voice.muted` so the preference
            // survives cold launches. eSangVoiceInput reads the same key.
            .environment(\.driverToggleVoiceMute) {
                voiceCoachMuted.toggle()
            }
            // Toggle the map-layers overlay. Persisted; 013/018 map
            // backgrounds read the @AppStorage key to decide whether
            // the traffic / weather overlays render.
            .environment(\.driverToggleMapLayers) {
                mapLayersVisible.toggle()
            }
            // Make the trip controller available to any descendant
            // (future: HOS break banner, proximity badge, Load-accept
            // sheet) via @EnvironmentObject so the state doesn't have
            // to be threaded through every call site.
            .environmentObject(trip)

            // MARK: - 49th firing · sheet + dialog presenters
            // These presenters wire the above state into real iOS UI.
            // They all hang off the root ZStack so any descendant firing an
            // env handler gets the sheet — no need to re-plumb per screen.

            // Phone-dial confirmation. Two-tap gate before a live call.
            .confirmationDialog(
                "Call \(dialConfirmationNumber ?? "")?",
                isPresented: Binding(
                    get: { dialConfirmationNumber != nil },
                    set: { if !$0 { dialConfirmationNumber = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Call", role: .destructive) {
                    if let digits = dialConfirmationNumber,
                       let url = URL(string: "tel://\(digits)") {
                        UIApplication.shared.open(url)
                    }
                    dialConfirmationNumber = nil
                }
                Button("Cancel", role: .cancel) {
                    dialConfirmationNumber = nil
                }
            }

            // Messaging sheet — inbox or single thread depending on target.
            .sheet(item: $messagingSheetTarget) { target in
                DriverMessagingSheet(threadId: target.threadId)
                    .environment(\.palette, register.palette)
                    .preferredColorScheme(register.preferredColorScheme)
            }

            // Document drawer sheet for the active load.
            .sheet(isPresented: $docDrawerActive) {
                DriverDocumentDrawerSheet(
                    loadId: trip.currentLoad?.id.description,
                    loadNumber: trip.currentLoad?.loadNumber
                )
                .environment(\.palette, register.palette)
                .preferredColorScheme(register.preferredColorScheme)
            }

            // Trip log sheet.
            .sheet(isPresented: $tripLogActive) {
                DriverTripLogSheet(
                    loadId: trip.currentLoad?.id.description,
                    loadNumber: trip.currentLoad?.loadNumber,
                    currentPhase: trip.phase
                )
                .environment(\.palette, register.palette)
                .preferredColorScheme(register.preferredColorScheme)
            }

            // iOS share sheet.
            .sheet(item: $shareItem) { item in
                DriverShareSheetHost(item: item)
                    .environment(\.palette, register.palette)
                    .preferredColorScheme(register.preferredColorScheme)
            }

            // Photo capture sheet (DVIR defect / POD / damage).
            .sheet(isPresented: $photoPickerActive) {
                DriverPhotoUploadSheet(
                    loadId: trip.currentLoad?.id.description,
                    phaseRaw: trip.phase.rawValue,
                    isDVIRPhase: {
                        if case .notStarted = trip.preTripGate { return false }
                        return true
                    }()
                )
                .environment(\.palette, register.palette)
                .preferredColorScheme(register.preferredColorScheme)
            }

            // Raise-exception sheet.
            .sheet(item: Binding(
                get: { reportIssueContext.map { DriverReportIssueContext(raw: $0) } },
                set: { new in reportIssueContext = new?.raw }
            )) { ctx in
                DriverReportIssueSheet(
                    contextRaw: ctx.raw,
                    loadId: trip.currentLoad?.id.description
                )
                .environment(\.palette, register.palette)
                .preferredColorScheme(register.preferredColorScheme)
            }

            // No visible dev-chrome puck. The top-right "slider.horizontal.3"
            // button was removed per user directive 2026-04-19 — it was
            // leaking the role walker / register pin / prev-next chrome
            // into the live surface. The chrome sheet state (`showChrome`,
            // `chromeSheet`) is retained behind `#if DEBUG` so a future
            // debug-only gesture can re-expose it if ever needed, but in
            // both Debug and Release builds no chrome affordance is
            // rendered.
        }
        // Only clamp the window's color scheme when the reviewer has
        // explicitly pinned a register via the dev-chrome switch. In the
        // default path we pass `nil`, which tells SwiftUI "no preference"
        // and lets the window inherit iOS Settings → Display & Brightness.
        // Passing a non-nil value here would freeze `@Environment(\.colorScheme)`
        // to that register, meaning the system-appearance flip the user
        // makes in Control Center would never propagate into the app.
        .preferredColorScheme(userOverrodeRegister ? register.preferredColorScheme : nil)
        .animation(.easeInOut(duration: 0.22), value: register)
#if DEBUG
        .animation(.easeInOut(duration: 0.22), value: currentIndex)
        .animation(.easeInOut(duration: 0.22), value: selectedRole)
#endif
        .animation(.easeInOut(duration: 0.22), value: nav.currentTab)
        .animation(.easeInOut(duration: 0.22), value: trip.phase)
#if DEBUG
        .onChange(of: selectedRole) { _, _ in
            currentIndex = 0
            // When the dev-chrome flips the role away from .driver, reset
            // driver nav so returning later lands on Home, not a stale tab,
            // and rewind the trip phase so the next driver walk starts at
            // the dashboard.
            nav.currentTab = .home
            nav.showeSang = false
            trip.reset()
        }
#endif
        // Mirror iOS Settings → Display & Brightness into our register the
        // first time ContentView mounts, and whenever the user flips system
        // appearance while the app is open — but only as long as they
        // haven't manually overridden via the dev-chrome switch.
        .onAppear {
            if !userOverrodeRegister {
                register = ThemeRegister(colorScheme: systemColorScheme)
            }
            // Bind the observers that drive background TripEvents into
            // the controller we own. GeofenceService will fire
            // .geofenceApproachingPickup / .geofenceApproachingDelivery
            // when CoreLocation reports region entry; HOSClockService
            // will fire .hosBreakRequired when drive-time nears the
            // 11-hour limit. Both hold weak refs, so rebinding is safe.
            GeofenceService.shared.bind(to: trip)
            HOSClockService.shared.bind(to: trip)
            // If the driver already has an active load (e.g. warm
            // launch into mid-trip), arm the geofences immediately
            // and start the continuous-GPS push so the shipper sees
            // the truck pin update on every map surface (lifecycle
            // 263–279, ControlTower, LiveTracking) without waiting
            // on the next coarse geofence transition.
            if let load = trip.currentLoad {
                GeofenceService.shared.monitor(load: load)
                DriverGPSPushService.shared.start(loadId: load.id)
            }
        }
        .onChange(of: systemColorScheme) { _, newScheme in
            guard !userOverrodeRegister else { return }
            register = ThemeRegister(colorScheme: newScheme)
        }
        // Re-register geofences whenever the active load changes (new
        // assignment, trip completed, sign-out). `monitor(load:)` clears
        // prior regions before registering the fresh pair, and
        // `clearAll()` on nil keeps CoreLocation quiet between trips.
        .onChange(of: trip.currentLoad?.id) { _, _ in
            if let load = trip.currentLoad {
                GeofenceService.shared.monitor(load: load)
                DriverGPSPushService.shared.start(loadId: load.id)
            } else {
                GeofenceService.shared.clearAll()
                DriverGPSPushService.shared.stop()
            }
        }
        // Cross-surface "Start pre-trip DVIR" — fired by the MeDvirView +
        // MeZeunView CTAs in `MeDetailScreens.swift`. Previously those
        // buttons lived inside a detail sheet with no way to navigate the
        // root surface out from under themselves. The notification is
        // posted on tap (see `MeAction.fire` + the explicit
        // `NotificationCenter.default.post(name: .eusoStartPretripDVIR…)`
        // sites). The root ContentView is the only place with access to
        // both `nav` and `trip`, so the observer lives here: we flip the
        // active tab back to Home and walk the trip state machine into
        // `.pretripDVIR`. Any presenting Me sheet auto-dismisses the
        // moment `nav.currentTab` changes because the sheet's presenter
        // (`DriverMePane`) is no longer rendered.
        .onReceive(NotificationCenter.default.publisher(for: .eusoStartPretripDVIR)) { _ in
            nav.currentTab = .home
            trip.handle(.startPretripDVIR)
        }
        // Driver-side `MeAction.fire(_:)` listener. The 49th-firing audit
        // surfaced 23 driver MeAction keys posting into the void because
        // the only `.eusoMeActionFired` subscriber lives inside the Shipper
        // surface. Driver chrome doesn't go through `RoleSurfaceRouter`,
        // so those taps were silently dropped. Per [feedback_no_dead_buttons]
        // every tap must land somewhere — here we route the navigation-class
        // keys to real tabs / sheets and accept the rest with the haptic
        // already fired in `MeAction.fire(_:)`.
        .onReceive(NotificationCenter.default.publisher(for: .eusoMeActionFired)) { note in
            guard let key = note.object as? String else { return }
            handleDriverMeAction(key: key, userInfo: note.userInfo ?? [:])
        }
#if DEBUG
        .sheet(isPresented: $showChrome) {
            chromeSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
#endif
        // ESANG coach sheet — presented as a system sheet from the root so
        // tapping the orb from any Driver surface (lifecycle screen or any
        // of the three panes) slides it in over the current content.
        .sheet(isPresented: $nav.showeSang) {
            DrivereSangCoachSheet()
                .environment(\.palette, register.palette)
                // Mirror the root: let the system drive the sheet's
                // scheme unless the reviewer has pinned a register.
                .preferredColorScheme(userOverrodeRegister ? register.preferredColorScheme : nil)
                // Wire ESANG autopilot actions back into the host. Per user
                // direction (2026-04-20):
                //   > i want you to look at the autopilot system on the
                //   > web platform and how esang can control the platform
                //   > by voice take you to this screen or that screen. i
                //   > need esang to have those same capabilties on the app.
                //   > wire commands into endpoints on the app.
                // The chat sheet parses `<<<ACTION:…>>>` tokens out of
                // ESANG's replies and fires them through this closure so
                // navigate / open-chat / refresh / select-load actually
                // affect the app state.
                .environment(\.esangActionHandler) { action in
                    handleeSangAction(action)
                }
        }
    }

    // MARK: - ESANG autopilot dispatcher

    /// Apply an `eSangAction` parsed from the assistant's reply. Routes the
    /// intent into the right controller — tab switching goes through
    /// `nav`, refreshes bubble back down via a notification, load-open
    /// surfaces a Load Detail sheet over Home.
    ///
    /// Unknown / no-op intents are swallowed silently — the parser only
    /// emits verbs it recognizes, so there's nothing to fall through to.
    private func handleeSangAction(_ action: eSangAction) {
        switch action {
        case .navigate(let route):
            switch route {
            case .home:
                nav.currentTab = .home
                trip.jump(to: .idle)
            case .trips:
                nav.currentTab = .trips
            case .myLoads:
                nav.currentTab = .wallet
            case .me:
                nav.currentTab = .me
            case .meDetail(let raw):
                // Switch to the Me tab first — if a sheet is about to
                // present, the user should see it layered over the right
                // surface. Then fire the notification carrying the
                // `MeDetailRoute.rawValue` so `DriverMePane` can flip its
                // `@State route` and open the sub-sheet.
                nav.currentTab = .me
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    NotificationCenter.default.post(
                        name: .esangOpenMeDetail,
                        object: raw
                    )
                }
            }
        case .openChat:
            nav.showeSang = true
        case .closeChat:
            nav.showeSang = false
        case .selectLoad:
            // The iOS shell doesn't yet expose a generic "open load by
            // id" pathway from the root (the per-surface sheet state is
            // local). Surface the driver's current active-load detail by
            // flipping to Home — ESANG's reply text already tells them
            // what they're looking at.
            nav.currentTab = .home
            trip.jump(to: .idle)
        case .refresh:
            // Broadcast a lightweight refresh signal; any surface that
            // wants to listen can observe the notification and re-run
            // its loader.
            NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
        }
    }

    // MARK: - Driver MeAction dispatcher
    //
    // Routes the keys posted by `MeAction.fire(_:)` from any Driver
    // Me-detail screen. Navigation-class keys flip the active tab or
    // open a Me sub-route via `.esangOpenMeDetail`; ack-class keys
    // (the Me-detail screen already mutated its own state) fall
    // through silently — the haptic in `MeAction.fire` is the
    // user-visible signal those land. Web-continuation keys hand off
    // to `app.eusotrip.com` in the in-app Safari sheet via
    // `\.driverWebContinuation`. No key drops into a void.
    private func handleDriverMeAction(key: String, userInfo: [AnyHashable: Any]) {
        switch key {
        // Navigation: load / bid / loadboard surfaces live under the
        // My Loads tab (the slot was renamed from "Wallet" to
        // "My Loads" 2026-05-07; the enum case stays `.wallet` for
        // back-compat with screen swap targets).
        //
        // `driver.load.detail` was previously routed here too, but
        // the founder bug 2026-05-07 surfaced that tapping a load
        // inside `108_MeLoadBoard` (Eusoboards) yanked the user to
        // My Loads — wrong destination. The fix lives at the source:
        // 108 now presents the canonical `LoadDetailSheet` IN-PLACE
        // via `.sheet(item:)` so the user stays inside Eusoboards.
        // Keeping `driver.load.detail` out of this tab-switch list
        // prevents the same regression from any future caller.
        case "driver.loadboard.open",
             "driver.bid.detail",
             "earnings.load.detail":
            nav.currentTab = .wallet
        case "driver.load.detail":
            // Intentionally NOT switching tabs. Source screens are
            // expected to handle the detail presentation locally
            // (sheet, push, in-place card). If a caller needs the
            // global Loads-tab path, they should fire
            // `driver.loadboard.open` instead.
            break

        // Me-detail sub-routes — switch tab + post the open-detail
        // notification consumed by `DriverMePane`.
        //
        // `zeun.report-breakdown` / `zeun.find-provider` are observability-only:
        // the Zeun Mechanics sheet that fires them already opens its own
        // sub-sheet (`showReporter` / `showProviders`) inline. Re-posting
        // `.esangOpenMeDetail` here would re-mount the Zeun parent and
        // collapse the just-presented sub-sheet — the founder bug where
        // tapping "Find a repair shop" appeared to kick the user back home.
        // Telemetry haptic already fired in `MeAction.fire(_:)`.
        case "zeun.report-breakdown", "zeun.find-provider":
            break
        // `carrier.attach-request` / `tax.download-1099` / `earnings.1099.download`
        // / `availability.export-ics` are fired from inside the corresponding
        // Me sub-sheet (Carrier, Tax, Availability) by buttons that already
        // open a sub-sheet (attach composer, PDF preview) or invoke an
        // external opener (ICS download). Re-posting `.esangOpenMeDetail`
        // re-mounts the parent sheet and collapses the sub-sheet — same
        // root cause as the Zeun "Find a repair shop" founder bug. The
        // local effect handles navigation; the notification is telemetry.
        case "carrier.attach-request",
             "tax.download-1099",
             "earnings.1099.download",
             "availability.export-ics":
            break

        // DVIR start: routed separately via `.eusoStartPretripDVIR`;
        // accepting here so the audit doesn't flag the key as
        // unhandled when ESANG fires it through this path too.
        case "dvir.start-pretrip":
            break

        // Wallet refresh — ask any wallet surface to reload after a
        // payment-method link round-trip completes.
        case "wallet.payment-method-linked":
            NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)

        // Ack-only: these keys originate inside Me-detail sheets that
        // already mutated their own local state on tap — the haptic
        // fired in `MeAction.fire(_:)` is the user-visible signal,
        // and the notification is reserved for downstream telemetry.
        case let k where k.hasPrefix("045."),
             let k where k.hasPrefix("049."),
             let k where k.hasPrefix("050."),
             let k where k.hasPrefix("051."),
             let k where k.hasPrefix("053."),
             let k where k.hasPrefix("054."),
             let k where k.hasPrefix("055."):
            break

        default:
            break
        }
    }

    // MARK: - Driver surface
    //
    // Branches on `nav.currentTab`. The .home case looks up the
    // ScreenRegistry entry whose id matches `trip.phase.screenId` —
    // so "which lifecycle screen to show" is a function of the trip's
    // state machine, not an index into a flat list. The three non-home
    // cases render their dedicated pane with a shared BottomNav
    // overlaid so slot taps route through the env handler and the
    // user can always get back to Home.
    @ViewBuilder
    private var driverSurface: some View {
        switch nav.currentTab {
        case .home:
            if let s = driverCurrentScreen {
                s.view(register.palette)
                    // Key on screen id ONLY. A dark-mode toggle rebuilds
                    // `register` — if rawValue is part of the identity
                    // here the whole lifecycle subtree (and trip-phase
                    // @State underneath) is torn down and SwiftUI snaps
                    // back to .idle / Dashboard. Palette updates reach
                    // the tree via `.environment(\.palette, ...)` below
                    // without needing a remount.
                    .id(s.id)
                    // Uniform cafe-door surface animation on every
                    // lifecycle-screen swap — fires fresh because the
                    // `.id` above remounts the view on each phase hop.
                    .screenTileRoot()
                    .transition(.opacity)
            } else {
                placeholder
                    .screenTileRoot()
            }
        case .trips:
            paneWithNav(.trips) { DriverTripsPane() }
        case .wallet:
            // Request 3 restructure: the former wallet tab is now the My
            // Loads surface (current / upcoming / pending / finished) with
            // ZEUN Mechanics + DVIR history entries. Wallet/earnings
            // content has been folded into `DriverMePane` via the
            // existing `.earnings` MeDetailRoute.
            paneWithNav(.wallet) { DriverLoadsPane() }
        case .me:
            // Founder direction 2026-05-04: driver Me adopts the
            // Shipper-320 parent-child hub design. `DriverMeSurface`
            // owns the navigation stack + back overlay + drills into
            // the existing leaf screens 060-110. Each registered hub
            // screen brings its own `Shell + driverMeHubNav` chrome
            // (same BottomNav slots as `paneWithNav(.me)` but with
            // Me current), so this branch renders the surface
            // directly without an outer pane wrapper to avoid
            // doubling up the BottomNav.
            DriverMeSurface(palette: register.palette)
        }
    }

    /// The driver-role ScreenRegistry entry that matches the current
    /// trip phase. Lookup-by-id rather than index so renames/reorders
    /// of the registry don't silently shift what Home renders.
    private var driverCurrentScreen: ProductionScreen? {
        ScreenRegistry.all.first { $0.id == trip.phase.screenId }
    }

    /// Wrap a pane (DriverTripsPane / DriverWalletPane / DriverMePane) in a
    /// ZStack with the shared BottomNav anchored to the bottom. The pane
    /// itself does its own scroll view; the nav floats over the content in
    /// the same floating-pill form used on 010-023. Taps on the nav route
    /// through the env-injected `driverNavHandler` so the call-site here
    /// doesn't need to know how switching works.
    @ViewBuilder
    private func paneWithNav<Pane: View>(
        _ tab: DriverNavController.Tab,
        @ViewBuilder _ pane: () -> Pane
    ) -> some View {
        ZStack(alignment: .bottom) {
            // Anchor the pane to the top edge. Without `alignment: .top` the
            // pane's content VStack gets vertically centered inside the
            // infinite frame, pushing titles ("Wallet", "Trips", "Me") down
            // into the middle of the screen. Top-alignment restores the
            // correct scroll-from-top layout used by the lifecycle screens.
            pane()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Nav-slot semantics (per user Request 3, 2026-04-19):
            //   • Home  — dashboard / lifecycle (trip.phase-driven)
            //   • Trips — Eusoboards public load board when idle; ALSO
            //             hosts the active-trip surface (map, nav, SOS)
            //             when a trip is active. DriverTripsPane branches
            //             internally on trip.phase.isActiveTrip.
            //   • Loads — My Loads (current / upcoming / pending /
            //             finished) + ZEUN Mechanics entry + DVIR
            //             history. Formerly the "Wallet" slot; wallet
            //             content folded into Me · Earnings.
            //   • Me    — profile, earnings, compliance, reputation.
            BottomNav(
                leading: [
                    NavSlot(label: "Home",  systemImage: "house",     isCurrent: tab == .home),
                    NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: tab == .trips)
                ],
                trailing: [
                    NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: tab == .wallet),
                    NavSlot(label: "Me",    systemImage: "person",           isCurrent: tab == .me)
                ]
            )
        }
        // Key by the tab so SwiftUI rebuilds the branch on every tab
        // switch, which re-triggers the cafe-door surface animation
        // below. Without this id the view is reused and the @State
        // that drives TileRevealModifier stays `true`, meaning the
        // animation would only play the very first time a tab is
        // opened in the session. Re-playing on every selection is
        // the whole point of the uniform screen animation.
        .id("pane-\(tab.rawValue)")
        .screenTileRoot()
        .transition(.opacity)
    }

#if DEBUG
    // MARK: - Dev chrome (DEBUG only)
    //
    // Everything from `chromeSheet` through `devChromeNext` is the dev
    // chrome surface: role tabs, register pin, prev/next walker, step
    // ordinal readout. None of it compiles into TestFlight / App Store
    // builds. Production renders only `driverSurface`.

    private var chromeSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                registerSwitch
                roleTabs
                screenTitle
                nextPrevBar
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
            VStack(alignment: .leading, spacing: 0) {
                Text("EusoTrip")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(register.palette.textPrimary)
                Text("by Eusorone Technologies, Inc. · ESANG AI™")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(register.palette.textTertiary)
            }
            Spacer()
            if selectedRole == .driver {
                // Driver role: phase-based breadcrumb.
                Text("\(trip.phase.screenId) · \(trip.phase.stepOrdinal)/\(TripPhase.allCases.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(register.palette.textSecondary)
            } else if let s = current {
                // Other roles: index-based (placeholders are sequential).
                Text("\(s.id) · \(currentIndex + 1)/\(screens.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(register.palette.textSecondary)
            }
        }
    }

    private var registerSwitch: some View {
        HStack(spacing: 6) {
            ForEach(ThemeRegister.allCases) { r in
                Button {
                    register = r
                    // Pin this choice — stop auto-following iOS system
                    // appearance so reviewers can lock Night or Afternoon
                    // for a fidelity walk without the simulator overriding.
                    userOverrodeRegister = true
                } label: {
                    Text(r.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            Capsule().fill(register == r
                                           ? AnyShapeStyle(LinearGradient.diagonal)
                                           : AnyShapeStyle(register.palette.bgCard))
                        )
                        .foregroundStyle(register == r ? .white : register.palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var roleTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProductionScreen.Role.allCases) { role in
                    let isOn = selectedRole == role
                    let hasContent = !ScreenRegistry.forRole(role).isEmpty
                    Button {
                        if hasContent { selectedRole = role }
                    } label: {
                        Text(role.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(
                                isOn ? register.palette.textPrimary :
                                hasContent ? register.palette.textSecondary :
                                register.palette.textTertiary
                            )
                            .background(
                                Capsule().stroke(
                                    isOn ? register.palette.borderStrong : register.palette.borderFaint,
                                    lineWidth: 1
                                )
                            )
                            .opacity(hasContent ? 1.0 : 0.45)
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasContent)
                }
            }
        }
    }

    private var screenTitle: some View {
        HStack {
            Text(devChromeTitle.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(register.palette.textTertiary)
            Spacer()
        }
    }

    /// Dev-chrome title label. Uses the trip phase's display name for
    /// the driver role (the authoritative "what surface is live"), and
    /// falls back to the registry title for placeholder roles.
    private var devChromeTitle: String {
        if selectedRole == .driver {
            return trip.phase.displayName
        }
        return current?.title ?? "—"
    }
#endif

    /// Deep-fallback empty state for `driverSurface` when the trip phase
    /// doesn't resolve to a registered screen. In practice every phase
    /// has a matching entry so this should never render; it's here to
    /// satisfy the exhaustive branch without leaking any chrome text
    /// into the user-facing build.
    private var placeholder: some View {
        VStack(spacing: 8) {
            Text("Preparing your surface…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(register.palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

#if DEBUG
    private var nextPrevBar: some View {
        HStack(spacing: 10) {
            Button {
                devChromePrev()
            } label: {
                Label("Prev", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(register.palette.bgCard)
                    .foregroundStyle(register.palette.textPrimary)
                    .clipShape(Circle())
            }
            .disabled(!canStepBack)
            .opacity(canStepBack ? 1.0 : 0.35)
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Dev-chrome progress bar — gradient per doctrine §2.1
            // (no flat Brand.blue). Uses the trip phase ordinal for
            // the driver role, currentIndex for placeholders.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(register.palette.borderFaint)
                        .frame(height: 3)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(
                            width: max(0, geo.size.width * devChromeProgress),
                            height: 3
                        )
                }
            }
            .frame(maxWidth: 220, maxHeight: 3)

            Spacer(minLength: 0)

            Button {
                devChromeNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient.diagonal)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .disabled(!canStepForward)
            .opacity(canStepForward ? 1.0 : 0.35)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Dev-chrome step helpers
    //
    // Unified across driver and non-driver roles. Driver role drives
    // the trip state machine; everything else still walks the
    // ScreenRegistry by index.

    private var canStepBack: Bool {
        if selectedRole == .driver {
            return trip.phase.happyPathPrev != nil
        }
        return currentIndex > 0
    }

    private var canStepForward: Bool {
        if selectedRole == .driver {
            // Happy path always has a next step (loops at .nextLoadBrief
            // back to .idle), so forward is always enabled in driver mode.
            return true
        }
        return currentIndex < screens.count - 1
    }

    private var devChromeProgress: CGFloat {
        if selectedRole == .driver {
            return CGFloat(trip.phase.stepOrdinal)
                 / CGFloat(max(1, TripPhase.allCases.count))
        }
        guard !screens.isEmpty else { return 0 }
        return CGFloat(currentIndex + 1) / CGFloat(max(1, screens.count))
    }

    private func devChromePrev() {
        if selectedRole == .driver {
            trip.stepBack()
        } else {
            currentIndex = max(0, currentIndex - 1)
        }
    }

    private func devChromeNext() {
        if selectedRole == .driver {
            trip.advance()
        } else {
            currentIndex = min(screens.count - 1, currentIndex + 1)
        }
    }
#endif
}

// MARK: - Previews

#Preview("Root · Night") {
    ContentView().preferredColorScheme(.dark)
}

#Preview("Root · Afternoon") {
    ContentView().preferredColorScheme(.light)
}
