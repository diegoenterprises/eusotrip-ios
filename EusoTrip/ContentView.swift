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
import Combine

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
            .init(id: "059E", title: "Vehicle & Equipment",         role: .driver) { p in AnyView(VehicleAndEquipmentScreen(theme: p)) },
            .init(id: "060", title: "The Haul · Dashboard",         role: .driver) { p in AnyView(TheHaulShellScreen(theme: p)) },
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
            // Driver Wallet card-style picker — same pure WalletCardPickerView as the
            // shipper "WalletCardStyle" entry, wrapped in driver Me chrome. Reached from
            // the driver Wallet hub (069) "Wallet card style" row via .eusoDriverMeNavSwap.
            .init(id: "WalletCardStyleDriver", title: "Driver · Wallet Card Style", role: .driver) { p in AnyView(DriverWalletCardStyleScreen(theme: p)) },
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
            .init(id: "108", title: "Driver · Eusoboards",          role: .driver) { p in AnyView(MeLoadBoardScreen(theme: p)) },
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
            // 2026-07-03 — Driver paperwork band: 114 DVIR Composite S13-S14
            // Acked Pickup Roll + 145-148 CEL M04 quartet. loadId "0" matches
            // the 149 registry convention — surfaces live-bind whatever load
            // id is passed at presentation and render honest "-" states otherwise.
            .init(id: "114",   title: "Driver · Zeun DVIR Complete · Pickup Roll", role: .driver) { p in AnyView(DriverDvirCompositePickupRollScreen(theme: p, loadId: "0")) },
            .init(id: "145",   title: "Driver · Pickup Departed",     role: .driver) { p in AnyView(DriverPickupDepartedCelM04Screen(theme: p, loadId: "0")) },
            .init(id: "146",   title: "Driver · In Transit",          role: .driver) { p in AnyView(DriverInTransitCelM04Screen(theme: p, loadId: "0")) },
            .init(id: "147",   title: "Driver · At Delivery Arrival", role: .driver) { p in AnyView(DriverAtDeliveryArrivalCelM04Screen(theme: p, loadId: "0")) },
            .init(id: "148",   title: "Driver · POD Sign + Unload",   role: .driver) { p in AnyView(DriverPodSignUnloadCelM04Screen(theme: p, loadId: "0")) },
            .init(id: "109", title: "Me · Bid Detail",              role: .driver) { p in AnyView(MeBidDetailScreen(theme: p, loadId: 0)) },
            .init(id: "110", title: "Me · Auto-Accept",             role: .driver) { p in AnyView(MeAutoAcceptRulesScreen(theme: p)) },
            // 2026-05-21 — Bonus Tracker port (web BonusTracker.tsx → iOS).
            .init(id: "111", title: "Me · Bonus Tracker",           role: .driver) { p in AnyView(DriverBonusTrackerScreen(theme: p)) },
            // 2026-05-31 — Rescue land: bespoke Driver Paperwork (full port). SVG 111 axis; iOS 111 already maps to Me·Bonus, so id 111p.
            .init(id: "111p", title: "Driver · Paperwork",            role: .driver) { p in AnyView(DriverPaperworkScreen(theme: p)) },
            // 2026-05-31 — Zeun #45 part-diagnosis (vision · zeunMechanics.diagnosePart).
            // Reached in production through MeZeunView's "Diagnose a part with
            // a photo" action; registry row paints it for the A→Z walker.
            .init(id: "113", title: "Me · Zeun Part Diagnosis",     role: .driver) { p in AnyView(MeZeunDiagnoseScreen(theme: p)) },
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
            // 2026-05-30 — the-oath §42/§48 driver ports.
            .init(id: "112",    title: "Driver · Load Closed (Settlement)", role: .driver) { p in AnyView(DriverClosedScreen(theme: p)) },
            .init(id: "161",    title: "Driver · Gate Pass",         role: .driver) { p in AnyView(DriverGatePass_161(appointmentId: 0).environment(\.palette, p)) },
            .init(id: "162",    title: "Driver · Wellness & Fatigue", role: .driver) { p in AnyView(DriverWellnessFatigue_162().environment(\.palette, p)) },
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
        //
        // Emergency Wave I1 (2026-06-11) — the registry entry no
        // longer mounts the `loadId:"0"` sentinel. The server
        // returns `null` AS SUCCESS for id<=0, so a sentinel mount
        // rendered the loading skeleton forever (the founder's dead
        // 205). 205 requires a real load id: every real path routes
        // through `ShipperSurface.activeLoadId` (captured via the
        // ShipperLoadIdResolver gate); reaching THIS entry means no
        // load context exists, so it renders the explicit
        // "Select a load" state — never a fake detail.
        list.append(
            .init(id: "205", title: "Shipper · Load Detail", role: .shipper) { p in
                AnyView(ShipperLoadDetailUnresolvedScreen(theme: p))
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
        // 2026-06-02 — dedup: dropped id "208" (legacy ShipperPaymentMethodsScreen),
        // superseded by canonical 295 PaymentMethodsScreen (which the Me hub links).
        // 208 was referenced 0×; file kept on disk, just unregistered.
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
        list.append(.init(id: "225", title: "Shipper · Hot Zones",       role: .shipper) { p in AnyView(MarketHubScreen(theme: p, initialTab: .hotZones)) })
        list.append(.init(id: "226", title: "Shipper · Document Center", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperDocumentCenter() }) })
        list.append(.init(id: "227", title: "Shipper · Settlement Detail", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperSettlementDetail() }) })
        // 2026-07-10 — Commodity + cross-border post-load addenda ports
        // (204D/E/F/G/H · 216C/E/G). Off-ring detail surfaces drilled from
        // the load (204·205) / cross-border (216B) context; registered so
        // the Shipper surface + ESANG/deep-link nav can route to each.
        // currentSlot: .none — none of the four bottom-nav slots is active
        // on an off-ring detail (same pattern as 227 Settlement Detail).
        list.append(.init(id: "204D", title: "Shipper · Oversize Permit & Escort",     role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperOversizePermitEscort() }) })
        list.append(.init(id: "204E", title: "Shipper · Livestock 28-Hour Clock",      role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperLivestock28HourClock() }) })
        list.append(.init(id: "204F", title: "Shipper · Auto-Transport VIN & Condition", role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperAutoTransportVINCondition() }) })
        list.append(.init(id: "204G", title: "Shipper · HHG Chain of Custody",         role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperHHGChainOfCustody() }) })
        list.append(.init(id: "204H", title: "Shipper · Flatbed Cargo Securement",     role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperFlatbedCargoSecurement() }) })
        list.append(.init(id: "216C", title: "Shipper · Carta Porte CFDI",             role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperCartaPorteCFDI() }) })
        list.append(.init(id: "216E", title: "Shipper · VUCEM Pedimento",              role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperVUCEMPedimento() }) })
        list.append(.init(id: "216G", title: "Shipper · MX Landed Cost",               role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .none) { ShipperMXLandedCost() }) })
        list.append(.init(id: "228", title: "Shipper · BOLs",            role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .me) { ShipperBOLs() }) })
        list.append(.init(id: "229", title: "Shipper · Allocations",     role: .shipper) { p in AnyView(wrapShipperScreen(palette: p, currentSlot: .loads) { ShipperAllocations() }) })
        // 2026-06-09 registry dedup: Market Intelligence was registered as
        // "233", colliding with (and shadowing) "233" Watch Complication —
        // the /shipper/watch deep-link rendered this screen instead. The
        // 231-240 series owns "233" (Watch); Market Intelligence re-id'd
        // to the free slot "330". Me-hub VISIBILITY cell updated to match.
        list.append(.init(id: "330", title: "Shipper · Market Intelligence", role: .shipper) { p in AnyView(MarketHubScreen(theme: p, initialTab: .market)) })
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
        // Wave I1/I2 contract: `product` defaults to nil here (bare
        // open = manual search). The 424→425 handoff carries the
        // matched grade through `ShipperSurface.activePortIntelProduct`,
        // which overrides this registration with
        // `PortIntelligenceScreen(theme:product:)` pre-filled.
        list.append(.init(id: "425", title: "Shipper · Port Intelligence",       role: .shipper) { p in AnyView(PortIntelligenceScreen(theme: p, product: nil)) })
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
        // 260 (PostedAwaitingBids) un-shelved 2026-05-31 — renders
        // from `shippers.getLifecycleSnapshot` + cancels via the real
        // `loads.cancel` proc. 254 "Track this load" deep-links here
        // for a freshly posted load (POSTED / awaiting-bids state).
        list.append(.init(id: "260", title: "Shipper · Posted · Awaiting Bids", role: .shipper) { p in AnyView(PostedAwaitingBidsScreen(theme: p, loadId: "0")) })
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
        // Wallet card-style picker — pure style chooser (no load). Server:
        // eusoWallet.listWalletThemes / getWalletTheme / setWalletTheme. Reached
        // from the Wallet hub "Wallet card style" row via .eusoShipperNavSwap.
        list.append(.init(id: "WalletCardStyle", title: "Shipper · Wallet Card Style", role: .shipper) { p in AnyView(WalletCardStyleScreen(theme: p)) })
        list.append(.init(id: "292", title: "Shipper · Settlements List",        role: .shipper) { p in AnyView(SettlementsListScreen(theme: p)) })
        list.append(.init(id: "437", title: "Shipper · Invoices & AR",           role: .shipper) { p in AnyView(ShipperInvoicesScreen(theme: p)) })
        list.append(.init(id: "293", title: "Shipper · Settlement Detail",       role: .shipper) { p in AnyView(SettlementDetailScreen(theme: p, settlementId: "0")) })
        list.append(.init(id: "294", title: "Shipper · Dispute Settlement",      role: .shipper) { p in AnyView(DisputeSettlementScreen(theme: p, settlementId: "0")) })
        list.append(.init(id: "295", title: "Shipper · Payment Methods",         role: .shipper) { p in AnyView(PaymentMethodsScreen(theme: p)) })
        // §40 — Shipper Dock Appointments (registry "295" is Payment Methods, so this
        // takes a distinct id). ShipperDockAppointments owns its chrome (ShipperScreenWrap)
        // + reads @Environment(\.palette); wired to appointments.{list,getSummary,assignHazmatBay}.
        list.append(.init(id: "ShipDock295", title: "Shipper · Dock Appointments", role: .shipper) { p in AnyView(ShipperDockAppointments().environment(\.palette, p)) })
        list.append(.init(id: "296", title: "Shipper · Add Payment Method",      role: .shipper) { p in AnyView(AddPaymentMethodScreen(theme: p)) })
        list.append(.init(id: "297", title: "Shipper · Monthly Statement",       role: .shipper) { p in AnyView(MonthlyStatementScreen(theme: p)) })
        list.append(.init(id: "298", title: "Shipper · Sustainability",          role: .shipper) { p in AnyView(SustainabilityScreen(theme: p)) })
        list.append(.init(id: "299", title: "Shipper · Reports",                 role: .shipper) { p in AnyView(ReportsScreen(theme: p)) })
        // 2026-06-09 — 300-309 documents/signing cluster EXPLICITLY RETIRED
        // (DocumentsAll, Pdf/ImageViewer, EusoTicket BOL/RunTicket/Haul,
        // BolCounterSign, RateConSign, PodPhotoCapture, WalletPass). Never
        // registered, zero external references; the canonical shipper
        // document surface is 226 ShipperDocumentCenter (the six lifecycle
        // CTAs in 262/266/271/272/273/274 were retargeted 300 → 226).
        // Do NOT register the orphans without a loadId/docId context plan.
        // 2026-05-30 — the-oath §46/§52 shipper ports (id-prefixed; bare 297/298 are taken above).
        list.append(.init(id: "Ship297Ins", title: "Shipper · Cargo Insurance",  role: .shipper) { p in AnyView(ShipperCargoInsurance().environment(\.palette, p)) })
        list.append(.init(id: "Ship298Det", title: "Shipper · Detention Exposure", role: .shipper) { p in AnyView(ShipperDetentionExposureScreen(theme: p)) })

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
        list.append(.init(id: "321C", title: "Carrier · Truck Posting",    role: .carrier) { p in AnyView(CarrierTruckPostingScreen(theme: p)) })
        list.append(.init(id: "350", title: "Carrier · Me",                role: .carrier) { p in AnyView(CarrierMeScreen(theme: p)) })
        // 2026-06-02 — WAVE 1: the 5 missing role Me hubs (kill Me→Home
        // dead-routes). Each mirrors 350_CarrierMe chrome, indexes its
        // role's real registered screens, and is bound as the Me-slot
        // tabRoot via <Role>NavRoute.map["me"] + <Role>Surface.tabRoots.
        list.append(.init(id: "404B", title: "Broker · Me",                role: .broker)     { p in AnyView(BrokerMeScreen(theme: p)) })
        list.append(.init(id: "620",  title: "Escort · Me",                role: .escort)     { p in AnyView(EscortMeHomeScreen(theme: p)) })
        list.append(.init(id: "703",  title: "Terminal · Me",              role: .terminal)   { p in AnyView(TerminalMeScreen(theme: p)) })
        list.append(.init(id: "804",  title: "Admin · Me",                 role: .admin)      { p in AnyView(AdminMeScreen(theme: p)) })
        list.append(.init(id: "903",  title: "Compliance · Me",            role: .compliance) { p in AnyView(ComplianceMeScreen(theme: p)) })
        // ComplianceAgentView (DG segregation tool) — was the lone
        // unregistered Compliance orphan; now housed in 903's TOOLS group.
        list.append(.init(id: "904",  title: "Compliance · Segregation Agent", role: .compliance) { _ in AnyView(ComplianceAgentView()) })
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
        list.append(contentsOf: [
            .init(id: "373", title: "Catalyst · Awarded (M04)", role: .catalyst) { p in AnyView(CatalystAwardedCelM04Screen(theme: p)) },
            .init(id: "374", title: "Catalyst · Pickup On-Site Echo (M04)", role: .catalyst) { p in AnyView(CatalystPickupOnSiteEchoCelM04Screen(theme: p)) },
            .init(id: "375", title: "Catalyst · In-Transit Fleet Track (M04)", role: .catalyst) { p in AnyView(CatalystInTransitFleetTrackCelM04Screen(theme: p)) },
            .init(id: "376", title: "Catalyst · At-Delivery Fleet Track (M04)", role: .catalyst) { p in AnyView(CatalystAtDeliveryFleetTrackCelM04Screen(theme: p)) },
        ])
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
        // 2026-05-30 — Catalyst intelligence band 399-403 (port wave 14, closes the 383-403 NEW band).
        list.append(.init(id: "Cat399", title: "Catalyst · Toll Corridor Cost",  role: .catalyst) { p in AnyView(CatalystTollCorridorCostScreen(theme: p)) })
        list.append(.init(id: "Cat400", title: "Catalyst · Convoy Platooning",   role: .catalyst) { p in AnyView(CatalystConvoyPlatooningScreen(theme: p)) })
        list.append(.init(id: "Cat401", title: "Catalyst · Crew Wellness",       role: .catalyst) { p in AnyView(CatalystCrewWellnessScreen(theme: p)) })
        list.append(.init(id: "Cat402", title: "Catalyst · Capacity Planner",    role: .catalyst) { p in AnyView(CatalystCapacityPlannerScreen(theme: p)) })
        list.append(.init(id: "Cat403", title: "Catalyst · Fleet Carbon",        role: .catalyst) { p in AnyView(CatalystFleetCarbonScreen(theme: p)) })
        // 2026-05-29 — Catalyst fleet/finance band 383-390 (port wave 12).
        // Bespoke ports of `03 Catalyst/Code/` canonical bricks, wired to real
        // routers (csaScores, ifta, dataqs, fuelMgmt, shipperFreightClaims) with
        // honest // WIRE: markers where no iOS client method exists yet. Numeric
        // 383-390 are Shipper slots, so these take role-prefixed Cat383-Cat390 ids.
        list.append(.init(id: "Cat383", title: "Catalyst · Fleet Safety CSA",     role: .catalyst) { p in AnyView(CatalystFleetSafetyCSA().environment(\.palette, p)) })
        list.append(.init(id: "Cat384", title: "Catalyst · Fleet IFTA",           role: .catalyst) { p in AnyView(CatalystFleetIFTAScreen(theme: p)) })
        list.append(.init(id: "Cat385", title: "Catalyst · Roadside DataQ",       role: .catalyst) { p in AnyView(CatalystRoadsideDataQ().environment(\.palette, p)) })
        list.append(.init(id: "Cat386", title: "Catalyst · Fuel Card Fleet",      role: .catalyst) { p in AnyView(CatalystFuelCardFleetScreen(theme: p)) })
        list.append(.init(id: "Cat387", title: "Catalyst · Reefer Fleet Monitor", role: .catalyst) { p in AnyView(CatalystReeferFleetMonitorScreen(theme: p)) })
        list.append(.init(id: "Cat388", title: "Catalyst · Tanker Fleet Monitor", role: .catalyst) { p in AnyView(CatalystTankerFleetMonitorScreen(theme: p)) })
        list.append(.init(id: "Cat389", title: "Catalyst · Cargo Claim",          role: .catalyst) { p in AnyView(CatalystCargoClaimScreen(theme: p)) })
        list.append(.init(id: "Cat390", title: "Catalyst · EDI Messages",         role: .catalyst) { p in AnyView(CatalystEDIMessagesScreen(theme: p)) })
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
        // POD · run-ticket · haul-receipt rendering surface — the Catalyst
        // reviews the as-rendered EusoTicket document for the active load
        // before dispatching to the shipper-of-record and the receiver.
        // 2026-06-06 — routes the REAL selected load via
        // `BrokerNavContext.latestLoadId` (was hardcoded "0", which made
        // fetchLoad early-return and paint a fabricated sample BOL). Wired
        // to `loads.getDetail`/`loads.getById` for the previewed load +
        // `eusoTicket.generateBOLPDF` on Send; QR uses the canonical
        // `EusoQRView` (kind `.eusoTicket(.bol)`, role `.carrier`) so the
        // same QR scans into the iOS deep-link handler and the web router.
        list.append(
            .init(id: "313", title: "Catalyst · EusoTicket Renderer", role: .catalyst) { p in
                AnyView(CatalystEusoTicketRendererScreen(theme: p, loadId: BrokerNavContext.latestLoadId))
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
        // 2026-06-02 — dedup: catalyst profile re-id'd 302→302C to end the
        // id collision with Carrier·Load Detail ("302", .carrier), which
        // (since allowedScreenRoles(.catalyst)=[.carrier,.catalyst], .carrier
        // first) had shadowed CatalystProfileScreen entirely. Now reachable
        // via 350 Account → Profile.
        list.append(.init(id: "302C", title: "Catalyst · Profile",        role: .catalyst) { p in AnyView(CatalystProfileScreen(theme: p)) })
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
        // 2026-05-31 — Rescue land: bespoke pixel-faithful 244/245 At-Dock + Departing (full ports; structs take loadId, not theme).
        list.append(.init(id: "244b", title: "Shipper · At Dock (Bespoke)",   role: .shipper) { _ in AnyView(ShipperAtDock()) })
        list.append(.init(id: "245b", title: "Shipper · Departing (Bespoke)", role: .shipper) { _ in AnyView(ShipperDeparting(loadId: "0")) })
        list.append(.init(id: "246", title: "Shipper · Pre-Delivery",   role: .shipper) { p in AnyView(ShipperPreDeliveryScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "247", title: "Shipper · At Delivery",    role: .shipper) { p in AnyView(ShipperAtDeliveryScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "249", title: "Shipper · Load Closed",    role: .shipper) { p in AnyView(ShipperLoadClosedScreen(theme: p, loadId: "0")) })
        list.append(.init(id: "306", title: "Catalyst · Driver Payroll", role: .catalyst) { p in AnyView(CatalystDriverPayrollScreen(theme: p)) })
        list.append(.init(id: "308", title: "Catalyst · Authority + Insurance", role: .catalyst) { p in AnyView(CatalystAuthorityInsuranceScreen(theme: p)) })
        list.append(.init(id: "312", title: "Catalyst · Hot Zones",        role: .catalyst) { p in AnyView(CatalystHotZonesScreen(theme: p)) })
        list.append(.init(id: "314", title: "Catalyst · Maintenance Zeun", role: .catalyst) { p in AnyView(CatalystMaintenanceZeunScreen(theme: p)) })
        list.append(.init(id: "319", title: "Catalyst · Wallet",           role: .catalyst) { p in AnyView(CatalystWalletScreen(theme: p)) })
        // Catalyst/Carrier Wallet card-style picker — same pure WalletCardPickerView
        // as the shipper "WalletCardStyle" / driver "WalletCardStyleDriver" entries,
        // wrapped in the catalyst/carrier Wallet chrome. role:.catalyst so it lands in
        // the concatenated .carrier+.catalyst pool CarrierSurface resolves, serving BOTH
        // surfaces. Reached from the catalyst Wallet hub (319) AND the carrier Earnings
        // hub (312) "Wallet card style" row via .eusoCarrierNavSwap. Server:
        // eusoWallet.listWalletThemes / getWalletTheme / setWalletTheme.
        list.append(.init(id: "WalletCardStyleCatalyst", title: "Catalyst · Wallet Card Style", role: .catalyst) { p in AnyView(CatalystWalletCardStyleScreen(theme: p)) })
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

        // 2026-07-03 — New Wave 07-Escort band: ES-01 Convoy Comms /
        // ES-02 Height Pole / ES-07 Settlement Detail (iOS 603/604/605).
        // Pushed surfaces reached from the Escort Me hub (620) rows —
        // not tab roots, so EscortNavRoute/tabRoots stay untouched.
        list.append(.init(id: "603", title: "Escort · Convoy Comms", role: .escort) { p in AnyView(EscortConvoyCommsScreen(theme: p)) })
        list.append(.init(id: "604", title: "Escort · Height Pole", role: .escort) { p in AnyView(EscortHeightPoleScreen(theme: p)) })
        list.append(.init(id: "605", title: "Escort · Settlement Detail", role: .escort) { p in AnyView(EscortSettlementDetailScreen(theme: p, assignmentId: "0")) })  // pushed surface; pass a real assignment id via the entry-point row when navigating
        list.append(.init(id: "608", title: "Escort · Vehicle Check", role: .escort) { p in AnyView(EscortVehicleCheckScreen(theme: p, assignmentId: "0")) })  // ES-06 pre-trip equipment gate; resolves the active assignment when id is "0"
        list.append(.init(id: "606", title: "Escort · Route Survey", role: .escort) { p in AnyView(EscortRouteSurveyScreen(theme: p, assignmentId: "0")) })  // ES-03 pre-move hazard log; resolves the active assignment when id is "0"
        list.append(.init(id: "609", title: "Escort · Jurisdiction Handoff", role: .escort) { p in AnyView(EscortJurisdictionHandoffScreen(theme: p, assignmentId: "0")) })  // ES-05 state-line LEO handoff; resolves the active assignment when id is "0"
        list.append(.init(id: "610", title: "Escort · Cert Reciprocity", role: .escort) { p in AnyView(EscortCertReciprocityScreen(theme: p)) })  // ES-08 iOS peer of the live web cert-reciprocity page (spine already live)
        list.append(.init(id: "607", title: "Escort · Permit & Requirements", role: .escort) { p in AnyView(EscortPermitRequirementsScreen(theme: p)) })  // ES-04 per-state OS/OW matrix from escorts.getStateRequirements

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
            // Terminal · Access control · scan — the access-controller side of
            // the staff ACCESS CARD. A gate guard / temporary access-card
            // scanner scans a staff member's access-card QR or types the
            // 6-digit code, and `terminals.verifyStaffAccess` answers honestly
            // (valid / expired / denied — never a fabricated pass). Reached
            // from 700_TerminalHome ("Access control · scan") and 703 Me
            // (Operations). A pushed leaf (not a tabRoot) via .eusoTerminalNavSwap.
            .init(id: "TerminalAccessScan", title: "Terminal · Access control · scan", role: .terminal) { p in AnyView(TerminalAccessScanScreen(theme: p)) },
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
            // 2026-06-02 — Dpch700 "Dispatch · Home" RETIRED: it was the
            // quarantined 700-series invention (no SVG provenance, Drivers/
            // Loads nav). Canonical home is now Disp400 (verbatim 400 SVG
            // port, more wired). 2026-06-09 — 700_DispatchHome.swift DELETED
            // from disk + target (zero references; its stray "703" post was
            // a Terminal id and died with it). Driver roster (Dpch701) +
            // load queue (Dpch702) remain registered + reachable via the
            // Dpch713 Me hub and the drivers/loads label aliases.
            .init(id: "Dpch701", title: "Dispatch · Driver Board",     role: .dispatch) { p in AnyView(DispatchDriverBoardScreen(theme: p)) },
            // §37 — Dispatcher 404 Driver Roster (HOS-urgency-sorted roster; wires dispatch.getDriverRoster).
            .init(id: "Dpch404", title: "Dispatch · Driver Roster",    role: .dispatch) { p in AnyView(DispatcherDriverRosterScreen(theme: p)) },
            .init(id: "Dpch702", title: "Dispatch · Load Assignment",  role: .dispatch) { p in AnyView(DispatchLoadAssignmentScreen(theme: p)) },
            .init(id: "Dpch703", title: "Dispatch · Exception Triage", role: .dispatch) { p in AnyView(DispatchExceptionTriageScreen(theme: p)) },
            .init(id: "Dpch704", title: "Dispatch · HOS Alerts",       role: .dispatch) { p in AnyView(DispatchHOSAlertsScreen(theme: p)) },
            .init(id: "Dpch705", title: "Dispatch · Route Optimization", role: .dispatch) { p in AnyView(DispatchRouteOptimizationScreen(theme: p)) },
            .init(id: "Dpch706", title: "Dispatch · Driver Chat",      role: .dispatch) { p in AnyView(DispatchDriverChatScreen(theme: p)) },
            .init(id: "Dpch707", title: "Dispatch · Daily KPI",        role: .dispatch) { p in AnyView(DispatchDailyKPIScreen(theme: p)) },
            // 2026-06-02 — Dpch708 "Dispatch · Kanban Board" RETIRED: superseded
            // by canonical Disp401 (verbatim 401 SVG port, same endpoints).
            // 2026-06-09 — 708_DispatchKanbanBoard.swift DELETED from disk +
            // target (zero references; Disp400's "Open the Board" CTA now
            // posts "Disp401" instead of the stale "708").
            // 2026-05-31 — Rescue land: bespoke Dispatcher greenfield home + kanban (full ports).
            .init(id: "Disp400", title: "Dispatch · Home",            role: .dispatch) { p in AnyView(DispatcherHomeScreen(theme: p)) },
            .init(id: "Disp401", title: "Dispatch · Kanban",          role: .dispatch) { p in AnyView(DispatcherKanbanScreen(theme: p)) },
            .init(id: "Dpch709", title: "Dispatch · Bulk Upload Kanban", role: .dispatch) { p in AnyView(DispatchBulkUploadKanbanScreen(theme: p)) },
            .init(id: "Dpch710", title: "Dispatch · Run Ticket Capture", role: .dispatch) { p in AnyView(DispatchRunTicketCaptureScreen(theme: p)) },
            .init(id: "Dpch711", title: "Dispatch · Price Book",       role: .dispatch) { p in AnyView(DispatchPriceBookScreen(theme: p)) },
            .init(id: "Dpch712", title: "Dispatch · Reports Hub",      role: .dispatch) { p in AnyView(DispatchReportsHubScreen(theme: p)) },
            // 2026-05-21 dead-button fix — dedicated Dispatch Me hub. The
            // bottom-nav "Me" slot used to map to Dpch700 (Home), a
            // functional dead-end. Now points here. Links to all 13
            // registered dispatch screens via .eusoDispatchNavSwap.
            .init(id: "Dpch713", title: "Dispatch · Me",               role: .dispatch) { p in AnyView(DispatchMeScreen(theme: p)) },
            // 2026-06-02 — WAVE-0 orphan recovery: 710A ConvoyComposer
            // (T-023, fully built, was never registered). Reachable via
            // Dpch713 Me → TOOLS → "Convoy composer".
            .init(id: "Dpch710A", title: "Dispatch · Convoy Composer",  role: .dispatch) { p in
                let loadId = ShipperLoadIdResolver.normalize(BrokerNavContext.latestLoadId)
                let loadNumber = ShipperLoadIdResolver.normalize(BrokerNavContext.latestLoadNumber) ?? loadId
                return AnyView(DispatchConvoyComposerScreen(theme: p, loadId: loadId, loadNumber: loadNumber))
            },
            // 2026-06-03 — landed 3 scheduled-lane ports from _PORT_STAGING.
            // Dpch402 (NOT "402" — that id is Broker·Tender Detail).
            .init(id: "Dpch402", title: "Dispatch · Profile",           role: .dispatch) { p in AnyView(DispatcherProfileScreen(theme: p)) },
            .init(id: "Vesl004", title: "Vessel Shipper · Demurrage & Detention", role: .shipper) { p in AnyView(VesselDemurrageDetentionScreen(theme: p)) },
            .init(id: "Rail008", title: "Rail Shipper · Tender Workflow", role: .shipper) { _ in AnyView(RailShipperTenderWorkflow_008()) },
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
            .init(id: "Dpch801", title: "Dispatch · BH Tender Resolved",  role: .dispatch) { p in AnyView(DispatcherBHTenderResolved515Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch802", title: "Dispatch · BH Pickup Armed",     role: .dispatch) { p in AnyView(DispatcherBHPickupArmed516Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch803", title: "Dispatch · BH Pickup Fired",     role: .dispatch) { p in AnyView(DispatcherBHPickupFired517Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch804", title: "Dispatch · BH In-Transit",       role: .dispatch) { p in AnyView(DispatcherBHInTransit518Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch805", title: "Dispatch · BH Approach",         role: .dispatch) { p in AnyView(DispatcherBHApproaching519Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch806", title: "Dispatch · BH At Delivery",      role: .dispatch) { p in AnyView(DispatcherBHAtDelivery520Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch807", title: "Dispatch · BH Docked Loading",   role: .dispatch) { p in AnyView(DispatcherBHDockedLoading521Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch808", title: "Dispatch · BH BOL Pre-Sign",     role: .dispatch) { p in AnyView(DispatcherBHBolPreSign522Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch809", title: "Dispatch · BH BOL Signed",       role: .dispatch) { p in AnyView(DispatcherBHBolSigned523Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch810", title: "Dispatch · BH Paperwork",        role: .dispatch) { p in AnyView(DispatcherBHPaperwork524Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch811", title: "Dispatch · BH Closed",           role: .dispatch) { p in AnyView(DispatcherBHClosed525Screen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-21 — Dispatcher M-04 kanban quintet (SVG 526-530).
            .init(id: "Dpch820", title: "Dispatch · M-04 Awarded Kanban", role: .dispatch) { p in AnyView(DispatcherM04AwardedKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch821", title: "Dispatch · M-04 Pickup Kanban",  role: .dispatch) { p in AnyView(DispatcherM04PickupKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch822", title: "Dispatch · M-04 Transit Kanban", role: .dispatch) { p in AnyView(DispatcherM04InTransitKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch823", title: "Dispatch · M-04 Delivery Kanban",role: .dispatch) { p in AnyView(DispatcherM04AtDeliveryKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "Dpch824", title: "Dispatch · M-04 Paper Kanban",   role: .dispatch) { p in AnyView(DispatcherM04PaperworkKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "531",     title: "Dispatch · M-04 Closed Kanban",  role: .dispatch) { p in AnyView(DispatcherM04ClosedKanbanScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            .init(id: "532",     title: "Dispatch · M-05 Assign Driver",  role: .dispatch) { p in AnyView(DispatcherM05AssignDriverScreen(theme: p, loadId: BrokerNavContext.latestLoadId)) },
            // 2026-05-30 — the-oath §44/§50 dispatcher ports.
            .init(id: "533",     title: "Dispatch · AI Dispatch Assist",   role: .dispatch) { p in AnyView(DispatcherAIDispatchAssistScreen(theme: p)) },
            .init(id: "539",     title: "Dispatch · Carrier Scorecard",     role: .dispatch) { p in AnyView(DispatcherCarrierScorecardScreen(theme: p)) },
            // 2026-07-10 — Dispatcher wireframe ports 410/534/535/537 (native, honest-wired).
            .init(id: "410",     title: "Dispatch · Exception Triage",      role: .dispatch) { p in AnyView(DispatcherExceptionTriageScreen(theme: p)) },
            .init(id: "534",     title: "Dispatch · Dock Coordination",     role: .dispatch) { p in AnyView(DispatcherDockCoordinationScreen(theme: p)) },
            .init(id: "535",     title: "Dispatch · Driver Availability",   role: .dispatch) { p in AnyView(DispatcherDriverAvailabilityScreen(theme: p)) },
            .init(id: "537",     title: "Dispatch · Opportunities Board",   role: .dispatch) { p in AnyView(DispatcherOpportunitiesBoardScreen(theme: p)) },
            // 2026-07-11 — Dispatcher revenue-assurance band ports 538/540-545 (native, honest-wired · completes the role).
            .init(id: "538",     title: "Dispatch · Cash & Factoring",       role: .dispatch) { p in AnyView(DispatcherCashAndFactoringScreen(theme: p)) },
            .init(id: "540",     title: "Dispatch · Accessorial Recovery",   role: .dispatch) { p in AnyView(DispatcherAccessorialRecoveryScreen(theme: p)) },
            .init(id: "541",     title: "Dispatch · Margin Bridge",          role: .dispatch) { p in AnyView(DispatcherMarginBridgeScreen(theme: p)) },
            .init(id: "542",     title: "Dispatch · Credentials Watchtower", role: .dispatch) { p in AnyView(DispatcherCredentialsWatchtowerScreen(theme: p)) },
            .init(id: "543",     title: "Dispatch · Rate Negotiation",       role: .dispatch) { p in AnyView(DispatcherRateNegotiationScreen(theme: p)) },
            .init(id: "544",     title: "Dispatch · Demand Map",             role: .dispatch) { p in AnyView(DispatcherDemandMapScreen(theme: p)) },
            .init(id: "545",     title: "Dispatch · Maintenance Due",        role: .dispatch) { p in AnyView(DispatcherMaintenanceDueScreen(theme: p)) },
            // 2026-05-21 — Catalyst Vehicle B-variant deep-drill octet (SVG 330B-337B).
            .init(id: "CV330B", title: "Catalyst · Vehicle Score Axis",   role: .catalyst) { p in AnyView(CatalystVehicleScoreAxisScreen(theme: p)) },
            // 2026-05-31 — Rescue land: bespoke pixel-faithful 330B scorecard axis detail (full port).
            .init(id: "330B", title: "Catalyst · Vehicle Scorecard Axis (Bespoke)", role: .catalyst) { p in AnyView(CatalystVehicleScorecardAxisDetailScreen(theme: p)) },
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
            // 2026-05-31 — Rescue land: bespoke pixel-faithful 327B driver quarter detail (full port).
            .init(id: "327B", title: "Catalyst · Driver Quarter Detail (Bespoke)", role: .catalyst) { p in AnyView(CatalystDriverQuarterDetailBespokeScreen(theme: p)) },
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
            // 2026-05-31 — Rescue land: bespoke Rail shipper greenfield home + shipment detail + demurrage dispute (full ports).
            .init(id: "Rail001", title: "Rail Shipper · Home",            role: .shipper) { p in AnyView(RailShipperHomeScreen(theme: p)) },
            .init(id: "Rail002", title: "Rail Shipper · Shipment Detail",  role: .shipper) { p in AnyView(RailShipmentDetailScreen(theme: p, shipmentId: 48217)) },
            .init(id: "Rail570", title: "Rail Engineer · Demurrage Dispute", role: .railEngineer) { p in AnyView(RailDemurrageDisputeScreen(theme: p, railId: "RAIL-260523-7C3A0B12D4")) },
            .init(id: "Rail551", title: "Rail Engineer · Shipments",  role: .railEngineer) { p in AnyView(RailShipmentsScreen(theme: p)) },
            .init(id: "Rail552", title: "Rail Engineer · Compliance", role: .railEngineer) { p in AnyView(RailComplianceScreen(theme: p)) },
            // 2026-05-30 — Rail Engineer deep surface (Rail553–590): 36 orphaned screens
            // registered into the build target + ScreenRegistry. Args default to neutral
            // placeholders (ids "0", status "IN_TRANSIT") matching 551/552 convention.
            .init(id: "Rail553", title: "Rail Engineer · Shipment Detail (Carrier)", role: .railEngineer) { p in AnyView(RailShipmentDetailCarrierScreen(theme: p, shipmentId: 0)) },
            .init(id: "Rail554", title: "Rail Engineer · Crew HOS Roster", role: .railEngineer) { p in AnyView(RailCrewHOSRosterScreen(theme: p)) },
            .init(id: "Rail555", title: "Rail Engineer · Consist Board", role: .railEngineer) { p in AnyView(RailConsistBoardScreen(theme: p)) },
            .init(id: "Rail556", title: "Rail Engineer · Engineer Account", role: .railEngineer) { p in AnyView(RailEngineerAccountScreen(theme: p)) },
            .init(id: "Rail557", title: "Rail Engineer · Status Update", role: .railEngineer) { p in AnyView(RailStatusUpdateScreen(theme: p, shipmentId: 0, currentStatus: "IN_TRANSIT")) },
            .init(id: "Rail558", title: "Rail Engineer · Demurrage Watch", role: .railEngineer) { p in AnyView(RailDemurrageWatchScreen(theme: p)) },
            .init(id: "Rail560", title: "Rail Engineer · Live Tracking", role: .railEngineer) { p in AnyView(RailLiveTrackingScreen(theme: p, shipmentId: 0)) },
            .init(id: "Rail561", title: "Rail Engineer · Facility Status", role: .railEngineer) { p in AnyView(RailFacilityStatusScreen(theme: p, yardId: 0, railroad: "", facilityCode: "")) },
            .init(id: "Rail562", title: "Rail Engineer · Gate Appointment", role: .railEngineer) { p in AnyView(RailGateAppointmentScreen(theme: p, facilityId: "0", shipmentId: "0")) },
            .init(id: "Rail563", title: "Rail Engineer · Exceptions & Holds", role: .railEngineer) { p in AnyView(RailExceptionsHoldsScreen(theme: p)) },
            .init(id: "Rail564", title: "Rail Engineer · Border Clearance", role: .railEngineer) { p in AnyView(RailBorderClearanceScreen(theme: p, shipmentId: 0, interchangePointId: "0")) },
            .init(id: "Rail565", title: "Rail Engineer · Container Timeline", role: .railEngineer) { p in AnyView(RailContainerTimelineScreen(theme: p, containerNumber: "", shipmentId: 0)) },
            .init(id: "Rail566", title: "Rail Engineer · Intermodal Transfer", role: .railEngineer) { p in AnyView(RailIntermodalTransferScreen(theme: p, shipmentId: 0)) },
            .init(id: "Rail567", title: "Rail Engineer · Chain of Custody", role: .railEngineer) { p in AnyView(RailChainOfCustodyScreen(theme: p, loadId: "0")) },
            .init(id: "Rail606", title: "Rail Engineer · Cargo Insurance", role: .railEngineer) { p in AnyView(RailCargoInsuranceScreen(theme: p)) },
            .init(id: "Rail608", title: "Rail Engineer · Demurrage Alerts", role: .railEngineer) { p in AnyView(RailDemurrageAlertsScreen(theme: p)) },
            .init(id: "Rail613", title: "Rail Engineer · Gate Activity Log", role: .railEngineer) { p in AnyView(RailGateActivityLogScreen(theme: p)) },
            .init(id: "Rail612", title: "Rail Engineer · Transload Inventory", role: .railEngineer) { p in AnyView(RailTransloadInventoryScreen(theme: p)) },
            .init(id: "Rail699", title: "Rail Engineer · Bad-Order Handoff", role: .railEngineer) { p in AnyView(RailBadOrderMonitorScreen(theme: p)) },
            .init(id: "Rail609", title: "Rail Engineer · Reefer Cold-Chain", role: .railEngineer) { p in AnyView(RailReeferMonitorScreen(theme: p)) },
            .init(id: "Rail610", title: "Rail Engineer · Tank Car Monitor", role: .railEngineer) { p in AnyView(RailTankCarMonitorScreen(theme: p)) },
            .init(id: "Rail611", title: "Rail Engineer · FSMA Compliance", role: .railEngineer) { p in AnyView(RailFSMAComplianceScreen(theme: p)) },
            .init(id: "Rail694", title: "Rail Engineer · Interchange Handoff", role: .railEngineer) { p in AnyView(RailInterchangeHandoffScreen(theme: p)) },
            .init(id: "Rail697", title: "Rail Engineer · Interline Route Plan", role: .railEngineer) { p in AnyView(RailInterlineRoutePlanScreen(theme: p)) },
            .init(id: "Rail656", title: "Rail Engineer · Claim Payments", role: .railEngineer) { p in AnyView(RailClaimPaymentsScreen(theme: p)) },
            .init(id: "Rail669", title: "Rail Engineer · Overcharge Recovery", role: .railEngineer) { p in AnyView(RailOverchargeRecoveryScreen(theme: p)) },
            .init(id: "Rail670", title: "Rail Engineer · Shortage Claims", role: .railEngineer) { p in AnyView(RailShortageClaimsScreen(theme: p)) },
            .init(id: "Rail671", title: "Rail Engineer · Claim Templates", role: .railEngineer) { p in AnyView(RailClaimTemplatesScreen(theme: p)) },
            .init(id: "Rail673", title: "Rail Engineer · Intermodal Dashboard", role: .railEngineer) { p in AnyView(RailIntermodalDashboardScreen(theme: p)) },
            // 2026-07-03 — Rail 700-706 (mechanical/safety + fraud/trust).
            // Id "Rail700" is collision-free: Terminal uses bare "700",
            // Vessel uses "Vesl700".
            .init(id: "Rail700", title: "Rail Engineer · Carman Cert Registry", role: .railEngineer) { p in AnyView(RailCarmanCertRegistryScreen(theme: p)) },
            .init(id: "Rail701", title: "Rail Engineer · Repair Work Order", role: .railEngineer) { p in AnyView(RailRepairWorkOrderScreen(theme: p)) },
            .init(id: "Rail702", title: "Rail Engineer · Wayside Detectors", role: .railEngineer) { p in AnyView(RailWaysideDetectorsScreen(theme: p)) },
            .init(id: "Rail703", title: "Rail Engineer · Hazmat Incident E-Report", role: .railEngineer) { p in AnyView(RailHazmatIncidentReportScreen(theme: p)) },
            .init(id: "Rail704", title: "Rail Engineer · Trust Verdict", role: .railEngineer) { p in AnyView(RailTrustVerdictScreen(theme: p, loadId: "0")) },  // loadId accepts "1077" or "load_1077"; pass the real tender id when opened from a shipment context
            .init(id: "Rail705", title: "Rail Engineer · SCAC Mark Check", role: .railEngineer) { p in AnyView(RailScacMarkCheckScreen(theme: p)) },  // optional enteredMark: pre-fills the mark when opened from a tender
            .init(id: "Rail706", title: "Rail Engineer · Tag-Swap Scan", role: .railEngineer) { p in AnyView(RailTagSwapScanScreen(theme: p)) },
            // 2026-07-11 — 05 Rail port-batch (ios/port-rail-3): 674-681, the
            // carrier-side departure-readiness + movement-planning band
            // (consist mass · air-brake · PTC · bad-order · deadhead · Part 228
            // HOS · hp/ton · interchange dwell). Ids "Rail674"…"Rail681" are
            // collision-free; the Vessel 679 uses "Vesl679" + a distinct type.
            .init(id: "Rail674", title: "Rail Engineer · Consist Mass & Dynamic-Brake", role: .railEngineer) { p in AnyView(RailConsistMassDynamicBrakeScreen(theme: p)) },
            .init(id: "Rail675", title: "Rail Engineer · Air-Brake Test Log", role: .railEngineer) { p in AnyView(RailAirBrakeTestLogScreen(theme: p)) },
            .init(id: "Rail676", title: "Rail Engineer · PTC Route Qualification", role: .railEngineer) { p in AnyView(RailPTCRouteQualificationScreen(theme: p)) },
            .init(id: "Rail677", title: "Rail Engineer · Bad-Order Tagging", role: .railEngineer) { p in AnyView(RailBadOrderTaggingScreen(theme: p)) },
            .init(id: "Rail678", title: "Rail Engineer · Deadhead Positioning", role: .railEngineer) { p in AnyView(RailDeadheadPositioningScreen(theme: p)) },
            .init(id: "Rail679", title: "Rail Engineer · FRA Part 228 HOS Audit", role: .railEngineer) { p in AnyView(RailFRAPart228HOSAuditScreen(theme: p)) },
            .init(id: "Rail680", title: "Rail Engineer · Locomotive HP-per-Ton", role: .railEngineer) { p in AnyView(RailLocomotiveHPPerTonScreen(theme: p)) },
            .init(id: "Rail681", title: "Rail Engineer · Interchange Dwell-SLA", role: .railEngineer) { p in AnyView(RailInterchangeDwellSLAScreen(theme: p)) },
            .init(id: "Rail639", title: "Rail Engineer · Yard Directory", role: .railEngineer) { p in AnyView(RailYardDirectoryScreen(theme: p)) },
            .init(id: "Rail672", title: "Rail Engineer · Layover Tracking", role: .railEngineer) { p in AnyView(RailLayoverTrackingScreen(theme: p)) },
            .init(id: "Rail568", title: "Rail Engineer · Equipment Lease", role: .railEngineer) { p in AnyView(RailEquipmentLeaseScreen(theme: p)) },
            .init(id: "Rail569", title: "Rail Engineer · Tender Workflow", role: .railEngineer) { p in AnyView(RailTenderWorkflowScreen(theme: p)) },
            .init(id: "Rail571", title: "Rail Engineer · IMDG Hazmat Manifest", role: .railEngineer) { p in AnyView(RailIMDGHazmatManifestScreen(theme: p, containerNumber: "", railId: "0")) },
            .init(id: "Rail572", title: "Rail Engineer · Emissions", role: .railEngineer) { p in AnyView(RailEmissionsScreen(theme: p, railId: "0", shipmentId: 0)) },
            .init(id: "Rail573", title: "Rail Engineer · Accessorial Charges", role: .railEngineer) { p in AnyView(RailAccessorialChargesScreen(theme: p, railId: "0")) },
            .init(id: "Rail574", title: "Rail Engineer · Carrier Scorecard", role: .railEngineer) { p in AnyView(RailCarrierScorecardScreen(theme: p)) },
            .init(id: "Rail575", title: "Rail Engineer · Equipment Health", role: .railEngineer) { p in AnyView(RailEquipmentHealthScreen(theme: p)) },
            .init(id: "Rail576", title: "Rail Engineer · Shipment Amendment", role: .railEngineer) { p in AnyView(RailShipmentAmendmentScreen(theme: p, railId: "0")) },
            .init(id: "Rail577", title: "Rail Engineer · Fuel Surcharge", role: .railEngineer) { p in AnyView(RailFuelSurchargeScreen(theme: p)) },
            .init(id: "Rail578", title: "Rail Engineer · Route Weather", role: .railEngineer) { p in AnyView(RailRouteWeatherScreen(theme: p, railId: "0")) },
            .init(id: "Rail579", title: "Rail Engineer · Network Disruption", role: .railEngineer) { p in AnyView(RailNetworkDisruptionScreen(theme: p)) },
            .init(id: "Rail580", title: "Rail Engineer · Tariff Rate Lookup", role: .railEngineer) { p in AnyView(RailTariffRateLookupScreen(theme: p, railId: "0", shipmentId: 0)) },
            .init(id: "Rail581", title: "Rail Engineer · Settlement Summary", role: .railEngineer) { p in AnyView(RailSettlementSummaryScreen(theme: p)) },
            .init(id: "Rail582", title: "Rail Engineer · Ramp Schedule", role: .railEngineer) { p in AnyView(RailRampScheduleScreen(theme: p, locationId: "0")) },
            .init(id: "Rail583", title: "Rail Engineer · Cross-Border Interchange", role: .railEngineer) { p in AnyView(RailCrossBorderInterchangeScreen(theme: p, railId: "0")) },
            .init(id: "Rail584", title: "Rail Engineer · Crew Call Board", role: .railEngineer) { p in AnyView(RailCrewCallBoardScreen(theme: p, yardId: "0")) },
            .init(id: "Rail585", title: "Rail Engineer · Equipment Positions", role: .railEngineer) { p in AnyView(RailEquipmentPositionsScreen(theme: p, railId: "0")) },
            .init(id: "Rail586", title: "Rail Engineer · Service Lineup", role: .railEngineer) { p in AnyView(RailServiceLineupScreen(theme: p, railId: "0")) },
            .init(id: "Rail587", title: "Rail Engineer · FRA Safety", role: .railEngineer) { p in AnyView(RailFRASafetyScreen(theme: p, railId: "0")) },
            .init(id: "Rail588", title: "Rail Engineer · Fleet Health", role: .railEngineer) { p in AnyView(RailFleetHealthScreen(theme: p, railId: "0")) },
            .init(id: "Rail589", title: "Rail Engineer · Transload Connection", role: .railEngineer) { p in AnyView(RailTransloadConnectionScreen(theme: p, railId: "0")) },
            .init(id: "Rail590", title: "Rail Engineer · Document Ingest", role: .railEngineer) { p in AnyView(RailDocumentIngestScreen(theme: p, documentId: "0")) },
            // 2026-05-30 — the-oath §41/§47/§53 rail ports.
            .init(id: "Rail005", title: "Rail · Waybill",                 role: .railEngineer) { p in AnyView(RailWaybillScreen(theme: p)) },
            .init(id: "Rail006", title: "Rail · Cross-Border Customs",    role: .railEngineer) { p in AnyView(RailCrossBorderCustoms_006(loadId: 0).environment(\.palette, p)) },
            .init(id: "Rail007", title: "Rail · New Shipment",            role: .railEngineer) { p in AnyView(RailNewShipment_007().environment(\.palette, p)) },
            // Phase B wave 5 — Rail engineer NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail559", title: "Rail Engineer · Yard Operations",       role: .railEngineer) { p in AnyView(RailYardOperationsScreen(theme: p)) },
            .init(id: "Rail591", title: "Rail Engineer · Consignee Tracking",    role: .railEngineer) { p in AnyView(RailConsigneeTrackingLinkScreen(theme: p)) },
            .init(id: "Rail592", title: "Rail Engineer · Forwarder Portal",      role: .railEngineer) { p in AnyView(RailForwarderPortalScreen(theme: p)) },
            .init(id: "Rail593", title: "Rail Engineer · Settlement Batch",      role: .railEngineer) { p in AnyView(RailSettlementBatchScreen(theme: p)) },
            .init(id: "Rail594", title: "Rail Engineer · Cost Breakdown",        role: .railEngineer) { p in AnyView(RailCostBreakdownScreen(theme: p)) },
            .init(id: "Rail595", title: "Rail Engineer · Crew Certifications",   role: .railEngineer) { p in AnyView(RailCrewCertificationsScreen(theme: p)) },
            .init(id: "Rail596", title: "Rail Engineer · Duty HTS Estimate",     role: .railEngineer) { p in AnyView(RailDutyHTSEstimateScreen(theme: p)) },
            .init(id: "Rail597", title: "Rail Engineer · Hazmat DG Rules",       role: .railEngineer) { p in AnyView(RailHazmatDGRulesScreen(theme: p)) },
            // Phase B wave 7 — Rail NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail607", title: "Rail Engineer · EDI Messages",        role: .railEngineer) { p in AnyView(RailEDIMessagesScreen(theme: p)) },
            .init(id: "Rail616", title: "Rail Engineer · Free Time",           role: .railEngineer) { p in AnyView(RailFreeTimeScreen(theme: p)) },
            .init(id: "Rail617", title: "Rail Engineer · Drayage Orders",      role: .railEngineer) { p in AnyView(RailDrayageOrdersScreen(theme: p)) },
            .init(id: "Rail618", title: "Rail Engineer · Mode Optimization",   role: .railEngineer) { p in AnyView(RailModeOptimizationScreen(theme: p)) },
            .init(id: "Rail619", title: "Rail Engineer · Per Diem Tracking",   role: .railEngineer) { p in AnyView(RailPerDiemTrackingScreen(theme: p)) },
            .init(id: "Rail620", title: "Rail Engineer · Release Order",       role: .railEngineer) { p in AnyView(RailReleaseOrderScreen(theme: p)) },
            .init(id: "Rail621", title: "Rail Engineer · Yard Move Queue",     role: .railEngineer) { p in AnyView(RailYardMoveQueueScreen(theme: p)) },
            .init(id: "Rail622", title: "Rail Engineer · Move Scheduler",      role: .railEngineer) { p in AnyView(RailMoveSchedulerScreen(theme: p)) },
            // Phase B wave 9 — Rail NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail631", title: "Rail Engineer · FRA Accident Reports",  role: .railEngineer) { p in AnyView(RailFRAAccidentReportsScreen(theme: p)) },
            .init(id: "Rail632", title: "Rail Engineer · Crew Availability",      role: .railEngineer) { p in AnyView(RailCrewAvailabilityScreen(theme: p)) },
            .init(id: "Rail633", title: "Rail Engineer · Border Crossing ETA",    role: .railEngineer) { p in AnyView(RailBorderCrossingETAScreen(theme: p)) },
            .init(id: "Rail634", title: "Rail Engineer · Railcar Inventory",      role: .railEngineer) { p in AnyView(RailRailcarInventoryScreen(theme: p)) },
            .init(id: "Rail635", title: "Rail Engineer · Financial Summary",      role: .railEngineer) { p in AnyView(RailFinancialSummaryScreen(theme: p)) },
            .init(id: "Rail636", title: "Rail Engineer · X-Border Crew Certs",    role: .railEngineer) { p in AnyView(RailCrossBorderCrewCertsScreen(theme: p)) },
            .init(id: "Rail637", title: "Rail Engineer · X-Border DG Regs",       role: .railEngineer) { p in AnyView(RailCrossBorderDGRegsScreen(theme: p)) },
            .init(id: "Rail638", title: "Rail Engineer · X-Border Compliance",    role: .railEngineer) { p in AnyView(RailCrossBorderComplianceCheckScreen(theme: p)) },
            // Phase B wave 10 — Rail analytics NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail640", title: "Rail Engineer · Diesel Fuel Index",     role: .railEngineer) { p in AnyView(RailDieselFuelIndexScreen(theme: p)) },
            .init(id: "Rail641", title: "Rail Engineer · Demurrage Analytics",   role: .railEngineer) { p in AnyView(RailDemurrageAnalyticsScreen(theme: p)) },
            .init(id: "Rail642", title: "Rail Engineer · Accessorial Analytics", role: .railEngineer) { p in AnyView(RailAccessorialAnalyticsScreen(theme: p)) },
            .init(id: "Rail643", title: "Rail Engineer · ETA Prediction",        role: .railEngineer) { p in AnyView(RailETAPredictionScreen(theme: p)) },
            .init(id: "Rail644", title: "Rail Engineer · Transit Comparison",    role: .railEngineer) { p in AnyView(RailTransitComparisonScreen(theme: p)) },
            .init(id: "Rail645", title: "Rail Engineer · Detention Dashboard",   role: .railEngineer) { p in AnyView(RailDetentionDashboardScreen(theme: p)) },
            .init(id: "Rail646", title: "Rail Engineer · Rebooking Options",     role: .railEngineer) { p in AnyView(RailRebookingOptionsScreen(theme: p)) },
            .init(id: "Rail647", title: "Rail Engineer · Multimodal Analytics",  role: .railEngineer) { p in AnyView(RailMultimodalAnalyticsScreen(theme: p)) },
            // Phase B wave 11 — Rail detention/claims NEW screens (theme-only inits).
            .init(id: "Rail648", title: "Rail Engineer · Demurrage Calculator", role: .railEngineer) { p in AnyView(RailDemurrageCalculatorScreen(theme: p)) },
            .init(id: "Rail649", title: "Rail Engineer · Detention by Customer", role: .railEngineer) { p in AnyView(RailDetentionByCustomerScreen(theme: p)) },
            .init(id: "Rail650", title: "Rail Engineer · Detention History", role: .railEngineer) { p in AnyView(RailDetentionHistoryScreen(theme: p)) },
            .init(id: "Rail651", title: "Rail Engineer · Auto-Detention Rules", role: .railEngineer) { p in AnyView(RailAutoDetentionRulesScreen(theme: p)) },
            .init(id: "Rail652", title: "Rail Engineer · Claims Dashboard", role: .railEngineer) { p in AnyView(RailClaimsDashboardScreen(theme: p)) },
            .init(id: "Rail653", title: "Rail Engineer · Claims List", role: .railEngineer) { p in AnyView(RailClaimsListScreen(theme: p)) },
            .init(id: "Rail654", title: "Rail Engineer · Claim Workflow", role: .railEngineer) { p in AnyView(RailClaimWorkflowScreen(theme: p)) },
            .init(id: "Rail655", title: "Rail Engineer · Loss Prevention", role: .railEngineer) { p in AnyView(RailLossPreventionScreen(theme: p)) },
            // Phase B wave 6 — Rail engineer + ramp-ops NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail598", title: "Rail Engineer · Equipment Specs",      role: .railEngineer) { p in AnyView(RailEquipmentSpecsScreen(theme: p)) },
            .init(id: "Rail599", title: "Rail Engineer · Freight Bill Audit",   role: .railEngineer) { p in AnyView(RailFreightBillAuditScreen(theme: p)) },
            // 2026-07-10 — Rail wireframe ports 003/004/009/010 (shipper) + 614/615/657/658 (rail engineer).
            .init(id: "Rail003", title: "Rail Shipper · Live Tracking",       role: .shipper)      { p in AnyView(RailLiveTrackingShipperScreen(theme: p, shipmentId: 48217)) },
            .init(id: "Rail004", title: "Rail Shipper · Demurrage Detail",    role: .shipper)      { p in AnyView(RailDemurrageDetailScreen(theme: p, shipmentId: 39044)) },
            .init(id: "Rail009", title: "Rail Shipper · Intermodal Journey",  role: .shipper)      { p in AnyView(RailIntermodalJourneyScreen(theme: p, shipmentId: 50418)) },
            .init(id: "Rail010", title: "Rail Shipper · Freight Bill Audit",  role: .shipper)      { p in AnyView(RailFreightBillAuditShipperScreen(theme: p)) },
            .init(id: "Rail614", title: "Rail Engineer · Intermodal Segment Board", role: .railEngineer) { p in AnyView(RailIntermodalSegmentBoardScreen(theme: p, shipmentId: 50418)) },
            .init(id: "Rail615", title: "Rail Engineer · Cross-Dock Plan",    role: .railEngineer) { p in AnyView(RailCrossDockPlanScreen(theme: p)) },
            .init(id: "Rail657", title: "Rail Engineer · Dispute Resolution", role: .railEngineer) { p in AnyView(RailDisputeResolutionScreen(theme: p)) },
            .init(id: "Rail658", title: "Rail Engineer · Dispute Mediation",  role: .railEngineer) { p in AnyView(RailDisputeMediationScreen(theme: p)) },
            .init(id: "Rail600", title: "Rail Engineer · Ramp Ops Console",     role: .railEngineer) { p in AnyView(RailRampOperationsConsoleScreen(theme: p)) },
            .init(id: "Rail601", title: "Rail Engineer · Chassis Pool",         role: .railEngineer) { p in AnyView(RailChassisPoolScreen(theme: p)) },
            .init(id: "Rail602", title: "Rail Engineer · Detention Tracking",   role: .railEngineer) { p in AnyView(RailDetentionTrackingScreen(theme: p)) },
            .init(id: "Rail603", title: "Rail Engineer · Dock Schedule",        role: .railEngineer) { p in AnyView(RailDockScheduleScreen(theme: p)) },
            .init(id: "Rail604", title: "Rail Engineer · Yard Analytics",       role: .railEngineer) { p in AnyView(RailYardAnalyticsScreen(theme: p)) },
            .init(id: "Rail605", title: "Rail Engineer · Cargo Claim",          role: .railEngineer) { p in AnyView(RailCargoClaimScreen(theme: p)) },
            // Phase B wave 8 — Rail NEW screens (verbatim ports, theme-only inits).
            .init(id: "Rail623", title: "Rail Engineer · Drop Yard Ops",        role: .railEngineer) { p in AnyView(RailDropYardOperationsScreen(theme: p)) },
            .init(id: "Rail624", title: "Rail Engineer · Dwell Reason Analysis",role: .railEngineer) { p in AnyView(RailDwellReasonAnalysisScreen(theme: p)) },
            .init(id: "Rail625", title: "Rail Engineer · Appointment Compliance",role: .railEngineer) { p in AnyView(RailAppointmentComplianceScreen(theme: p)) },
            .init(id: "Rail626", title: "Rail Engineer · Warehouse Receipt",    role: .railEngineer) { p in AnyView(RailWarehouseReceiptScreen(theme: p)) },
            .init(id: "Rail627", title: "Rail Engineer · Bid Board",            role: .railEngineer) { p in AnyView(RailBidBoardScreen(theme: p)) },
            .init(id: "Rail628", title: "Rail Engineer · Yard Map",             role: .railEngineer) { p in AnyView(RailYardMapScreen(theme: p)) },
            .init(id: "Rail629", title: "Rail Engineer · Trailer Pool Detail",  role: .railEngineer) { p in AnyView(RailTrailerPoolDetailScreen(theme: p)) },
            .init(id: "Rail630", title: "Rail Engineer · Cross-Dock Ops",       role: .railEngineer) { p in AnyView(RailCrossDockOperationsScreen(theme: p)) },
            // Phase — Rail claims-analytics / demurrage-charge / gate / equipment / yard / intermodal ports (659–666).
            .init(id: "Rail659", title: "Rail Engineer · Claims Analytics",        role: .railEngineer) { p in AnyView(RailClaimsAnalyticsScreen(theme: p)) },
            .init(id: "Rail660", title: "Rail Engineer · Claim Report",            role: .railEngineer) { p in AnyView(RailClaimReportScreen(theme: p)) },
            .init(id: "Rail661", title: "Rail Engineer · Demurrage Charge Gen",    role: .railEngineer) { p in AnyView(RailDemurrageChargeGenerationScreen(theme: p)) },
            .init(id: "Rail662", title: "Rail Engineer · Demurrage Charge Approval",role: .railEngineer) { p in AnyView(RailDemurrageChargeApprovalScreen(theme: p)) },
            .init(id: "Rail663", title: "Rail Engineer · Gate Check-In",           role: .railEngineer) { p in AnyView(RailGateCheckInScreen(theme: p)) },
            .init(id: "Rail664", title: "Rail Engineer · Trailer Detail",          role: .railEngineer) { p in AnyView(RailTrailerDetailScreen(theme: p)) },
            .init(id: "Rail665", title: "Rail Engineer · Yard Slot Inventory",     role: .railEngineer) { p in AnyView(RailYardSlotInventoryScreen(theme: p)) },
            .init(id: "Rail666", title: "Rail Engineer · Intermodal Booking",      role: .railEngineer) { p in AnyView(RailIntermodalBookingScreen(theme: p)) },
        ])

        // Vessel Operator surface (Vesl650–652 tab roots; Vesl659 drill-in leaf).
        list.append(contentsOf: [
            .init(id: "Vesl650", title: "Vessel Operator · Home",       role: .vesselOperator) { p in AnyView(VesselOperatorHomeScreen(theme: p)) },
            // 2026-05-31 — Rescue land: bespoke Vessel shipper greenfield home + booking detail + live tracking (full ports).
            .init(id: "Vesl001", title: "Vessel Shipper · Home",          role: .shipper) { p in AnyView(VesselShipperHomeScreen(theme: p)) },
            .init(id: "Vesl002", title: "Vessel Shipper · Booking Detail", role: .shipper) { p in AnyView(VesselBookingDetailScreen(theme: p, shipmentId: 48217)) },
            .init(id: "Vesl003", title: "Vessel Shipper · Live Tracking",  role: .shipper) { p in AnyView(VesselLiveTrackingScreen(theme: p, bookingNumber: "VS-48217")) },
            .init(id: "Vesl651", title: "Vessel Operator · Shipments",  role: .vesselOperator) { p in AnyView(VesselShipmentsScreen(theme: p)) },
            .init(id: "Vesl652", title: "Vessel Operator · Compliance", role: .vesselOperator) { p in AnyView(VesselComplianceScreen(theme: p)) },
            .init(id: "Vesl757", title: "Vessel · Detention Letters", role: .vesselOperator) { p in AnyView(VesselDetentionLettersScreen(theme: p)) },
            .init(id: "Vesl815", title: "Vessel · Demurrage Charge Approval", role: .vesselOperator) { p in AnyView(VesselDemurrageChargeApprovalScreen(theme: p)) },
            .init(id: "Vesl669", title: "Vessel · Booking Amendment", role: .vesselOperator) { p in AnyView(VesselBookingAmendmentScreen(theme: p)) },
            .init(id: "Vesl706", title: "Vessel · Rebooking Suggestions", role: .vesselOperator) { p in AnyView(VesselRebookingSuggestionsScreen(theme: p)) },
            .init(id: "Vesl737", title: "Vessel · Drayage Orders", role: .vesselOperator) { p in AnyView(VesselDrayageOrdersScreen(theme: p)) },
            .init(id: "Vesl772", title: "Vessel · Demurrage Analytics", role: .vesselOperator) { p in AnyView(VesselDemurrageAnalyticsScreen(theme: p)) },
            .init(id: "Vesl792", title: "Vessel · Demurrage Calculator", role: .vesselOperator) { p in AnyView(VesselDemurrageCalculatorScreen(theme: p)) },
            .init(id: "Vesl709", title: "Vessel · Bid Board", role: .vesselOperator) { p in AnyView(VesselBidBoardScreen(theme: p)) },
            .init(id: "Vesl800", title: "Vessel · Claims Dashboard", role: .vesselOperator) { p in AnyView(VesselClaimsDashboardScreen(theme: p)) },
            .init(id: "Vesl801", title: "Vessel · Claims List", role: .vesselOperator) { p in AnyView(VesselClaimsListScreen(theme: p)) },
            .init(id: "Vesl808", title: "Vessel · Claim Workflow", role: .vesselOperator) { p in AnyView(VesselClaimWorkflowScreen(theme: p)) },
            .init(id: "Vesl732", title: "Vessel · Cargo Claim", role: .vesselOperator) { p in AnyView(VesselCargoClaimScreen(theme: p)) },
            .init(id: "Vesl006", title: "Vessel Shipper · Customs ISF", role: .shipper) { p in AnyView(VesselCustomsISFScreen(theme: p)) },
            .init(id: "Vesl814", title: "Vessel · Customs Entry Filing", role: .vesselOperator) { p in AnyView(VesselCustomsEntryFilingScreen(theme: p)) },
            .init(id: "Vesl789", title: "Vessel · Customs Status Update", role: .vesselOperator) { p in AnyView(VesselCustomsStatusUpdateScreen(theme: p)) },
            .init(id: "Vesl770", title: "Vessel · ETA Prediction", role: .vesselOperator) { p in AnyView(VesselETAPredictionScreen(theme: p)) },
            .init(id: "Vesl782", title: "Vessel · Dwell Analysis", role: .vesselOperator) { p in AnyView(VesselDwellAnalysisScreen(theme: p)) },
            .init(id: "Vesl816", title: "Vessel · Top Shippers", role: .vesselOperator) { p in AnyView(VesselTopShippersScreen(theme: p)) },
            .init(id: "Vesl820", title: "Vessel · Reefer Pre-Cool", role: .vesselOperator) { p in AnyView(VesselReeferPreCoolScreen(theme: p)) },
            .init(id: "Vesl821", title: "Vessel · Reefer Alert Console", role: .vesselOperator) { p in AnyView(VesselReeferAlertConsoleScreen(theme: p)) },
            .init(id: "Vesl735", title: "Vessel · Demurrage Alerts", role: .vesselOperator) { p in AnyView(VesselDemurrageAlertsScreen(theme: p)) },
            .init(id: "Vesl689", title: "Vessel · Network Disruption", role: .vesselOperator) { p in AnyView(VesselNetworkDisruptionScreen(theme: p)) },
            .init(id: "Vesl802", title: "Vessel · Claim Payments", role: .vesselOperator) { p in AnyView(VesselClaimPaymentsScreen(theme: p)) },
            .init(id: "Vesl804", title: "Vessel · Overcharge Recovery", role: .vesselOperator) { p in AnyView(VesselOverchargeRecoveryScreen(theme: p)) },
            .init(id: "Vesl805", title: "Vessel · Loss Prevention", role: .vesselOperator) { p in AnyView(VesselLossPreventionScreen(theme: p)) },
            .init(id: "Vesl809", title: "Vessel · Dispute Resolution", role: .vesselOperator) { p in AnyView(VesselDisputeResolutionScreen(theme: p)) },
            .init(id: "Vesl660", title: "Vessel · Live Position", role: .vesselOperator) { p in AnyView(VesselLivePositionScreen(theme: p)) },
            .init(id: "Vesl661", title: "Vessel · Port Calls", role: .vesselOperator) { p in AnyView(VesselPortCallsScreen(theme: p)) },
            .init(id: "Vesl674", title: "Vessel · Cost Breakdown", role: .vesselOperator) { p in AnyView(VesselCostBreakdownScreen(theme: p)) },
            .init(id: "Vesl696", title: "Vessel · Settlement Batch", role: .vesselOperator) { p in AnyView(VesselSettlementBatchScreen(theme: p)) },
            .init(id: "Vesl784", title: "Vessel · Detention Tracking", role: .vesselOperator) { p in AnyView(VesselDetentionTrackingScreen(theme: p)) },
            .init(id: "Vesl810", title: "Vessel · Dispute Mediation", role: .vesselOperator) { p in AnyView(VesselDisputeMediationScreen(theme: p)) },
            .init(id: "Vesl811", title: "Vessel · Claims Analytics", role: .vesselOperator) { p in AnyView(VesselClaimsAnalyticsScreen(theme: p)) },
            .init(id: "Vesl812", title: "Vessel · Claim Templates", role: .vesselOperator) { p in AnyView(VesselClaimTemplatesScreen(theme: p)) },
            .init(id: "Vesl670", title: "Vessel · Bunker Prices", role: .vesselOperator) { p in AnyView(VesselBunkerPricesScreen(theme: p)) },
            .init(id: "Vesl708", title: "Vessel · Shipment CO2", role: .vesselOperator) { p in AnyView(VesselShipmentCO2Screen(theme: p)) },
            // 2026-06-10 — PR #50 salvage: the 4 port-wave-1 screens that never
            // landed on main (661/670/735/784 + KeyboardDismissBridge were
            // superseded by newer work). De-fabricated to the live procs
            // before registration.
            .init(id: "Vesl697", title: "Vessel · Port Operations", role: .vesselOperator) { p in AnyView(VesselPortOperationsScreen(theme: p)) },
            .init(id: "Vesl730", title: "Vessel · Blank Sailing Watch", role: .vesselOperator) { p in AnyView(VesselBlankSailingWatchScreen(theme: p)) },
            .init(id: "Vesl731", title: "Vessel · Accessorial Charges", role: .vesselOperator) { p in AnyView(VesselAccessorialChargesScreen(theme: p)) },
            // Port wave 5 ( EI-prefix pbxproj) — Vessel Operator bespoke ports.
            .init(id: "Vesl734", title: "Vessel · EDI Messages", role: .vesselOperator) { p in AnyView(VesselEDIMessagesScreen(theme: p)) },
            .init(id: "Vesl736", title: "Vessel · Chassis Pool", role: .vesselOperator) { p in AnyView(VesselChassisPoolScreen(theme: p)) },
            .init(id: "Vesl739", title: "Vessel · Terminal Analytics", role: .vesselOperator) { p in AnyView(VesselTerminalAnalyticsScreen(theme: p)) },
            .init(id: "Vesl740", title: "Vessel · Free Time · LFD", role: .vesselOperator) { p in AnyView(VesselFreeTimeLFDScreen(theme: p)) },
            .init(id: "Vesl741", title: "Vessel · Per Diem", role: .vesselOperator) { p in AnyView(VesselPerDiemTrackingScreen(theme: p)) },
            .init(id: "Vesl742", title: "Vessel · Mode Optimization", role: .vesselOperator) { p in AnyView(VesselModeOptimizationScreen(theme: p)) },
            .init(id: "Vesl743", title: "Vessel · Cold-Chain FSMA Attestation", role: .vesselOperator) { p in AnyView(VesselColdChainFSMAScreen(theme: p)) },
            .init(id: "Vesl744", title: "Vessel · Terminal Gate Log", role: .vesselOperator) { p in AnyView(VesselTerminalGateLogScreen(theme: p)) },
            .init(id: "Vesl738", title: "Vessel · VGM Declaration", role: .vesselOperator) { p in AnyView(VesselVGMDeclarationScreen(theme: p)) },
            .init(id: "Vesl653", title: "Vessel Operator · Booking Detail",      role: .vesselOperator) { p in AnyView(VesselBookingDetailCarrierScreen(theme: p, shipmentId: 0)) },
            .init(id: "Vesl654", title: "Vessel Operator · Crew Certifications",  role: .vesselOperator) { p in AnyView(VesselCrewCertificationsScreen(theme: p)) },
            .init(id: "Vesl655", title: "Vessel Operator · Container Positions",  role: .vesselOperator) { p in AnyView(VesselContainerPositionsScreen(theme: p)) },
            .init(id: "Vesl656", title: "Vessel Operator · Account",             role: .vesselOperator) { p in AnyView(VesselOperatorAccountScreen(theme: p)) },
            .init(id: "Vesl657", title: "Vessel Operator · Status Update",        role: .vesselOperator) { p in AnyView(VesselStatusUpdateScreen(theme: p, bookingId: 0, currentStatus: "")) },
            .init(id: "Vesl658", title: "Vessel Operator · Demurrage & Detention", role: .vesselOperator) { p in AnyView(VesselDemurrageDetentionWatchScreen(theme: p)) },
            // 2026-05-30 — the-oath §43/§49 vessel ports.
            .init(id: "Vesl008", title: "Vessel · Intermodal Journey",    role: .vesselOperator) { p in AnyView(VesselIntermodalJourneyScreen(theme: p)) },
            .init(id: "Vesl009", title: "Vessel · Tender Workflow",        role: .vesselOperator) { p in AnyView(VesselTenderWorkflowScreen(theme: p)) },
            // Phase B wave 1 — Vessel operator NEW screens (verbatim ports of the canonical Dark-SVGs).
            // 2026-06-09 registry dedup: Port Directory was registered as
            // "Vesl659", colliding with (and shadowing) the Bunker FSC
            // screen that owns that id — the 656 Me-hub "Bunker FSC" row
            // opened the Port Directory instead. Re-id'd to the free slot
            // "Vesl686" (wave 3 skips 686); file renamed 659→686 on disk.
            // Do NOT merge with Vesl685 (Bunker FSC Schedule — different screen).
            .init(id: "Vesl686", title: "Vessel Operator · Port Directory",       role: .vesselOperator) { p in AnyView(VesselPortDirectoryScreen(theme: p)) },
            .init(id: "Vesl666", title: "Vessel Operator · Container Timeline",   role: .vesselOperator) { p in AnyView(VesselContainerTimelineScreen(theme: p)) },
            .init(id: "Vesl667", title: "Vessel Operator · Chain of Custody",      role: .vesselOperator) { p in AnyView(VesselChainOfCustodyScreen(theme: p)) },
            .init(id: "Vesl668", title: "Vessel Operator · IMDG Hazmat Manifest",  role: .vesselOperator) { p in AnyView(VesselIMDGHazmatManifestScreen(theme: p)) },
            .init(id: "Vesl676", title: "Vessel Operator · Equipment Health",      role: .vesselOperator) { p in AnyView(VesselEquipmentHealthScreen(theme: p)) },
            .init(id: "Vesl681", title: "Vessel Operator · Emissions CII",         role: .vesselOperator) { p in AnyView(VesselEmissionsCIIScreen(theme: p)) },
            .init(id: "Vesl682", title: "Vessel Operator · Carrier Scorecard",     role: .vesselOperator) { p in AnyView(VesselCarrierScorecardScreen(theme: p)) },
            // 2026-07-03 — 06 Vessel freshest trio: 675 Carrier Scorecard (LEAGUE/COMPARISON).
            .init(id: "Vesl675", title: "Vessel Operator · Carrier League",        role: .vesselOperator) { p in AnyView(VesselCarrierScorecard_675(theme: p)) },
            .init(id: "Vesl683", title: "Vessel Operator · Fleet Health",          role: .vesselOperator) { p in AnyView(VesselFleetHealthScreen(theme: p)) },
            // 2026-07-11 — 06 Vessel port-batch (ios/port-vessel-2): 692/693/694/695/699/703/704/707.
            // 692·693·699·707 are 1:1 ports of their Dark-SVGs; 694·695·703·704 are purpose-built to
            // the golden bar (their catalog SVGs ship empty) from the real router blueprints.
            .init(id: "Vesl692", title: "Vessel Operator · Transshipment Connection", role: .vesselOperator) { p in AnyView(VesselTransshipmentConnectionScreen(theme: p)) },
            .init(id: "Vesl693", title: "Vessel Operator · Document Ingest",          role: .vesselOperator) { p in AnyView(VesselDocumentIngestScreen(theme: p)) },
            .init(id: "Vesl694", title: "Vessel Operator · Consignee Tracking Link",  role: .vesselOperator) { p in AnyView(VesselConsigneeTrackingLinkScreen(theme: p)) },
            .init(id: "Vesl695", title: "Vessel Operator · Forwarder Portal",         role: .vesselOperator) { p in AnyView(VesselForwarderPortalScreen(theme: p)) },
            .init(id: "Vesl699", title: "Vessel Operator · Vessel Particulars",       role: .vesselOperator) { p in AnyView(VesselParticularsScreen(theme: p)) },
            .init(id: "Vesl703", title: "Vessel Operator · Port Lineup",              role: .vesselOperator) { p in AnyView(VesselPortLineupScreen(theme: p)) },
            .init(id: "Vesl704", title: "Vessel Operator · Bay Plan",                 role: .vesselOperator) { p in AnyView(VesselBayPlanScreen(theme: p)) },
            .init(id: "Vesl707", title: "Vessel Operator · Container Movement Log",   role: .vesselOperator) { p in AnyView(VesselContainerMovementLogScreen(theme: p)) },
            // Phase B wave 2 — Vessel operator NEW screens (verbatim ports). Required ids defaulted for registry construction.
            .init(id: "Vesl662", title: "Vessel Operator · Exceptions & Holds",     role: .vesselOperator) { p in AnyView(VesselExceptionsHoldsScreen(theme: p)) },
            .init(id: "Vesl663", title: "Vessel Operator · CBP Entry Detail",       role: .vesselOperator) { p in AnyView(VesselCBPEntryDetailScreen(theme: p, entryNumber: "", importerId: "")) },
            .init(id: "Vesl664", title: "Vessel Operator · Terminal Appointment",   role: .vesselOperator) { p in AnyView(VesselTerminalAppointmentScreen(theme: p)) },
            .init(id: "Vesl671", title: "Vessel Operator · Marine Weather Routing", role: .vesselOperator) { p in AnyView(VesselMarineWeatherRoutingScreen(theme: p)) },
            .init(id: "Vesl673", title: "Vessel Operator · Container Lease",        role: .vesselOperator) { p in AnyView(VesselContainerLeaseScreen(theme: p)) },
            .init(id: "Vesl677", title: "Vessel Operator · Carrier Tender Workflow",role: .vesselOperator) { p in AnyView(VesselCarrierTenderWorkflowScreen(theme: p, shipmentId: 0)) },
            .init(id: "Vesl678", title: "Vessel Operator · Port State Control",     role: .vesselOperator) { p in AnyView(VesselPortStateControlScreen(theme: p)) },
            .init(id: "Vesl680", title: "Vessel Operator · Intermodal Segment Board",role: .vesselOperator) { p in AnyView(VesselIntermodalSegmentBoardScreen(theme: p, shipmentId: 0)) },
            // Phase B wave 3 — Vessel operator NEW screens (verbatim ports, theme-only inits).
            .init(id: "Vesl684", title: "Vessel Operator · Settlement",          role: .vesselOperator) { p in AnyView(VesselSettlementScreen(theme: p)) },
            .init(id: "Vesl685", title: "Vessel Operator · Bunker FSC Schedule",  role: .vesselOperator) { p in AnyView(VesselBunkerFSCScheduleScreen(theme: p)) },
            .init(id: "Vesl687", title: "Vessel Operator · Ocean Rate Lookup",    role: .vesselOperator) { p in AnyView(VesselOceanRateLookupScreen(theme: p)) },
            .init(id: "Vesl688", title: "Vessel Operator · Sailing Schedule",     role: .vesselOperator) { p in AnyView(VesselSailingScheduleScreen(theme: p)) },
            .init(id: "Vesl698", title: "Vessel Operator · Berth Window",         role: .vesselOperator) { p in AnyView(VesselBerthWindowScreen(theme: p)) },
            .init(id: "Vesl700", title: "Vessel Operator · Freight Bill Audit",   role: .vesselOperator) { p in AnyView(VesselFreightBillAuditScreen(theme: p)) },
            .init(id: "Vesl701", title: "Vessel Operator · IMDG DG Rules",        role: .vesselOperator) { p in AnyView(VesselIMDGDGRulesScreen(theme: p)) },
            .init(id: "Vesl702", title: "Vessel Operator · Reefer Monitoring",    role: .vesselOperator) { p in AnyView(VesselReeferMonitoringScreen(theme: p)) },
            // Phase B wave 4 — last Vessel operator NEW screens (verbatim ports, theme-only inits).
            .init(id: "Vesl705", title: "Vessel Operator · CBP Alerts",       role: .vesselOperator) { p in AnyView(VesselCBPAlertsScreen(theme: p)) },
            .init(id: "Vesl710", title: "Vessel Operator · Marine Casualty",  role: .vesselOperator) { p in AnyView(VesselMarineCasualtyScreen(theme: p)) },
            .init(id: "Vesl711", title: "Vessel Operator · Crew Rest Hours",  role: .vesselOperator) { p in AnyView(VesselCrewRestHoursScreen(theme: p)) },
            .init(id: "Vesl712", title: "Vessel Operator · Financial Summary",role: .vesselOperator) { p in AnyView(VesselFinancialSummaryScreen(theme: p)) },
            .init(id: "Vesl659", title: "Vessel Operator · Bunker FSC", role: .vesselOperator) { p in AnyView(VesselBunkerFSCScreen(theme: p)) },
            // Vessel operator wave — booking/documentation + fraud/GA + release/eBL/PGA (verbatim ports 713–720).
            .init(id: "Vesl713", title: "Vessel Operator · Multi-Carrier RFQ",      role: .vesselOperator) { p in AnyView(VesselMultiCarrierRFQScreen(theme: p)) },
            .init(id: "Vesl714", title: "Vessel Operator · Shipping Instructions",  role: .vesselOperator) { p in AnyView(VesselShippingInstructionsScreen(theme: p)) },
            .init(id: "Vesl715", title: "Vessel Operator · B/L Draft Approval",     role: .vesselOperator) { p in AnyView(VesselBLDraftApprovalScreen(theme: p)) },
            .init(id: "Vesl716", title: "Vessel Operator · AIS Integrity",          role: .vesselOperator) { p in AnyView(VesselAisIntegrityScreen(theme: p)) },
            .init(id: "Vesl717", title: "Vessel Operator · General Average",        role: .vesselOperator) { p in AnyView(VesselGeneralAverageScreen(theme: p)) },
            .init(id: "Vesl718", title: "Vessel Operator · Cargo Release",          role: .vesselOperator) { p in AnyView(VesselCargoReleaseScreen(theme: p)) },
            .init(id: "Vesl719", title: "Vessel Operator · DCSA eBL",               role: .vesselOperator) { p in AnyView(VesselEBLScreen(theme: p)) },
            .init(id: "Vesl720", title: "Vessel Operator · PGA Holds",              role: .vesselOperator) { p in AnyView(VesselPGAHoldsScreen(theme: p)) },
            // Port wave — Vessel operator NEW screens 721/723/725/726/727/728/729/733 (native SwiftUI ports).
            .init(id: "Vesl721", title: "Vessel Operator · EU ETS & FuelEU",        role: .vesselOperator) { p in AnyView(VesselEUETSFuelEUScreen(theme: p)) },
            .init(id: "Vesl723", title: "Vessel Operator · Allocation & MQC",        role: .vesselOperator) { p in AnyView(VesselAllocationMQCScreen(theme: p)) },
            .init(id: "Vesl725", title: "Vessel Operator · Ocean Factoring",         role: .vesselOperator) { p in AnyView(VesselOceanFactoringScreen(theme: p)) },
            .init(id: "Vesl726", title: "Vessel Operator · DCSA Feed Health",        role: .vesselOperator) { p in AnyView(VesselFeedHealthScreen(theme: p)) },
            .init(id: "Vesl727", title: "Vessel Operator · MARPOL Record Book",      role: .vesselOperator) { p in AnyView(VesselMarpolRecordBookScreen(theme: p)) },
            .init(id: "Vesl728", title: "Vessel Operator · Three-Way Match",         role: .vesselOperator) { p in AnyView(VesselThreeWayMatchScreen(theme: p)) },
            .init(id: "Vesl729", title: "Vessel Operator · HS Dual-Use Screening",   role: .vesselOperator) { p in AnyView(VesselDualUseScreeningScreen(theme: p)) },
            .init(id: "Vesl733", title: "Vessel Operator · Cargo Insurance",         role: .vesselOperator) { p in AnyView(VesselCargoInsuranceScreen(theme: p)) },
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

    /// Driver-surface sheet→push detail layer (push-nav mandate,
    /// 2026-06-09 / audit M25). The non-driver roles each mount their own
    /// `RoleDetailLayer` inside `RoleSurfaceRouter`; the Driver surface is
    /// inline here, so it owns its own pushed-detail truth. Driver screens
    /// (010 Home, Eusoboards/Loads panes, 108 Eusoboards alias, 068 Me
    /// Earnings) call `\.rolePushDetail` to slide the canonical
    /// `LoadDetailSheet` in from the trailing edge instead of presenting
    /// a slide-up modal. Back posts the shared `.eusoRoleNavBack`.
    @State private var driverPushedDetail: RoleDetailPush? = nil

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
                        // Push-nav mandate (2026-06-09 / audit M25): the
                        // shared sheet→push detail layer, identical to
                        // every RoleSurfaceRouter surface. Injects
                        // `\.rolePushDetail` for all driver screens and
                        // renders the pushed detail above the surface
                        // (incl. BottomNav — same as the other roles).
                        .modifier(RoleDetailLayer(
                            pushedDetail: $driverPushedDetail,
                            palette: register.palette,
                            onBack: {
                                NotificationCenter.default.post(
                                    name: .eusoRoleNavBack, object: nil)
                            }
                        ))
                        // Detail-first back semantics: one back gesture
                        // clears the pushed layer. Only the driver branch
                        // is mounted when this fires (other surfaces own
                        // their own `.eusoRoleNavBack` receivers).
                        .onReceive(NotificationCenter.default.publisher(for: .eusoRoleNavBack)) { _ in
                            if driverPushedDetail != nil {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    driverPushedDetail = nil
                                }
                            }
                        }
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
                let key = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if driverPushedDetail != nil {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        driverPushedDetail = nil
                    }
                }
                nav.showeSang = false
                switch key {
                case "home", "home screen", "dashboard":
                    nav.currentTab = .home
                    trip.jump(to: .idle)
                case "trips", "haul", "eusoboards", "euso boards", "load board":
                    nav.currentTab = .trips
                case "my loads", "loads", "wallet":
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
        // Load detail "Message" CTA. The sheet resolves a persisted
        // load-scoped conversation first, then posts this app-level open
        // request. Root routing matters because Driver presents the native
        // message sheet while Shipper lands in the 311 thread screen.
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadConversationOpen)) { note in
            handleLoadConversationOpen(note)
        }
        // Universal hands-free autopilot — mounted ONCE at the root so the
        // orb press-and-hold activates continuous voice for WHATEVER role
        // is signed in (driver / ship captain / rail engineer / shipper /
        // dispatch / …), not just the driver/shipper chat sheets. The
        // engine drives the shared voice controller; Driver actions route
        // through `handleeSangAction`, every other role through
        // `eSangRoleDispatcher`. Floats above the current surface + the
        // BottomNav. See `EusoAutopilotMount` below this struct.
        .overlay(alignment: .top) {
            EusoAutopilotMount(
                role: session.user?.roleEnum ?? .driver,
                onDriverAction: { action in handleeSangAction(action) }
            )
            .environment(\.palette, register.palette)
        }
#if DEBUG
        .sheet(isPresented: $showChrome) {
            chromeSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
#endif
        // ESANG coach sheet — presented as a full-screen cover from the root
        // so tapping the orb from any Driver surface (lifecycle screen or any
        // of the three panes) slides it in over the current content.
        // ASC AOd5xzXVfU6CF6hyijTDwgk parity (build 712): the page-sheet peek
        // band let the presenting surface's labels collide with the status
        // bar; the coach sheet has its own close X, so nothing is lost.
        .fullScreenCover(isPresented: $nav.showeSang) {
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
            driverNavigate(to: route)
        case .navigatePath(let path):
            // The parser now emits the raw server SPA path for every
            // `navigate` verb so non-Driver roles can resolve it against
            // THEIR push-nav registry (E1/E2 fix). On the DRIVER surface
            // we keep the exact prior behavior: collapse the path onto a
            // Driver tab via `eSangAutopilot.route(for:)`. An unknown path
            // is a silent no-op (the reply text already rendered).
            if let route = eSangAutopilot.route(for: path) {
                driverNavigate(to: route)
            }
        case .openChat:
            nav.showeSang = true
        case .closeChat:
            nav.showeSang = false
        case .back:
            // Driver back: there's no push-nav stack on the Driver
            // surface (it's a 4-tab + lifecycle state machine), so a
            // spoken "go back" lands the driver on Home — the universal
            // safe return target — and dissolves the coach sheet.
            nav.showeSang = false
            nav.currentTab = .home
            trip.jump(to: .idle)
        case .execute(let key, _):
            // Broadcast the named action so any Driver surface owning a
            // matching CTA fires the same code path the button does
            // (e.g. "accept this load"). Also routes through the
            // existing Driver MeAction dispatcher for keys it knows.
            nav.showeSang = false
            NotificationCenter.default.post(
                name: .esangExecuteAction, object: key)
            handleDriverMeAction(key: key, userInfo: [:])
        case .autopilot:
            // Enter hands-free autopilot. The orb / surface state machine
            // owns continuous-listening; broadcast the enter signal.
            NotificationCenter.default.post(name: .esangEnterAutopilot, object: nil)
        case .undoAll:
            NotificationCenter.default.post(name: .esangUndoAll, object: nil)
        case .selectLoad:
            // The iOS shell doesn't yet expose a generic "open load by
            // id" pathway from the root (the per-surface sheet state is
            // local). Founder fix 2026-05-30: dissolve the coach sheet so
            // the driver lands ON the load surface, then surface the
            // current active-load detail by flipping to Home — ESANG's
            // reply text already tells them what they're looking at.
            nav.showeSang = false
            nav.currentTab = .home
            trip.jump(to: .idle)
        case .refresh:
            // Broadcast a lightweight refresh signal; any surface that
            // wants to listen can observe the notification and re-run
            // its loader.
            NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
        case .tapAt(let x, let y):
            // ESANG VISION GROUNDING (Driver path). Post the normalized
            // point; the key-window activator (mounted on the autopilot
            // overlay, see `EusoAutopilotMount`) hit-tests + activates the
            // control there, pulses, and gives honest feedback if nothing
            // activatable sits under the point.
            NotificationCenter.default.post(
                name: .esangTapAtPoint, object: nil,
                userInfo: ["x": x, "y": y]
            )
        }
    }

    /// Drive a typed Driver `eSangRoute` — extracted from
    /// `handleeSangAction` so both `.navigate` (legacy typed) and
    /// `.navigatePath` (raw server path, collapsed via `route(for:)`)
    /// share one path. Behavior is byte-for-byte the prior `.navigate`
    /// handler.
    private func driverNavigate(to route: eSangRoute) {
        // Founder fix 2026-05-30: ESANG-triggered navigation on the
        // Driver surface used to flip the BottomNav tab while the
        // ESANG coach sheet stayed up — so the driver "navigated"
        // but landed BEHIND the overlay and never saw the screen.
        // DISSOLVE the coach sheet first (the same `showeSang = false`
        // path the close button / tap-out uses), THEN drive the
        // EXISTING tab swap + Me deep-link so the user lands ON the
        // destination as the sheet slides away.
        nav.showeSang = false
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
            // `@State route` and open the sub-sheet. Defer the Me
            // sub-sheet until the coach sheet has finished dismissing
            // so the two presentations don't fight (a `.sheet` can
            // only present one item at a time per presenter).
            nav.currentTab = .me
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: raw
                )
            }
        }
    }

    /// Open a resolved, persisted load conversation in the native surface for
    /// the active role. Driver and the non-shipper operational roles use the
    /// canonical message sheet; Shipper uses the existing 311 push-nav thread
    /// because it owns a full role-specific chat screen.
    private func handleLoadConversationOpen(_ note: Notification) {
        let rawConversationId = note.userInfo?["conversationId"]
        let conversationId = (rawConversationId as? String)
            ?? (rawConversationId as? Int).map(String.init)
        guard let conversationId, !conversationId.isEmpty else { return }

        let loadNumber = (note.userInfo?["loadNumber"] as? String)
            ?? (note.userInfo?["loadId"] as? String)

        let role = session.user?.roleEnum ?? .driver
        if role == .shipper {
            LoadConversationContext.shared.pendingConversationId = conversationId
            LoadConversationContext.shared.pendingLoadNumber = loadNumber
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "311"]
            )
        } else {
            messagingSheetTarget = MessagingSheetTarget(threadId: conversationId)
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
        // Navigation: Eusoboards is the Driver Trips tab. Bid-detail and
        // earnings load-detail surfaces stay under Loads, because those
        // represent already-owned / already-bid work.
        //
        // `driver.load.detail` was previously routed here too, but
        // the founder bug 2026-05-07 surfaced that tapping a load
        // inside `108_MeLoadBoard` (Eusoboards) yanked the user to
        // My Loads — wrong destination. The fix lives at the source:
        // 108 is now only a compatibility alias; all public board entry
        // points route to the canonical Driver Trips surface.
        // Keeping `driver.load.detail` out of this tab-switch list
        // prevents the same regression from any future caller.
        case "driver.loadboard.open":
            nav.currentTab = .trips
        case "driver.bid.detail",
             "earnings.load.detail":
            nav.currentTab = .wallet
        case "driver.load.detail":
            // Intentionally NOT switching tabs. Source screens are
            // expected to handle the detail presentation locally
            // (sheet, push, in-place card). If a caller needs the
            // global public-board path, they should fire
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

// MARK: - Universal hands-free autopilot
//
// Founder direction (2026-06-02):
//   > autopilot has to especially work when user in service meaning
//   > drivers, ship captains, rail etc — every user role type,
//   > especially the ones who have to operate.
//
// ONE role-agnostic activation path, mounted once at the ContentView
// root, so every signed-in role gets identical press-and-hold autopilot.
// The orb long-press (DesignSystem.BottomNav) latches
// `eSangAutopilot.pendingAutopilotActivation` and posts
// `.esangEnterAutopilot`; `EusoAutopilotMount` (the overlay below)
// listens for both — the live notification AND the pending latch in its
// own `.onAppear` — and drives `EusoAutopilotEngine`.
//
// The engine runs a continuous voice loop on the SHARED
// `eSangVoiceInputController`: it listens, ships each final transcript to
// `esang.chat`, parses the reply for `<<<ACTION:…>>>` tokens, dispatches
// them to the CURRENT role (Driver via the injected `onDriverAction`
// closure; every other role via `eSangRoleDispatcher.dispatch`), then
// re-arms the mic for the next command — until the user taps the HUD's
// stop control or `.esangExitAutopilot` is posted.

/// Continuous hands-free voice loop shared by every role.
@MainActor
final class EusoAutopilotEngine: ObservableObject {

    /// `true` while autopilot is live (HUD visible, mic looping).
    @Published var isActive: Bool = false
    /// Last final transcript ESANG heard — surfaced in the HUD so the
    /// operator gets visible confirmation their command registered.
    @Published var lastHeard: String = ""
    /// Human status line for the HUD ("Listening…", "Thinking…", a denial
    /// reason, or an error).
    @Published var statusLine: String = "Listening…"

    /// Shared voice pipeline (Speech + AVAudioEngine). Same controller
    /// type the chat composers use, so the voice path terminates at the
    /// same `esang.chat` backend.
    let voice = eSangVoiceInputController()

    /// Role the loop dispatches against. Set on `activate`.
    private var role: EusoRole = .driver
    /// Driver dispatch is owned by ContentView (`nav`/`trip`); the engine
    /// calls back into it for the Driver role. Non-driver roles go through
    /// `eSangRoleDispatcher`.
    private var onDriverAction: ((eSangAction) -> Void)?
    /// `true` between shipping a transcript to ESANG and the dispatch
    /// settling — so the idle-watcher doesn't re-arm mid-request.
    private var awaitingReply: Bool = false
    /// Watches the voice controller returning to idle. The mic can finalize
    /// with an EMPTY transcript (the operator paused before speaking, or the
    /// utterance was unintelligible) — in that case `onFinalTranscript`
    /// never fires, so without this the hands-free loop would die after one
    /// silent cycle. We re-arm whenever the controller idles while autopilot
    /// is live and we're not mid-request.
    private var statusObserver: AnyCancellable?

    /// Begin the continuous loop for `role`. Idempotent — a second
    /// activation while already active is ignored.
    func activate(role: EusoRole, onDriverAction: @escaping (eSangAction) -> Void) {
        self.role = role
        self.onDriverAction = onDriverAction
        guard !isActive else { return }
        isActive = true
        lastHeard = ""
        statusLine = "Listening…"
        // Hands-free: auto-finalize a command after a short pause, since
        // there's no manual "stop" tap in autopilot. The chat composers
        // leave this nil and keep tap-to-stop.
        voice.silenceAutoStopInterval = 2.0   // 2026-06-03 — was 1.6, too eager (clipped commands)
        awaitingReply = false
        // Each final transcript → chat → parse → dispatch → re-listen.
        voice.onFinalTranscript = { [weak self] transcript in
            Task { @MainActor in self?.handleTranscript(transcript) }
        }
        // Defer the first listen a beat: if a chat coach sheet was up when
        // autopilot was entered, it tears down ITS mic + audio session on
        // the same notification. Letting that settle before we arm our own
        // session avoids the two controllers fighting over AVAudioSession.
        // We install the idle-watcher only AFTER the first listen so the
        // publisher's immediate `.idle` emission (on subscribe) can't open
        // the mic inside the protective window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.isActive else { return }
            self.startListening()
            self.installIdleWatcher()
        }
    }

    /// Re-arm after a SILENT finalize (empty transcript delivers no
    /// `onFinalTranscript`, so the loop would otherwise stall). When the
    /// controller returns to idle while we're live and not mid-request,
    /// open the mic again. Installed after the first listen so the
    /// publisher's replay-on-subscribe `.idle` can't fire prematurely.
    private func installIdleWatcher() {
        guard isActive else { return }
        statusObserver = voice.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.isActive, !self.awaitingReply else { return }
                if status == .idle && !self.voice.isRecording {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        guard self.isActive, !self.awaitingReply,
                              !self.voice.isRecording else { return }
                        self.startListening()
                    }
                }
            }
    }

    /// Stop the loop, release the mic, drop the HUD.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        awaitingReply = false
        statusObserver?.cancel()
        statusObserver = nil
        voice.onFinalTranscript = nil
        voice.silenceAutoStopInterval = nil
        voice.cancel()
        NotificationCenter.default.post(name: .esangExitAutopilot, object: nil)
    }

    /// Arm the mic for the next utterance (no-op if already recording or
    /// autopilot was just torn down).
    private func startListening() {
        guard isActive else { return }
        statusLine = "Listening…"
        // `toggle()` starts when idle. If a previous cycle left it
        // mid-finalize, the controller drains before responding.
        if !voice.isRecording { voice.toggle() }
        // Surface a permission denial honestly instead of a silent loop.
        if case .denied(let reason) = voice.status {
            statusLine = reason
        }
    }

    @MainActor
    private func handleTranscript(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty else {
            // Empty utterance — just re-arm so the operator can try again.
            if isActive { startListening() }
            return
        }
        lastHeard = text

        // ── FAST LOCAL INTENT ────────────────────────────────────────────
        // Act on the common spoken NAVIGATION commands INSTANTLY + reliably
        // on-device — independent of the ESANG server round-trip. The server
        // turn depends on a (possibly stale/slow) deploy returning a
        // perfectly-formatted <<<ACTION:…>>> token; when it doesn't, autopilot
        // "heard but did nothing." This short-circuits the obvious commands
        // ("go to my loads", "post a load", "market intelligence", "go home",
        // "back", …) through the SAME dispatcher, so they always act. Anything
        // not an obvious navigation falls through to the full ESANG turn.
        if let local = eSangAutopilot.localNavIntent(for: text) {
            statusLine = "On it"
            if role == .driver {
                onDriverAction?(local)
            } else {
                eSangRoleDispatcher.dispatch(local, role: role, dismissSheet: {})
            }
            Task { await ESangTTSPlayer.shared.speak("On it.", serverAudioBase64: nil) }
            awaitingReply = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isActive else { return }
                self.startListening()
            }
            return
        }
        // ─────────────────────────────────────────────────────────────────

        statusLine = "Thinking…"
        // Guard the idle-watcher from re-arming the mic while the ESANG
        // round-trip is in flight; cleared after the dispatch settles.
        awaitingReply = true
        let dispatchRole = role
        let driverAction = onDriverAction
        // ── ESANG VISION GROUNDING ──
        // PRIVACY: this screenshot is captured ONLY here, inside a
        // user-initiated hands-free AUTOPILOT turn (we're inside the engine's
        // own transcript handler, which only runs while `isActive`). It is
        // sent to ESANG so the model can ground a `<<<ACTION:tap:CX x CY>>>`
        // on a control the operator can actually see. No capture happens for
        // text or coach chat, and capture is best-effort — a nil snapshot
        // still sends a perfectly good text-only command (autopilot keeps
        // working). `drawHierarchy(in:afterScreenUpdates:)` MUST run on the
        // main thread, so we snapshot here (this handler is `@MainActor`).
        let shot = EusoAutopilotEngine.captureKeyWindowForVision()
        Task {
            var reply = ""
            do {
                // 2026-06-03 — AUTOPILOT FIX. The voice command was being sent
                // raw to esang.chat (the safety COACH prompt), which just chats
                // ("No…") and never emits the <<<ACTION:…>>> control tokens the
                // dispatcher needs — so autopilot "did nothing". Wrap the
                // transcript in an explicit autopilot directive so the model
                // drives the app. (Belt-and-suspenders for the server prompt;
                // the matching server-side autopilot.* branch lands separately.)
                // When a screenshot rode along, ESANG can ground a tap on a
                // VISIBLE control via the vision token; only advertise that
                // grammar when we actually attached an image (else the model
                // would hallucinate coordinates with nothing to look at).
                let tapGrammar = shot != nil ? """

                <<<ACTION:tap:CX x CY>>>     — tap a control you can SEE in the attached screenshot. CX and CY are NORMALIZED 0..1 coordinates (top-left origin): CX=0 is the left edge, CX=1 the right; CY=0 the top, CY=1 the bottom. Use this only for an on-screen button/cell with no navigate/back equivalent.
                """ : ""
                let piloted = """
                [EUSOTRIP AUTOPILOT] You are ESANG driving the app hands-free for a \(dispatchRole.rawValue). The operator spoke the command below. Reply with a SHORT spoken confirmation (under 12 words), then the EXACT control tokens to execute it — emit them literally, one per action, using this grammar:
                <<<ACTION:navigate:/PATH>>>  — drive the screen there. Valid PATHs include /home /loads /me /trips /wallet /settlements /compliance /marketplace /dispatch/planner /shipper/settlements /rail/marketplace /vessel/bookings plus any visible tab name.
                <<<ACTION:back>>>            — go back one screen.\(tapGrammar)
                Rules: NEVER refuse a navigation request; if the exact screen is unclear pick the closest tab and STILL emit a navigate token. Prefer navigate/back over tap when an equivalent exists. Do not describe the tokens.
                Operator command: \(text)
                """
                let resp = try await EusoTripAPI.shared.esang.chat(
                    message: piloted,
                    currentPage: "autopilot.\(dispatchRole.rawValue)",
                    loadId: nil,
                    // ESANG VISION GROUNDING — attach the live screenshot
                    // (nil when capture failed; the chat then sends the exact
                    // text-only payload it did before and autopilot still
                    // navigates/executes — it just can't ground a tap).
                    screenB64: shot?.b64,
                    screenW: shot?.width,
                    screenH: shot?.height
                )
                reply = resp.message
            } catch {
                reply = "I couldn't reach ESANG just now — say that again and I'll retry."
            }
            let (_, actions) = eSangAutopilot.parse(reply)
            await MainActor.run {
                guard self.isActive else { return }
                // Dispatch each parsed action to the CURRENT role. Driver
                // uses the ContentView-owned typed handler; every other
                // role resolves through the role dispatcher (which posts
                // the right push-nav swap / back / execute notification).
                for (idx, action) in actions.enumerated() {
                    let delay = Double(idx) * 0.20
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard self.isActive else { return }
                        if dispatchRole == .driver {
                            driverAction?(action)
                        } else {
                            eSangRoleDispatcher.dispatch(
                                action,
                                role: dispatchRole,
                                dismissSheet: {}
                            )
                        }
                    }
                }
                // HONEST NO-OP FEEDBACK. The model gave us actions, but if
                // the turn carried NAVIGATION intent and NONE of those
                // navigational actions resolved to a real, in-role screen,
                // the surface only bounced to home — the operator asked to
                // go somewhere and effectively nothing happened. Never leave
                // them staring at an unchanged screen with no feedback:
                // surface an honest HUD line and (if TTS is available) say
                // it. Driver resolves through its own typed tab handler, so
                // we only run this for the non-Driver dispatcher path where
                // the path-resolution gap lives.
                if dispatchRole != .driver {
                    let navActions = actions.filter { eSangRoleDispatcher.isNavigational($0) }
                    let anyResolved = navActions.contains {
                        eSangRoleDispatcher.resolvesToRealScreen($0, role: dispatchRole)
                    }
                    if !navActions.isEmpty && !anyResolved {
                        let heard = self.lastHeard.isEmpty ? transcript : self.lastHeard
                        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
                        let line = trimmed.isEmpty
                            ? "I couldn't open that here."
                            : "I heard \u{201C}\(trimmed)\u{201D} but couldn't open it here."
                        self.statusLine = line
                        Task { await ESangTTSPlayer.shared.speak(line, serverAudioBase64: nil) }
                    }
                }
                // Re-arm the mic for the next command after the actions
                // settle, so autopilot stays hands-free across a sequence.
                let reArm = Double(max(actions.count, 1)) * 0.20 + 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + reArm) {
                    self.awaitingReply = false
                    guard self.isActive else { return }
                    self.startListening()
                }
            }
        }
    }

    /// Handle an ESANG vision-grounded tap. Activates the control under the
    /// normalized point (with a visible pulse). On a MISS — no activatable
    /// element there — we do NOT fail silently: ESANG speaks an honest line,
    /// the HUD shows it, and the mic re-arms so the operator can retry or
    /// give a different command. Main-actor only (touches UIKit + the loop).
    @MainActor
    func handleTapAtPoint(nx: Double, ny: Double) {
        // Defense-in-depth: never drive a real screen tap unless autopilot is
        // actively listening. The `.esangTapAtPoint` observer already gates on
        // this, but `handleTapAtPoint` is a public method — guard here too so
        // no caller can stage an unsolicited tap outside hands-free autopilot.
        guard isActive else { return }
        #if canImport(UIKit)
        Self.activateAccessibilityElement(atNormalized: nx, ny: ny) { [weak self] in
            // ── Honest miss path ──
            guard let self else { return }
            let line = "I see it but couldn't tap there."
            self.statusLine = line
            Task { await ESangTTSPlayer.shared.speak(line, serverAudioBase64: nil) }
            // Re-arm so autopilot keeps listening (don't strand the loop).
            self.awaitingReply = false
            if self.isActive { self.startListening() }
        }
        #else
        // No UIKit — can't tap; stay honest and re-arm.
        statusLine = "Tap isn't available here."
        awaitingReply = false
        if isActive { startListening() }
        #endif
    }

    // MARK: - ESANG vision grounding (capture + activate)

    /// A captured screen for ESANG vision grounding: the base64 JPEG plus
    /// the downscaled pixel dimensions the tap-grounder reasons over.
    struct VisionShot {
        let b64: String
        let width: Int
        let height: Int
    }

    /// Snapshot the active key window for ESANG vision grounding, downscale
    /// to a ~1024px long edge, JPEG-encode (quality ~0.5), and base64. Runs
    /// on the main actor because `drawHierarchy(in:afterScreenUpdates:)`
    /// MUST be called on the main thread. Returns `nil` on any failure (no
    /// window, empty bounds, or no UIKit) — the caller then sends a
    /// text-only command, so autopilot never silently dies on a bad capture.
    ///
    /// PRIVACY: only ever invoked from `handleTranscript`, i.e. inside a
    /// user-initiated hands-free autopilot turn. Never for text/coach chat.
    @MainActor
    static func captureKeyWindowForVision() -> VisionShot? {
        #if canImport(UIKit)
        guard let window = activeKeyWindow() else { return nil }
        let bounds = window.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        // Render the window hierarchy at native scale into an image. Read
        // the scale from the trait collection (non-deprecated; `window.screen`
        // is deprecated on newer SDKs) and clamp to a sane floor.
        let format = UIGraphicsImageRendererFormat()
        let displayScale = window.traitCollection.displayScale
        format.scale = displayScale > 0 ? displayScale : 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let full = renderer.image { _ in
            // afterScreenUpdates:false — capture what's on screen NOW,
            // synchronously, without forcing a relayout pass (cheaper and
            // avoids re-entrancy with an in-flight layout).
            _ = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }

        // Downscale so the long edge is ~1024px — small enough to keep the
        // upload light, large enough for the grounder to read a control.
        let longEdge = max(full.size.width, full.size.height)
        let target: CGFloat = 1024
        let scale = longEdge > target ? target / longEdge : 1
        let outSize = CGSize(width: (full.size.width * scale).rounded(),
                             height: (full.size.height * scale).rounded())
        let scaledFormat = UIGraphicsImageRendererFormat()
        scaledFormat.scale = 1          // 1:1 — outSize is already in pixels
        scaledFormat.opaque = true
        let down = UIGraphicsImageRenderer(size: outSize, format: scaledFormat)
            .image { _ in full.draw(in: CGRect(origin: .zero, size: outSize)) }

        guard let jpeg = down.jpegData(compressionQuality: 0.5) else { return nil }
        return VisionShot(b64: jpeg.base64EncodedString(),
                          width: Int(outSize.width),
                          height: Int(outSize.height))
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    /// The foreground-active key window across all connected scenes (the
    /// surface the operator is actually looking at). Falls back to any
    /// key window, then any window, so a snapshot/activation still has a
    /// target even mid scene-transition.
    @MainActor
    static func activeKeyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        // Prefer the foreground-active scene's key window.
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }),
           let key = active.keyWindow ?? active.windows.first(where: { $0.isKeyWindow }) {
            return key
        }
        // Fall back to any key window across scenes, then any window.
        let allWindows = scenes.flatMap { $0.windows }
        return allWindows.first(where: { $0.isKeyWindow }) ?? allWindows.first
    }

    /// ESANG VISION GROUNDING — activate a control at a NORMALIZED point.
    /// `nx`/`ny` are 0…1 (top-left origin). Converts to a window-space
    /// CGPoint, hit-tests the window's ACCESSIBILITY tree (recursing
    /// `accessibilityElements` / `subviews`) for the DEEPEST element whose
    /// `accessibilityActivationPoint`/`accessibilityFrame` contains the
    /// point AND which reports `accessibilityActivate()` == true, then
    /// activates it. Pulses a small expanding ring at the point so the tap
    /// is visible. If nothing activatable sits under the point, calls
    /// `onMiss` so the caller can speak/show an honest message and re-arm
    /// the mic — never a silent no-op. Main-actor only.
    @MainActor
    static func activateAccessibilityElement(atNormalized nx: Double,
                                             ny: Double,
                                             onMiss: () -> Void) {
        guard let window = activeKeyWindow() else { onMiss(); return }
        let bounds = window.bounds
        let windowPoint = CGPoint(x: CGFloat(min(max(nx, 0), 1)) * bounds.width,
                                  y: CGFloat(min(max(ny, 0), 1)) * bounds.height)
        // accessibilityFrame is in SCREEN coordinates; convert once.
        let screenPoint = window.convert(windowPoint, to: nil)

        // Always show the pulse first — the operator sees WHERE ESANG aimed
        // even if the hit-test comes up empty (honest feedback either way).
        pulse(at: windowPoint, in: window)

        if let target = deepestActivatable(in: window,
                                           screenPoint: screenPoint) {
            // Activate via the accessibility action — drives the same code
            // path VoiceOver's double-tap fires, so it works for SwiftUI
            // buttons, list rows, and UIKit controls alike.
            let didActivate = target.accessibilityActivate()
            if !didActivate { onMiss() }
        } else {
            onMiss()
        }
    }

    /// Recurse the accessibility/view tree under `root`, returning the
    /// DEEPEST element whose accessibility frame contains the point and
    /// which can be activated. Depth-first so a leaf control wins over its
    /// container. Checks both `NSObject` accessibility elements (SwiftUI
    /// vends these) and `UIView` subviews.
    @MainActor
    private static func deepestActivatable(in root: NSObject,
                                           screenPoint: CGPoint) -> NSObject? {
        var best: NSObject?

        func frameContains(_ obj: NSObject) -> Bool {
            // `accessibilityFrame` is in SCREEN coordinates. For a UIView it
            // can be .zero until the element is queried for a11y; fall back
            // to the view's own bounds converted to screen space (bounds →
            // window via `convert(_:to: v.window)`, then window → screen via
            // `window.convert(_:to: nil)`).
            var frame = obj.accessibilityFrame
            if frame == .zero, let v = obj as? UIView, v.bounds.width > 0,
               let win = v.window {
                let inWindow = v.convert(v.bounds, to: win)
                frame = win.convert(inWindow, to: nil)
            }
            return frame.contains(screenPoint)
        }
        func isActivatable(_ obj: NSObject) -> Bool {
            // A hidden / a11y-hidden view is never a tap target.
            if let v = obj as? UIView, (v.isHidden || v.alpha < 0.01) { return false }
            if obj.accessibilityElementsHidden { return false }
            // A control that actively reports an activate success is ideal;
            // but `accessibilityActivate()` has side-effects, so we DON'T
            // call it during the search — we treat "has an activation trait
            // or is a UIControl/known activatable" as eligible and let the
            // real call happen once on the winner.
            let traits = obj.accessibilityTraits
            let activatableTraits: UIAccessibilityTraits =
                [.button, .link, .keyboardKey, .adjustable]
            if !traits.intersection(activatableTraits).isEmpty { return true }
            if obj is UIControl { return true }
            // SwiftUI tappable elements expose `.isAccessibilityElement`
            // with a button trait; some custom ones only set
            // `isAccessibilityElement`. Treat a leaf a11y element as
            // eligible — the final `accessibilityActivate()` is the real
            // gate (it returns false for genuinely inert elements).
            if obj.isAccessibilityElement { return true }
            return false
        }

        func recurse(_ obj: NSObject) {
            // Descend into explicit accessibility children first (SwiftUI),
            // then UIView subviews. A deeper hit overwrites a shallower one.
            if let elements = obj.accessibilityElements as? [NSObject] {
                for child in elements where frameContains(child) {
                    if isActivatable(child) { best = child }
                    recurse(child)
                }
            }
            if let view = obj as? UIView {
                // Front-most subviews are last in `subviews`; iterate in
                // reverse so the top-most control wins ties.
                for sub in view.subviews.reversed() where frameContains(sub) {
                    if isActivatable(sub) { best = sub }
                    recurse(sub)
                }
            }
        }

        recurse(root)
        return best
    }

    /// Render a brief expanding-ring pulse at `point` (window coords) on the
    /// key window so an ESANG-driven tap is VISIBLE to the operator. Pure
    /// CoreAnimation — self-removing, non-interactive, never blocks touch.
    @MainActor
    private static func pulse(at point: CGPoint, in window: UIWindow) {
        let diameter: CGFloat = 56
        let ring = UIView(frame: CGRect(x: point.x - diameter / 2,
                                        y: point.y - diameter / 2,
                                        width: diameter, height: diameter))
        ring.isUserInteractionEnabled = false
        ring.layer.cornerRadius = diameter / 2
        ring.layer.borderWidth = 2.5
        // EusoTrip signature glow — high-contrast so it reads on any surface.
        ring.layer.borderColor = UIColor(red: 0.42, green: 0.78,
                                         blue: 1.0, alpha: 0.95).cgColor
        ring.backgroundColor = UIColor(red: 0.42, green: 0.78,
                                       blue: 1.0, alpha: 0.18)
        window.addSubview(ring)

        let expand = CABasicAnimation(keyPath: "transform.scale")
        expand.fromValue = 0.35
        expand.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [expand, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.layer.add(group, forKey: "esangTapPulse")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            ring.removeFromSuperview()
        }
    }
    #endif
}

/// Root-mounted overlay that owns the autopilot engine, listens for the
/// universal enter/exit signals (live + pending latch), and renders the
/// "ESANG is listening… (autopilot)" HUD. Mounted ONCE in ContentView so
/// it works for whatever role is signed in.
private struct EusoAutopilotMount: View {
    /// Current signed-in role — drives which dispatch path the engine uses.
    let role: EusoRole
    /// Driver dispatch closure (ContentView's `handleeSangAction`).
    let onDriverAction: (eSangAction) -> Void

    @StateObject private var engine = EusoAutopilotEngine()
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            if engine.isActive {
                hud
                    .padding(.top, Device.safeTop + Space.s2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: engine.isActive)
        // Live in-session trigger (orb hold while overlay already mounted,
        // or a chat reply carrying <<<ACTION:autopilot>>>). The overlay is
        // always mounted at the root, so this is the PRIMARY activation
        // path; clear the pending latch so it can't double-fire later.
        .onReceive(NotificationCenter.default.publisher(for: .esangEnterAutopilot)) { _ in
            _ = eSangAutopilot.consumePendingAutopilotActivation()
            engine.activate(role: role, onDriverAction: onDriverAction)
        }
        // Allow any surface to cancel autopilot.
        .onReceive(NotificationCenter.default.publisher(for: .esangExitAutopilot)) { _ in
            if engine.isActive { engine.deactivate() }
        }
        // ESANG VISION GROUNDING — a parsed `<<<ACTION:tap:CX x CY>>>` posts
        // `.esangTapAtPoint` (via the role/driver dispatcher). Hit-test the
        // key window's accessibility tree, activate the control there, pulse
        // it, and give honest feedback on a miss. `.onReceive` delivers on
        // the main run loop, so the engine call is main-actor-safe.
        .onReceive(NotificationCenter.default.publisher(for: .esangTapAtPoint)) { note in
            // SAFETY GATE: a vision tap is a REAL screen interaction, so it
            // must only ever fire while hands-free autopilot is armed. A
            // plain (non-autopilot) ESANG chat reply also parses
            // `<<<ACTION:…>>>` tokens (see `.esangActionHandler` on the coach
            // sheet), so a reply that happens to carry a `tap:CX x CY` token
            // could otherwise post `.esangTapAtPoint` and trigger an
            // unsolicited tap. Ignore the signal unless the engine is active.
            guard engine.isActive else { return }
            let nx = (note.userInfo?["x"] as? Double) ?? -1
            let ny = (note.userInfo?["y"] as? Double) ?? -1
            guard (0...1).contains(nx), (0...1).contains(ny) else { return }
            engine.handleTapAtPoint(nx: nx, ny: ny)
        }
        // Pending-latch path: the orb long-press may have fired before this
        // overlay subscribed (it presents a frame after the press). Consume
        // the latch on appear so a hold that beat the observer still arms.
        .onAppear {
            if eSangAutopilot.consumePendingAutopilotActivation() {
                engine.activate(role: role, onDriverAction: onDriverAction)
            }
        }
        // Re-check the latch when the role changes (surface swap remounts).
        .onChange(of: role) { _, _ in
            if eSangAutopilot.consumePendingAutopilotActivation() {
                engine.activate(role: role, onDriverAction: onDriverAction)
            }
        }
    }

    /// Minimal listening HUD. A pulsing orb-tinted capsule with the live
    /// status + last-heard line and a stop control. Tapping anywhere on it
    /// (or the stop glyph) ends autopilot.
    private var hud: some View {
        HStack(spacing: Space.s3) {
            // Orb state tracks the engine's published status (which flips
            // between "Listening…" and "Thinking…" as each command cycles)
            // rather than reading the non-observed voice flag directly.
            OrbeSang(state: engine.statusLine == "Thinking…" ? .thinking : .listening,
                     diameter: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("ESANG · Autopilot")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(engine.lastHeard.isEmpty ? engine.statusLine : engine.lastHeard)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Brand.magenta)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: Brand.blue.opacity(0.30), radius: 16, x: -4, y: 4)
                .shadow(color: Brand.magenta.opacity(0.30), radius: 16, x: 4, y: 4)
        )
        .padding(.horizontal, Space.s4)
        .contentShape(Capsule())
        .onTapGesture { engine.deactivate() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ESANG autopilot is listening. \(engine.lastHeard)")
        .accessibilityHint("Double tap to stop autopilot.")
    }
}

// MARK: - Previews

#Preview("Root · Night") {
    ContentView().preferredColorScheme(.dark)
}

#Preview("Root · Afternoon") {
    ContentView().preferredColorScheme(.light)
}
