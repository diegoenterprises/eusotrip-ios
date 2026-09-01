//
//  LoadDetailSheet.swift
//  EusoTrip — Full load-detail sheet opened when a driver taps a pin on
//  the Eusoboards map (or a load card). Mirrors the web platform's load
//  detail view (see `/frontend/server/routers/loads.ts :: getById` and
//  `/frontend/client/src/pages/LoadDetail.tsx`) so the fields the driver
//  sees are the same across surfaces:
//
//    • Origin / destination addresses + pickup / delivery windows
//    • Route preview (static map with a blue→magenta polyline)
//    • Prohibited routes (hazmat / height / weight restrictions)
//    • Permits & licenses required (CDL class, hazmat, TWIC, escort,
//      special permit)
//    • Equipment requirements (dry van / reefer / flatbed / ...)
//    • Cargo + hazmat metadata (UN number, class, packing group, ERG #)
//    • Rate breakdown ($total, $/mi, distance, weight)
//    • Broker + contact
//
//  Brand invariant: uses the same palette / gradient / Space.s* tokens as
//  the rest of the Driver surface. No opaque black cards — every grouping
//  sits on `palette.bgCard` with a gradient-accent border.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import MapKit
import CoreLocation

extension Notification.Name {
    static let eusoLoadConversationOpen = Notification.Name("eusoLoadConversationOpen")
}

struct LoadDetailSheet: View {

    // MARK: - Input

    let load: AvailableLoad
    var onBook: (() -> Void)? = nil
    var onBid: (() -> Void)? = nil
    var onMessageBroker: (() -> Void)? = nil
    /// Optional hero namespace threaded from the load card source so
    /// SwiftUI's `matchedGeometryEffect` interpolates the load id +
    /// origin/destination text from the card into the sheet header
    /// per the 2026 UX motion doc §3.1. nil = legacy call sites that
    /// don't yet pass a namespace; sheet still presents normally.
    var heroNamespace: Namespace.ID? = nil
    /// The load id under the source card's namespace — usually the
    /// same as `load.id` but exposed separately so callers that
    /// transform the model (e.g. `AvailableLoad.from(MyLoad)`) can
    /// keep the source/destination ids in sync.
    var heroSourceId: String? = nil
    /// True when this detail is rendered inside the shared
    /// `RoleDetailLayer` push (push-nav mandate, 2026-06-09 / audit
    /// M25) instead of a presented sheet. In push context the layer's
    /// `BespokeBackBar` owns the exit, so the canonical close X is
    /// hidden (its `dismiss()` would be a dead no-op) and the booked-
    /// card "Done"/"Open My Loads" exit posts `.eusoRoleNavBack` to
    /// pop the layer instead of dismissing a non-existent sheet.
    var hostedInPush: Bool = false

    // MARK: - Environment

    @Environment(\.palette)     private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss)     private var dismiss
    @Environment(\.openURL)     private var openURL

    // MARK: - State

    /// Lazy-loaded commercial context (broker identity + active
    /// agreement type). `nil` until the first fetch resolves; renders
    /// neutral placeholders until then so the sheet doesn't pop in.
    @State private var commercial: LoadsAPI.CommercialContext?
    @State private var commercialError: Bool = false
    /// Escort attachment(s) for this load. `nil` = first fetch hasn't
    /// resolved; `[]` = backend confirmed there's no escort wired
    /// (rendered as the "no escort assigned" card so the driver knows
    /// they're hauling solo, not that the request silently failed).
    @State private var escorts: [LoadsAPI.EscortAssignment]?
    @State private var escortAssignmentError: String?
    @State private var escortRequestCapability: Bool?
    @State private var escortCapabilityError: String?
    /// Counter-offer sheet — driver proposes a different rate on the
    /// posted tender. Backed by `drivers.counterOffer`. The "Bid a
    /// different rate" footer button now flips this true instead of
    /// the prior dead `onBid?()` closure.
    @State private var showCounterOffer: Bool = false
    /// Adaptive fee preview — `adaptiveFee.estimate` returns the
    /// 6-dimension multiplier breakdown + final effective rate +
    /// carrier net. Drivers see the full math before booking so the
    /// settlement isn't a surprise. nil while loading.
    @State private var feePreview: AdaptiveFeeAPI.FeeResult?
    /// Lane benchmark from `rates.compareLaneRate` — drives the
    /// ABOVE_MARKET / AT_MARKET / BELOW_MARKET pill that sits next to
    /// the posted rate. nil while loading; `comparisonError = true`
    /// when the call genuinely failed (we just hide the pill — no
    /// red banner since the rest of the load detail still works).
    @State private var comparison: RatesAPI.LaneComparison?
    @State private var comparisonError: Bool = false
    /// Booking call state. `idle` = "Book now" button shown.
    /// `submitting` = button shows spinner. `booked` = inline success
    /// card. `error` = inline error + retry. Server endpoint:
    /// `loadBidding.submit` at the posted rate (one-tap accept).
    @State private var bookState: BookState = .idle
    @State private var bookRequestKey: String?
    /// Message-thread open state. The CTA resolves a persisted load-scoped
    /// conversation through `messages.getOrCreateLoadConversation`; failures
    /// render inline so the button never degrades into a silent no-op.
    @State private var messageOpenState: MessageOpenState = .idle

    /// Exact server-owned mode-native plan. Every independent GeoJSON line
    /// remains independent; the shared sheet never authors or repairs geometry.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var canonicalRouteDistanceMeters: Int?
    @State private var canonicalRouteDurationSeconds: Int?
    /// Full `loads.getById` projection used when this sheet opens from a
    /// summary row with missing/sentinel geometry. This stays nil unless the
    /// backend supplies a better real route basis.
    @State private var hydratedRouteLoad: AvailableLoad?
    /// Authoritative load projection used for commercial decisions. Summary
    /// board rows do not carry signed truck detention terms, so booking and
    /// bidding wait for this server row instead of inventing client defaults.
    @State private var authoritativeLoadDetail: LoadsAPI.LoadDetail?
    @State private var authoritativeLoadError: String?

    private var routeDetailLoad: AvailableLoad { hydratedRouteLoad ?? load }
    private var authoritativeTransportMode: String? {
        authoritativeLoadDetail?.transportMode ?? load.transportMode
    }
    private var isTruckLoad: Bool {
        authoritativeTransportMode?.lowercased() == "truck"
    }
    private var inheritedTruckDetentionTerms: TruckDetentionNegotiatedTerms? {
        authoritativeLoadDetail?.truckDetentionTerms
    }
    private var authoritativeCurrency: String? {
        inheritedTruckDetentionTerms?.currency.rawValue ?? authoritativeLoadDetail?.currency
    }
    private var commercialAuthorityReady: Bool {
        if let summaryMode = load.transportMode?.lowercased(), summaryMode != "truck" {
            return true
        }
        guard let detail = authoritativeLoadDetail else { return false }
        guard detail.transportMode?.lowercased() == "truck" else { return true }
        return detail.truckDetentionTerms != nil
    }

    enum BookState: Equatable {
        case idle
        case submitting
        case booked(bidId: Int?, status: String)
        case error(String)
    }

    enum MessageOpenState: Equatable {
        case idle
        case resolving
        case failed(String)
    }

    /// Escort-request state for the empty-state "Request …" button.
    /// `idle` = button shown. `requesting` = spinner. `requested` =
    /// success confirmation. `failed` = inline retry. The request is a
    /// real action (MeAction fire + dispatch message) — not a dead
    /// label (founder note "didnt see add escort").
    @State private var escortRequestState: EscortRequestState = .idle

    enum EscortRequestState: Equatable {
        case idle
        case requesting
        case requested
        case failed(String)
    }

    // MARK: - Mode resolution
    //
    // Resolve the load's transport mode once. Every mode-aware surface on
    // this sheet (prohibited routes, escort vocabulary) reads from this so
    // a vessel load never shows trucking copy and vice-versa. Defaults to
    // `.truck` when the source row carried no `transportMode`, so existing
    // truck loads render exactly as before.
    private var mode: TransportMode {
        TransportMode(rawValue: load.transportMode ?? "truck") ?? .truck
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                routeCard
                rateRow
                if isTruckLoad || load.transportMode?.lowercased() == "truck" {
                    truckDetentionAuthorityCard
                }
                if let agreement = commercial?.agreement {
                    agreementRow(agreement)
                }
                equipmentAndPermitsCard
                cargoCard
                prohibitedRoutesCard
                // Inline regulatory panel — mirrors the web platform's
                // `<RegulatoryCompliancePanel />` (see
                // frontend/client/src/components/RegulatoryCompliancePanel.tsx)
                // embedded in LoadDetails for every load. Pins the
                // March 23, 2026 FMCSA rules that touch the rig itself:
                // § 393.67 overfill cap, § 393.67 auxiliary-pump carve-out,
                // and § 393.95 warning-device update. Driver sees the
                // citations directly next to the load they're about to
                // book / execute — no hub to navigate away from.
                ComplianceInlinePanel(
                    tags: [.overfill, .auxPump, .warningDevice],
                    topic: "Equipment compliance (Mar 23, 2026)",
                    mode: mode
                )
                if let f = feePreview {
                    feeBreakdownCard(f)
                }
                escortCard
                brokerCard
                // `actionButtons` lives in the sticky footer below
                // (.safeAreaInset) — keeping it in-scroll pushed the
                // Book now / Bid CTAs below the fold on long loads, so
                // testers "couldn't book". This trailing spacer keeps
                // the last scroll content clear of the pinned footer.
                Color.clear.frame(height: Space.s5)
            }
            .padding(Space.s5)
        }
        .scrollIndicators(.hidden)
        // Sticky CTA footer — mirrors the shipper sheet's
        // `podDecisionBar` (205_ShipperLoadDetail.swift). Book now /
        // Bid a different rate stay pinned to the bottom regardless of
        // load length so the primary affordance is always reachable.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                IridescentHairline()
                actionButtons
                    .padding(.horizontal, Space.s5)
                    .padding(.vertical, Space.s3)
            }
            .background(palette.bgSheet)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            // Canonical close X. Replaces the bespoke inline button
            // so this sheet shares the same hit-target geometry +
            // press animation as every other sheet in the app per
            // the 2026 UX motion doc. Sheet-hosting only — in push
            // context the BespokeBackBar owns the exit and dismiss()
            // would be a dead no-op (audit M25).
            if !hostedInPush {
                SheetCloseButton { dismiss() }
                    .padding(Space.s4)
            }
        }
        // Uniform cafe-door entrance — loads used to snap in.
        .screenTileRoot()
        // Lazy-load broker + agreement context. Failures land in
        // `commercialError` so the broker card can render an em-dash
        // neutral state rather than a red toast — drivers shouldn't
        // see a "load failed to fetch broker" panic 65 mph.
        .task(id: load.id) {
            // Hard 6-second timeout — `Loading…` was hanging forever
            // when the procedure was slow or the network blipped, per
            // the founder report 2026-05-06 (broker line stuck on
            // "Loading…" with no fallback). Whichever finishes first
            // (real fetch or timeout) flips `commercial` or
            // `commercialError` so the broker card always resolves to
            // a non-loading state within 6s.
            // Server's `loads.getCommercialContext` does
            // `parseInt(input.loadId)` and returns null when that's
            // NaN. AvailableLoad's `load.id` is the human-readable
            // loadNumber (e.g. "LD-MATRIX-50-2026-04-26-D1461BB0")
            // while the server expects the numeric id. Use
            // `backendLoadId` when populated; only fall through to
            // `load.id` for legacy callers that haven't wired the
            // numeric id yet.
            let resolvedLoadId: String = {
                if let n = load.backendLoadId { return String(n) }
                return load.id
            }()
            let result: Result<LoadsAPI.CommercialContext?, Error> = await withTaskGroup(
                of: Result<LoadsAPI.CommercialContext?, Error>.self
            ) { group in
                group.addTask {
                    do {
                        let r = try await EusoTripAPI.shared.loads
                            .getCommercialContext(loadId: resolvedLoadId)
                        return .success(r)
                    } catch {
                        return .failure(error)
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    return .failure(URLError(.timedOut))
                }
                let first = await group.next() ?? .failure(URLError(.unknown))
                group.cancelAll()
                return first
            }
            switch result {
            case .success(let ctx):
                commercial = ctx
                // When ctx is nil (server returned null because the
                // loadId couldn't be resolved on its side), flip the
                // error flag so the view falls out of "Loading…" into
                // the neutral em-dash state.
                commercialError = (ctx == nil)
            case .failure:
                commercialError = true
            }
        }
        .task(id: load.id) {
            escortAssignmentError = nil
            escortCapabilityError = nil
            escortRequestCapability = nil
            let loadRef = load.backendLoadId.map(String.init) ?? load.id
            do {
                escorts = try await EusoTripAPI.shared.loads
                    .getEscortAssignment(loadId: loadRef)
            } catch {
                escorts = []
                escortAssignmentError = error.eusoUserCopy
            }

            guard let backendId = load.backendLoadId else {
                escortRequestCapability = false
                return
            }
            do {
                escortRequestCapability = try await EusoTripAPI.shared.escort
                    .getRequestCapability(loadId: backendId).canRequest
            } catch {
                escortCapabilityError = error.eusoUserCopy
            }
        }
        .task(id: canonicalRouteDistanceMeters) {
            // Distance-sensitive fee math must wait for the exact released
            // route.plan distance; summary/legacy estimates never enter money.
            guard let distanceMiles = canonicalDistanceMiles else {
                feePreview = nil
                return
            }
            let isHaz = load.hazmat
            let equip = mapEquipmentForFee(load.equipment)
            let vert  = isHaz ? "hazmat" : mapVerticalForFee(load.equipment)
            do {
                feePreview = try await EusoTripAPI.shared.adaptiveFee.estimate(
                    loadRate: load.rate,
                    vertical: vert,
                    equipmentType: equip,
                    hazmatClass: isHaz ? "class_3" : "none",
                    distanceMiles: distanceMiles,
                    loadType: commercial?.agreement?.contractDuration ?? "spot"
                )
            } catch {
                feePreview = nil
            }
        }
        .task(id: canonicalRouteDistanceMeters) {
            // Lane benchmark from `rates.compareLaneRate` — drives the
            // ABOVE_MARKET / AT_MARKET / BELOW_MARKET pill above the
            // book/bid buttons. Skip the call when the AvailableLoad
            // adapter couldn't extract origin/dest state codes (rare —
            // mostly preview rows) so we don't send a malformed query.
            guard let oSt = load.originState,
                  let dSt = load.destState,
                  let distanceMiles = canonicalDistanceMiles else {
                comparison = nil
                return
            }
            do {
                comparison = try await EusoTripAPI.shared.rates.compareLaneRate(
                    originState: oSt,
                    destState: dSt,
                    rate: load.rate,
                    distance: distanceMiles,
                    cargoType: load.equipment.lowercased(),
                    lookbackDays: 90
                )
                comparisonError = false
            } catch {
                comparison = nil
                comparisonError = true
            }
        }
        .task(id: load.id) {
            // Resolve only through the canonical server plan authority.
            await hydrateRouteLoadIfNeeded()
            await refreshCanonicalRoute()
        }
    }

    /// Summary board rows can carry display labels without geometry. Before
    /// giving up on the map, hydrate the full load row by numeric id and use its stored
    /// pickup/delivery JSON and distance. This never guesses coordinates:
    /// if the backend record still lacks real geometry, the route card keeps
    /// its honest unavailable state.
    @MainActor
    private func hydrateRouteLoadIfNeeded() async {
        guard authoritativeLoadDetail == nil,
              let backendId = load.backendLoadId else { return }
        do {
            guard let full = try await EusoTripAPI.shared.loads.getDetail(id: String(backendId)) else {
                authoritativeLoadError = "This load is no longer available. Refresh the board before bidding."
                return
            }
            authoritativeLoadDetail = full
            authoritativeLoadError = nil

            guard hydratedRouteLoad == nil,
                  load.miles <= 0 || routeCoordinates(for: load) == nil else {
                return
            }
            let candidate = routeHydratedCopy(from: full)
            guard candidate.miles > 0 ||
                  routeCoordinates(for: candidate) != nil else {
                return
            }
            hydratedRouteLoad = candidate
        } catch {
            authoritativeLoadDetail = nil
            authoritativeLoadError = "Signed load terms could not be loaded. Refresh this load before bidding."
        }
    }

    private func routeHydratedCopy(from detail: LoadsAPI.LoadDetail) -> AvailableLoad {
        let authoritativeOrigin = LatLongParser.validatedCoordinate(
            latitude: detail.pickupLocation?.lat,
            longitude: detail.pickupLocation?.lng
        )
        let authoritativeDestination = LatLongParser.validatedCoordinate(
            latitude: detail.deliveryLocation?.lat,
            longitude: detail.deliveryLocation?.lng
        )
        let existingOrigin = load.originCoordinate
        let existingDestination = load.destinationCoordinate
        let originLabel = detail.pickupLocation?.cityState.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationLabel = detail.deliveryLocation?.cityState.trimmingCharacters(in: .whitespacesAndNewlines)
        return AvailableLoad(
            id: load.id,
            origin: originLabel?.isEmpty == false ? originLabel! : load.origin,
            destination: destinationLabel?.isEmpty == false ? destinationLabel! : load.destination,
            miles: 0,
            equipment: load.equipment,
            rate: load.rate,
            rpm: 0,
            pickupWindow: load.pickupWindow,
            broker: load.broker,
            hazmat: load.hazmat,
            weight: load.weight,
            hotScore: load.hotScore,
            originLat: authoritativeOrigin?.latitude ?? existingOrigin?.latitude,
            originLng: authoritativeOrigin?.longitude ?? existingOrigin?.longitude,
            destLat: authoritativeDestination?.latitude ?? existingDestination?.latitude,
            destLng: authoritativeDestination?.longitude ?? existingDestination?.longitude,
            backendLoadId: Int(detail.id) ?? load.backendLoadId,
            originState: detail.origin?.state ?? detail.pickupLocation?.state ?? load.originState,
            destState: detail.destination?.state ?? detail.deliveryLocation?.state ?? load.destState,
            transportMode: detail.transportMode ?? load.transportMode,
            equipmentRaw: detail.equipmentType ?? detail.cargoType ?? load.equipmentRaw
        )
    }

    private var canonicalRoutePurpose: CanonicalRoutePlanClient.Purpose {
        let status = authoritativeLoadDetail?.status.lowercased() ?? ""
        let activeStates = [
            "assigned", "dispatched", "en_route", "enroute",
            "in_transit", "at_pickup", "loaded", "at_delivery", "delivered"
        ]
        if activeStates.contains(where: status.contains) { return .activeJob }
        if status.contains("accepted") || status.contains("awarded") { return .planning }
        return .posting
    }

    /// The shared sheet sends only subject identity and purpose. The server
    /// resolves mode, waypoints, requirement/asset profile, graph, evidence,
    /// constraints, and geometry.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        canonicalRouteDistanceMeters = nil
        canonicalRouteDurationSeconds = nil
        guard let loadId = authoritativeLoadDetail.flatMap({ Int($0.id) })
                ?? load.backendLoadId else {
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: loadId,
                purpose: canonicalRoutePurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: loadId)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: loadId)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(loadId: Int) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard route.plan.purpose == canonicalRoutePurpose,
              let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteStatus = "Canonical route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteDistanceMeters = route.plan.distanceMeters
        canonicalRouteDurationSeconds = route.plan.durationSeconds
        canonicalRouteStatus = nil
    }

    private var canonicalDistanceMiles: Double? {
        guard let meters = canonicalRouteDistanceMeters, meters > 0 else { return nil }
        return Double(meters) / 1_609.344
    }

    private var canonicalRatePerMile: Double? {
        guard let miles = canonicalDistanceMiles, miles > 0 else { return nil }
        return load.rate / miles
    }

    /// Map iOS load.equipment string → server `equipmentEnum`. The
    /// load board ships short labels ("Reefer", "Flatbed", "Dry Van")
    /// while the server expects snake_case enum values.
    private func mapEquipmentForFee(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("reefer")  { return "reefer" }
        if s.contains("flatbed") { return "flatbed" }
        if s.contains("step")    { return "step_deck" }
        if s.contains("tank")    { return "tanker" }
        if s.contains("hot")     { return "hotshot" }
        if s.contains("power")   { return "power_only" }
        if s.contains("pneumatic") { return "pneumatic" }
        return "dry_van"
    }

    /// Map iOS load.equipment → server `verticalEnum`. Reefers map
    /// to "refrigerated"; flatbeds to "flatbed", etc. Falls back to
    /// "general_freight" — the spec's domestic dry-van baseline.
    private func mapVerticalForFee(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("reefer")    { return "refrigerated" }
        if s.contains("flatbed")   { return "flatbed" }
        if s.contains("tank")      { return "tanker" }
        if s.contains("auto")      { return "auto_transport" }
        if s.contains("intermodal"){ return "intermodal" }
        if s.contains("ltl")       { return "ltl" }
        if s.contains("heavy")     { return "heavy_haul" }
        if s.contains("livestock") { return "livestock" }
        if s.contains("dry bulk") || s.contains("pneumatic") { return "dry_bulk" }
        if s.contains("household") { return "household" }
        return "general_freight"
    }

    // MARK: Fee breakdown card

    @ViewBuilder
    private func feeBreakdownCard(_ f: AdaptiveFeeAPI.FeeResult) -> some View {
        sectionCard(title: "WHAT YOU NET",
                    subtitle: "EusoWallet adaptive fee · live preview") {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "$%.2f", f.carrierPayment ?? 0))
                        .font(.system(size: 36, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f%%", f.effectiveRate * 100))
                            .font(EType.bodyStrong.monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text(String(format: "$%.2f fee", f.feeAmount))
                            .font(EType.caption.monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Divider().overlay(palette.borderFaint)
                Text("MULTIPLIER BREAKDOWN")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                if let breakdown = f.breakdown {
                    feeBreakdownRow("Base rate",         value: String(format: "%.2f%%", breakdown.baseRate * 100))
                    feeBreakdownRow("Country",           value: String(format: "× %.2f", breakdown.countryMultiplier))
                    feeBreakdownRow("Vertical",          value: String(format: "× %.2f", breakdown.verticalMultiplier))
                    feeBreakdownRow("Equipment",         value: String(format: "× %.2f", breakdown.productMultiplier))
                    feeBreakdownRow("Hazmat",            value: String(format: "× %.2f", breakdown.hazmatMultiplier))
                    feeBreakdownRow("Distance",          value: String(format: "× %.2f", breakdown.distanceMultiplier))
                    feeBreakdownRow("Cycle dampener",    value: String(format: "× %.2f", breakdown.cycleDampener))
                    feeBreakdownRow("Spot/contract",     value: String(format: "× %.2f", breakdown.loadTypeAdjustment))
                    if breakdown.gamificationDiscount > 0 {
                        feeBreakdownRow(
                            "Gamification discount",
                            value: String(format: "−%.2f%%", breakdown.gamificationDiscount * 100),
                            positive: true
                        )
                    }
                    HStack {
                        Image(systemName: cyclePhaseGlyph(breakdown.cyclePhase))
                            .foregroundStyle(cyclePhaseTint(breakdown.cyclePhase))
                        Text("Market \(breakdown.cyclePhase.capitalized) · MHI \(Int(breakdown.marketHealthIndex.rounded()))")
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    private func feeBreakdownRow(_ label: String, value: String, positive: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.caption.monospacedDigit())
                .foregroundStyle(positive ? Brand.success : palette.textPrimary)
        }
    }

    private func cyclePhaseGlyph(_ phase: String) -> String {
        switch phase.uppercased() {
        case "EXPANSION":   return "arrow.up.right.circle.fill"
        case "CONTRACTION": return "arrow.down.right.circle.fill"
        default:            return "equal.circle.fill"
        }
    }

    private func cyclePhaseTint(_ phase: String) -> Color {
        switch phase.uppercased() {
        case "EXPANSION":   return Brand.success
        case "CONTRACTION": return Brand.danger
        default:            return Brand.warning
        }
    }

    // MARK: - Sections

    private var header: some View {
        let detail = routeDetailLoad
        // Hero id used by §3.1 matchedGeometryEffect. Falls back to
        // the load's own id when the caller didn't pass an explicit
        // source id.
        let heroId = heroSourceId ?? load.id
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(detail.id.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-id", namespace: heroNamespace))
                spotContractBadge
                if detail.hotScore >= 4 {
                    // Patch #2: EusoBadge(.hot). Replaces the hand-rolled
                    // "HOT LANE" Label + gradient capsule so every HOT
                    // marker across the app shares one primitive.
                    EusoBadge(label: "HOT LANE",
                              kind: .hot,
                              icon: Image(systemName: "flame.fill"))
                }
                Spacer()
                Text("Live · updated 12s ago")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                Text(detail.origin)
                    .font(EType.h1).foregroundStyle(LinearGradient.diagonal)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-origin", namespace: heroNamespace))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(detail.destination)
                    .font(EType.h1).foregroundStyle(LinearGradient.diagonal)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-dest", namespace: heroNamespace))
            }
            .lineLimit(2)

            Text(headerRouteFacts(detail))
                .font(EType.caption).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Route card

    private var routeCard: some View {
        let detail = routeDetailLoad
        let coordinates = routeCoordinates(for: detail)
        let routeSubtitle: String = {
            guard let meters = canonicalRouteDistanceMeters, meters > 0 else {
                return "Canonical distance pending"
            }
            let miles = Double(meters) / 1_609.344
            if let seconds = canonicalRouteDurationSeconds, seconds >= 0 {
                let hours = seconds / 3_600
                let minutes = (seconds % 3_600) / 60
                return String(format: "%.1f mi · %dh %02dm planned", miles, hours, minutes)
            }
            return String(format: "%.1f mi planned", miles)
        }()
        return sectionCard(title: "ROUTE", subtitle: routeSubtitle) {
            // Exact canonical geometry can render without endpoint markers.
            // Markers appear only when the hydrated load carries complete real
            // coordinates; summary centroids are never substituted.
            if let center = canonicalRouteLines.lazy.compactMap(\.first).first
                ?? coordinates.map({ HereLatLng($0.pickup) }) {
                let mapTransportMode = EusoTripMapTransportMode(
                    canonicalValue: detail.transportMode
                )
                let routeLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                    .eusoRoute(
                        polyline: line,
                        state: canonicalRoutePurpose == .activeJob ? .active : .planned,
                        label: index == 0
                            ? "Eusorone \(mapTransportMode.rawValue) route plan version \(canonicalRouteVersion ?? 0)"
                            : nil
                        )
                }
                let markerLayers: [HereMapLayer] = coordinates.map { endpoints in
                    [.markers([
                        .init(at: .init(endpoints.pickup), kind: .pickup, label: detail.origin),
                        .init(at: .init(endpoints.delivery), kind: .delivery, label: detail.destination)
                    ])]
                } ?? []
                let mapLayers = routeLayers + markerLayers
                ZStack(alignment: .bottomLeading) {
                    // 2026-05-22: migrated off the legacy raster HereMapView onto
                    // the OMV vector renderer + live add-on layer (HereLiveMapView),
                    // matching the 205_ShipperLoadDetail hero map. Pickup/delivery
                    // pins + route connector on the vector basemap; shipper
                    // situational add-ons (weather + traffic + sponsored ad-zones).
                    HereLiveMapView(
                        center: center,
                        zoom: 6,
                        route: [],
                        baseLayers: mapLayers,
                        addOns: mapTransportMode == .truck ? .shipperTracking : .weather,
                        activeJob: canonicalRoutePurpose == .activeJob,
                        mapModeContext: .unconfirmed(mapTransportMode),
                        endpointLabelToggle: true
                    )
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md,
                                                    style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md,
                                             style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        pickupDeliveryStops
                        if let canonicalRouteStatus {
                            Text(canonicalRouteStatus)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(palette.bgCard.opacity(0.92))
                                .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                                .clipShape(Capsule())
                                .accessibilityLabel(canonicalRouteStatus)
                        }
                    }
                    .padding(10)
                }
            } else {
                routeUnavailablePlaceholder
            }
        }
    }

    /// True only when pickup and delivery are complete, distinct, in-range
    /// coordinates. Unknown geometry remains nil before this function.
    private func routeCoordinatesAreReal(pickup: CLLocationCoordinate2D,
                                         delivery: CLLocationCoordinate2D) -> Bool {
        func isPlottable(_ c: CLLocationCoordinate2D) -> Bool {
            LatLongParser.isValid(c)
        }
        guard isPlottable(pickup), isPlottable(delivery) else { return false }
        // Endpoints must be distinct — a zero-length lane is not a route.
        if abs(pickup.latitude - delivery.latitude) < 0.0001 &&
           abs(pickup.longitude - delivery.longitude) < 0.0001 { return false }
        return true
    }

    private func routeCoordinates(for load: AvailableLoad) ->
        (pickup: CLLocationCoordinate2D, delivery: CLLocationCoordinate2D)? {
        guard let pickup = load.originCoordinate,
              let delivery = load.destinationCoordinate,
              routeCoordinatesAreReal(pickup: pickup, delivery: delivery) else {
            return nil
        }
        return (pickup, delivery)
    }

    /// Shown in place of the route map when the lane has no honest
    /// geometry (centroid miss / missing coords). Never fabricates a route.
    private var routeUnavailablePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("Route preview unavailable")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Text("Awaiting verified pickup & delivery coordinates")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var pickupDeliveryStops: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Gradient endpoint marker (blue-weighted) — pickup side of brand gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Brand.blue, Brand.blue.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 8, height: 8)
                Text("PICKUP · \(load.pickupWindow.uppercased())")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
            }
            HStack(spacing: 6) {
                // Gradient endpoint marker (magenta-weighted) — delivery side of brand gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Brand.magenta, Brand.magenta.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 8, height: 8)
                Text("DELIVERY · \(deliveryTimingLabel)")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(Capsule(style: .continuous).fill(.black.opacity(0.55)))
    }

    private func headerRouteFacts(_ detail: AvailableLoad) -> String {
        let distance = canonicalDistanceMiles
            .map { String(format: "%.1f mi", $0) }
            ?? "Distance pending"
        return "\(distance) · \(detail.equipment.uppercased()) · \(detail.weight.uppercased())"
    }

    private var deliveryTimingLabel: String {
        let raw = authoritativeLoadDetail?.actualDeliveryDate
            ?? authoritativeLoadDetail?.estimatedDeliveryDate
            ?? authoritativeLoadDetail?.deliveryDate
        guard let raw, !raw.isEmpty else { return "SCHEDULE PENDING" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            return raw
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · HH:mm z"
        return formatter.string(from: date).uppercased()
    }

    // MARK: Rate row

    private var rateRow: some View {
        let detail = routeDetailLoad
        let perMile = canonicalRatePerMile
            .map { String(format: "$%.2f", $0) }
            ?? "-"
        let distance = canonicalDistanceMiles
            .map { String(format: "%.1f mi", $0) }
            ?? "-"
        return HStack(spacing: Space.s3) {
            ratePill(value: authoritativeMoney(detail.rate),
                     label: "TOTAL",
                     gradient: true)
            ratePill(value: perMile,
                     label: "PER MILE",
                     gradient: false)
            ratePill(value: distance,
                     label: "DISTANCE",
                     gradient: false)
        }
    }

    private func authoritativeMoney(_ amount: Double, fractionDigits: Int = 0) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(fractionDigits)))
        return authoritativeCurrency.map { "\($0) \(number)" } ?? number
    }

    @ViewBuilder
    private var truckDetentionAuthorityCard: some View {
        sectionCard(
            title: "TRUCK DETENTION",
            subtitle: "Signed load terms inherited by a bid unless you propose a change"
        ) {
            if let terms = inheritedTruckDetentionTerms {
                TruckDetentionTermsSummary(terms: terms, context: "INHERITED SIGNED TERMS")
            } else if authoritativeLoadDetail == nil && authoritativeLoadError == nil {
                HStack(spacing: Space.s2) {
                    ProgressView()
                    Text("Loading signed commercial authority…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(minHeight: 44)
            } else {
                Label(
                    authoritativeLoadError ?? "No signed truck detention terms are attached to this load.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(EType.caption)
                .foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(
                    "Truck detention terms unavailable. " +
                    (authoritativeLoadError ?? "No signed terms are attached to this load.")
                )
            }
        }
    }

    @ViewBuilder
    private func ratePill(value: String, label: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if gradient {
                Text(value)
                    .font(EType.title)
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: Equipment + permits

    private var equipmentAndPermitsCard: some View {
        sectionCard(title: "EQUIPMENT & PERMITS",
                    subtitle: "Required to book this lane") {
            VStack(alignment: .leading, spacing: Space.s2) {
                requirementRow(icon: "truck.box",
                               title: load.equipment,
                               subtitle: "Trailer type required")
                requirementRow(icon: "creditcard.and.123",
                               title: "CDL Class A",
                               subtitle: "Minimum license class")
                if load.hazmat {
                    requirementRow(icon: "exclamationmark.triangle.fill",
                                   title: "Hazmat endorsement (H)",
                                   subtitle: "Driver must hold current H or X endorsement",
                                   accent: Brand.warning)
                    requirementRow(icon: "lock.shield.fill",
                                   title: "TWIC card",
                                   subtitle: "Port / facility access required",
                                   accent: Brand.warning)
                }
                if load.equipment == "Flatbed" || load.equipment == "Step Deck" {
                    requirementRow(icon: "ruler.fill",
                                   title: "Tarps + straps",
                                   subtitle: "4 straps minimum, heavy-duty tarp")
                }
                if load.weight.localizedCaseInsensitiveContains("47") ||
                   load.weight.localizedCaseInsensitiveContains("48") {
                    requirementRow(icon: "scalemass.fill",
                                   title: "Overweight permit",
                                   subtitle: "Gross >46,000 lb, carrier must carry permit",
                                   accent: Brand.warning)
                }
            }
        }
    }

    // Doctrine §2.1: the default accent is the brand gradient (LinearGradient.diagonal).
    // Callers pass a concrete semantic Color (e.g. Brand.warning) only when a utility
    // color is required — hazmat, overweight permit, etc. Nil → gradient per doctrine.
    @ViewBuilder
    private func requirementRow(icon: String,
                                title: String,
                                subtitle: String,
                                accent: Color? = nil) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.map { AnyShapeStyle($0.opacity(0.14)) }
                          ?? AnyShapeStyle(LinearGradient.diagonal.opacity(0.14)))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent.map { AnyShapeStyle($0) }
                                     ?? AnyShapeStyle(LinearGradient.diagonal))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Cargo

    private var cargoCard: some View {
        sectionCard(title: "CARGO", subtitle: nil) {
            VStack(alignment: .leading, spacing: Space.s2) {
                kvRow(key: "Commodity",  value: commodityName)
                kvRow(key: "Weight",     value: load.weight)
                if load.hazmat {
                    kvRow(key: "UN Number",        value: "UN1993")
                    kvRow(key: "Hazard class",     value: "Class 3 · Flammable liquid")
                    kvRow(key: "Packing group",    value: "II")
                    kvRow(key: "ERG guide",        value: "128")
                    kvRow(key: "Emergency phone",  value: "1-800-424-9300 (CHEMTREC)")
                }
            }
        }
    }

    private var commodityName: String {
        switch load.equipment {
        case "Reefer":    return "Refrigerated produce"
        case "Flatbed":   return "Steel coils"
        case "Step Deck": return "Construction equipment"
        case "Power Only":return "Drop-and-hook trailer"
        default:          return load.hazmat ? "Class 3 flammable liquid" : "General freight"
        }
    }

    // MARK: Prohibited routes

    private var prohibitedRoutesCard: some View {
        sectionCard(title: "PROHIBITED ROUTES",
                    subtitle: "Avoid per federal/state rules") {
            VStack(alignment: .leading, spacing: Space.s2) {
                switch mode {
                case .truck:
                    prohibitedRow(icon: "road.lanes.curved.left",
                                  text: "No commercial tunnels carrying Class 3 hazmat (Lincoln Tunnel, Holland Tunnel).")
                        .opacity(load.hazmat ? 1 : 0.5)
                    prohibitedRow(icon: "building.2.fill",
                                  text: "No downtown truck routes between 07:00–09:30 and 16:00–18:30 local.")
                    prohibitedRow(icon: "arrow.up.arrow.down",
                                  text: "Bridges with posted weight <46,000 lb, alternate via I-highways only.")
                    if load.equipment == "Flatbed" || load.equipment == "Step Deck" {
                        prohibitedRow(icon: "exclamationmark.triangle",
                                      text: "Oversized load: follow state DOT permit routing only. No county or city bypass.")
                    }

                case .rail:
                    prohibitedRow(icon: "exclamationmark.triangle",
                                  text: "PHMSA 49 CFR 172.820 rail routing analysis (route selected vs alternatives).")
                        .opacity(load.hazmat ? 1 : 0.5)
                    prohibitedRow(icon: "road.lanes.curved.left",
                                  text: "Railroad restricted/embargoed routings (Railinc OPSL).")
                    prohibitedRow(icon: "arrow.up.arrow.down",
                                  text: "Plate clearance limit (Plate B/C/F) + tunnel/overhead clearance.")
                    prohibitedRow(icon: "gauge.with.dots.needle.bottom.50percent",
                                  text: "Key-train / OT-55 speed + handling (PIH/Class 3).")
                        .opacity(load.hazmat ? 1 : 0.5)

                case .vessel:
                    prohibitedRow(icon: "point.topleft.down.to.point.bottomright.curvepath",
                                  text: "IMO Traffic Separation Schemes + routeing measures (COLREG Rule 10).")
                    prohibitedRow(icon: "smoke.fill",
                                  text: "Emission Control Area — 0.10% sulphur fuel (MARPOL Annex VI).")
                    prohibitedRow(icon: "exclamationmark.octagon",
                                  text: "Areas To Be Avoided / restricted + USCG regulated nav areas.")
                    prohibitedRow(icon: "arrow.up.arrow.down",
                                  text: "Draft (under-keel) + air-draft / bridge & cable clearance.")

                case .barge:
                    prohibitedRow(icon: "lock.fill",
                                  text: "USACE lock status / scheduled closures + lockage delays (LPMS).")
                    prohibitedRow(icon: "water.waves",
                                  text: "Authorized channel + controlling depth (draft limit).")
                    prohibitedRow(icon: "arrow.up.arrow.down",
                                  text: "Fixed/movable bridge + overhead cable clearance (33 CFR 117).")
                    prohibitedRow(icon: "exclamationmark.triangle",
                                  text: "Navigation closures (high-water / ice / dredging / safety zone).")
                }
            }
        }
    }

    @ViewBuilder
    private func prohibitedRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.warning)
                .frame(width: 24)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Escort
    //
    // One row per escort assignment (lead + chase, or both). Always
    // renders a card — when the backend confirms `[]` we surface a
    // "no escort assigned" hint with a permit-aware nudge so the driver
    // knows whether they should be requesting one (oversized /
    // hazmat-with-escort-permit loads) or whether solo is fine.

    @ViewBuilder
    private var escortCard: some View {
        sectionCard(title: "ESCORT", subtitle: nil) {
            if let escortAssignmentError {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Label("Escort details unavailable", systemImage: "exclamationmark.triangle")
                        .font(EType.bodyStrong)
                        .foregroundStyle(Brand.warning)
                    Text(escortAssignmentError)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pull to refresh and try again.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            } else {
                switch escorts {
            case .none:
                HStack(spacing: Space.s2) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading escort assignment…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            case .some(let rows) where rows.isEmpty:
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No \(mode.escortConcept.lowercased()) assigned")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text(mode.escortEmptyNudge)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    if escortRequestCapability == true {
                        escortRequestButton
                    } else if escortRequestCapability == nil, escortCapabilityError == nil {
                        HStack(spacing: Space.s2) {
                            ProgressView().scaleEffect(0.7)
                            Text("Checking request access…")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    if escortCapabilityError != nil {
                        Text("Request access is unavailable. Pull to refresh before requesting an escort.")
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .some(let rows):
                VStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(rows) { row in
                        escortRow(row)
                    }
                }
                }
            }
        }
    }

    /// Real "Request escort" affordance for the empty state. The label
    /// is "Request \(mode.escortConcept.lowercased())" — e.g. "Request
    /// escort vehicle" (truck), "Request harbor pilot + tug escort"
    /// (vessel). There is no dedicated `escorts.request` endpoint, so
    /// this genuinely DOES something: it fires a MeAction (haptic +
    /// surface notification) and posts a dispatch message via the
    /// existing `messages.sendMessage` path keyed on the load id, then
    /// confirms with a "requested from dispatch" success line. The
    /// founder noted the prior label was dead — this is the live wire.
    @ViewBuilder
    private var escortRequestButton: some View {
        switch escortRequestState {
        case .requested:
            HStack(spacing: Space.s2) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Escort requested from dispatch")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.s2)
            .padding(.horizontal, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
            )

        default:
            VStack(alignment: .leading, spacing: Space.s2) {
                Button {
                    Task { await requestEscort() }
                } label: {
                    HStack(spacing: Space.s2) {
                        if case .requesting = escortRequestState {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(escortRequestState == .requesting
                             ? "Requesting…"
                             : "Request \(mode.escortConcept.lowercased())")
                            .font(EType.bodyStrong)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
                }
                .buttonStyle(PressableCardStyle())
                .disabled(escortRequestState == .requesting)

                if case .failed(let msg) = escortRequestState {
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Fire the escort request. The `escorts.requestEscort` procedure now
    /// exists on the backend: it raises a REAL escort demand by flipping
    /// loads.requiresEscort = true (+ escortCount >= 1) so the load surfaces
    /// in the escort marketplace (escorts.getAvailableJobs). We (1) fire a
    /// MeAction for the haptic + any listening surface, (2) call the real
    /// endpoint as the PRIMARY action — the button's success/failure now
    /// reflects this real demand, then (3) post a best-effort dispatch
    /// message on the load's conversation thread (same `messages.sendMessage`
    /// route as 053 dispatch chat) as a non-blocking human-readable courtesy.
    private func requestEscort() async {
        guard escortRequestState != .requesting else { return }
        guard escortRequestCapability == true else {
            escortRequestState = .failed("Request access changed. Pull to refresh before trying again.")
            return
        }
        guard let backendId = load.backendLoadId else {
            escortRequestState = .failed("This load isn't synced yet. Try again once it's posted.")
            return
        }

        escortRequestState = .requesting
        let loadRef = String(backendId)
        let concept = mode.escortConcept

        MeAction.fire("loaddetail.request-escort", userInfo: [
            "loadId": loadRef,
            "mode": mode.rawValue,
            "escortConcept": concept,
        ])

        do {
            _ = try await EusoTripAPI.shared.escort.requestEscort(
                loadId: backendId,
                position: "lead",
                notes: "Requested \(concept.lowercased()) · \(load.origin) → \(load.destination)"
            )
            escortRequestState = .requested

            // SECONDARY (best-effort): post a dispatch message on the load's
            // conversation thread so dispatch sees a human-readable note. A
            // failure here does NOT undo the real demand already committed.
            let body = "Escort request · \(load.origin) → \(load.destination): requesting \(concept.lowercased()) for load \(load.id)."
            _ = try? await EusoTripAPI.shared.messaging.sendMessage(
                conversationId: loadRef,
                content: body,
                type: "text"
            )
        } catch {
            let msg: String
            if let api = error as? EusoTripAPIError, case .trpcError(let m) = api {
                msg = m
            } else {
                msg = "Couldn't reach dispatch. Tap to retry."
            }
            escortRequestState = .failed(msg)
        }
    }

    @ViewBuilder
    private func escortRow(
        _ r: LoadsAPI.EscortAssignment
    ) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: escortGlyph(r.position))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(escortPrimaryLine(r))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(escortSecondaryLine(r))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(r.status.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(palette.bgCardSoft))
                .overlay(Capsule().strokeBorder(palette.borderFaint))
            if let phone = r.escortPhone, !phone.isEmpty,
               let url = URL(string: "tel:\(phone.filter { "+0123456789".contains($0) })") {
	                Button {
	                    openURL(url)
	                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call escort")
            }
        }
    }

    private func escortPrimaryLine(_ r: LoadsAPI.EscortAssignment) -> String {
        let posLabel = escortPositionLabel(r.position)
        if let name = r.companyName, !name.isEmpty { return "\(posLabel) · \(name)" }
        if let name = r.escortName,  !name.isEmpty { return "\(posLabel) · \(name)" }
        return posLabel
    }

    /// Map the backend escort position enum ("lead" / "chase" / "both")
    /// to the mode's native position vocabulary. `escortPositionLabels`
    /// is ordered [primary, secondary, both] per mode — truck reads
    /// [Lead, Chase, Lead + Chase], vessel [Harbor pilot, Bow tug,
    /// Stern tug], etc. Falls back to the raw enum capitalized for any
    /// position the mode list doesn't cover.
    private func escortPositionLabel(_ position: String) -> String {
        let labels = mode.escortPositionLabels
        switch position {
        case "lead":  return labels.first ?? "Lead"
        case "chase": return labels.count > 1 ? labels[1] : "Chase"
        case "both":  return labels.count > 2 ? labels[2] : (labels.first ?? "Both")
        default:      return position.capitalized
        }
    }

    private func escortSecondaryLine(_ r: LoadsAPI.EscortAssignment) -> String {
        var parts: [String] = []
        if let mc = r.companyMc, !mc.isEmpty   { parts.append("MC \(mc)") }
        if let dot = r.companyDot, !dot.isEmpty { parts.append("DOT \(dot)") }
        if let rate = r.rate, let type = r.rateType {
            let formatted = String(format: "$%.0f", rate)
            switch type {
            case "per_mile": parts.append("\(formatted)/mi")
            case "per_hour": parts.append("\(formatted)/hr")
            default:         parts.append(formatted)
            }
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private func escortGlyph(_ position: String) -> String {
        switch position {
        case "lead":  return "arrow.up.forward"
        case "chase": return "arrow.down.left"
        case "both":  return "arrow.left.and.right"
        default:      return "car.side"
        }
    }

    // MARK: Broker
    //
    // Two-pass render. The card always shows a body so the layout doesn't
    // shift when the commercial-context fetch resolves. Until then the
    // subtitle line shows "Loading…" — once the round-trip lands we
    // either:
    //   • paint the real broker (name + DOT/MC + complianceStatus pill),
    //   • paint a "Direct shipper" hint when the load is shipper-direct
    //     (i.e. the shipper isn't categorized as a broker), or
    //   • paint an em-dash neutral state when the lookup failed.
    // The fake "Verified · on-time 94% · 30d" line was a hardcoded
    // placeholder — pulled wholesale per the no-fake-data doctrine.

    private var brokerCard: some View {
        sectionCard(title: brokerSectionTitle, subtitle: nil) {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal.opacity(0.18))
                    Text(brokerInitials)
                        .font(EType.bodyStrong)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(brokerPrimaryLine)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(brokerSecondaryLine)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let pillText = brokerComplianceText {
                    Text(pillText)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(palette.bgCardSoft)
                        )
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }

                Button { handleMessageTap() } label: { messageButtonLabel }
                    .buttonStyle(.plain)
                    .disabled(messageOpenState == .resolving)
                    .accessibilityLabel("Message counterparty")
            }

            if case .failed(let message) = messageOpenState {
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s2)
            }
        }
    }

    @ViewBuilder
    private var messageButtonLabel: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            if messageOpenState == .resolving {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.72)
            } else {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
    }

    /// Message button never goes dead. Two cases:
    ///   1. Caller passed `onMessageBroker` — invoke it (legacy path
    ///      where the surface owns its own threading).
    ///   2. Otherwise resolve the persisted load conversation through
    ///      `messages.getOrCreateLoadConversation`, then ask the app root
    ///      to open that real thread for the active role.
    private func handleMessageTap() {
        if let onMessageBroker {
            onMessageBroker()
            return
        }
        guard messageOpenState != .resolving else { return }
        let loadId = load.backendLoadId.map(String.init) ?? load.id
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            messageOpenState = .failed("This load is missing its conversation id. Refresh the load board and try again.")
            return
        }

        messageOpenState = .resolving
        Task {
            do {
                let conversation = try await EusoTripAPI.shared.messaging
                    .getOrCreateLoadConversation(loadId: loadId)
                await MainActor.run {
                    messageOpenState = .idle
                    NotificationCenter.default.post(
                        name: .eusoLoadConversationOpen,
                        object: nil,
                        userInfo: [
                            "conversationId": conversation.id,
                            "loadId": conversation.loadId ?? loadId,
                            "loadNumber": conversation.loadNumber ?? load.id,
                        ]
                    )
                }
            } catch {
                await MainActor.run {
                    messageOpenState = .failed(messageConversationError(error))
                }
            }
        }
    }

    private func messageConversationError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            switch api {
            case .unauthenticated:
                NotificationCenter.default.post(
                    name: Notification.Name("eusoLogoutRequested"),
                    object: nil
                )
                return "Your session expired. Sign in again, then retry this message."
            case .forbidden(let message), .trpcError(let message):
                return message
            case .httpStatus(let code, _):
                if code == 401 {
                    return "Your session expired. Sign in again, then retry this message."
                }
                if code == 403 {
                    return "This account cannot message on this load."
                }
                return "Could not open this load conversation. Try again in a moment."
            case .decodingFailed:
                return "We could not read this conversation. Refresh the load board and try again."
            case .notConfigured:
                return "Messaging is not configured on this device."
            case .badURL:
                return "Messaging URL was malformed. Refresh the load board and try again."
            case .empty:
                return "Messaging returned an empty response. Try again."
            case .queuedForOfflineReplay:
                return "You are offline. Reconnect, then retry this message."
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Network unavailable. Check your connection and try again."
        }
        return error.localizedDescription
    }

    /// "BROKER" while we still don't know, or when one is wired.
    /// "SHIPPER · DIRECT" once the fetch confirms there's no broker
    /// in the chain and the shipper is the counterparty.
    private var brokerSectionTitle: String {
        guard let c = commercial else { return "BROKER" }
        return c.broker == nil ? "SHIPPER · DIRECT" : "BROKER"
    }

    private var brokerInitials: String {
        let name: String
        if let bn = commercial?.broker?.companyName, !bn.isEmpty {
            name = bn
        } else if !load.broker.isEmpty {
            name = load.broker
        } else {
            return "-"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var brokerPrimaryLine: String {
        if let bn = commercial?.broker?.companyName, !bn.isEmpty { return bn }
        if commercial?.broker == nil, commercial != nil {
            // Confirmed shipper-direct — fall back to whatever name the
            // load card already had so the card isn't blank.
            return load.broker.isEmpty ? "-" : load.broker
        }
        return load.broker.isEmpty ? "-" : load.broker
    }

    private var brokerSecondaryLine: String {
        if commercial == nil {
            // commercialError is set from either the catch path OR the
            // 6s timeout in the .task above. "Tap to message" beats a
            // bare em-dash when the lookup fails — the message button
            // is wired to ESANG fallback so the user always has an
            // action.
            return commercialError ? "Tap to message · context loading" : "Loading…"
        }
        if let b = commercial?.broker {
            var parts: [String] = []
            if let mc = b.mcNumber, !mc.isEmpty  { parts.append("MC \(mc)") }
            if let dot = b.dotNumber, !dot.isEmpty { parts.append("DOT \(dot)") }
            if parts.isEmpty, let cat = b.category {
                return cat.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return parts.joined(separator: " · ")
        }
        return "Shipper-direct load"
    }

    private var brokerComplianceText: String? {
        guard let raw = commercial?.broker?.complianceStatus else { return nil }
        switch raw.lowercased() {
        case "compliant":     return "Compliant"
        case "pending":       return "Pending"
        case "expired":       return "Expired"
        case "non_compliant": return "Non-compliant"
        default:              return nil
        }
    }

    // MARK: Agreement

    /// Compact contract-type chip rendered between the rate row and the
    /// equipment card. Only shows when the backend confirms an active
    /// agreement covers this lane.
    private func agreementRow(
        _ a: LoadsAPI.CommercialContext.Agreement
    ) -> some View {
        sectionCard(title: "CONTRACT", subtitle: nil) {
            HStack(spacing: Space.s2) {
                Image(systemName: agreementGlyph(a.contractDuration))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agreementTypeLabel(a.agreementType))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(agreementSubtitle(a))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(a.agreementNumber)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func agreementTypeLabel(_ raw: String) -> String {
        switch raw {
        case "catalyst_shipper":     return "Carrier ↔ Shipper"
        case "broker_catalyst":      return "Broker ↔ Carrier"
        case "broker_shipper":       return "Broker ↔ Shipper"
        case "catalyst_driver":      return "Carrier ↔ Driver"
        case "escort_service":       return "Escort service"
        case "dispatch_dispatch":    return "Dispatch agreement"
        case "terminal_access":      return "Terminal access"
        case "master_service":       return "Master service"
        case "lane_commitment":      return "Lane commitment"
        case "fuel_surcharge":       return "Fuel surcharge schedule"
        case "accessorial_schedule": return "Accessorial schedule"
        case "nda":                  return "NDA"
        case "factoring":            return "Factoring"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func agreementSubtitle(
        _ a: LoadsAPI.CommercialContext.Agreement
    ) -> String {
        let dur = a.contractDuration.replacingOccurrences(of: "_", with: " ").capitalized
        if let exp = a.expirationDate?.prefix(10) {
            return "\(dur) · expires \(exp)"
        }
        return dur
    }

    private func agreementGlyph(_ duration: String) -> String {
        switch duration {
        case "spot":       return "bolt.fill"
        case "short_term": return "calendar"
        case "long_term":  return "calendar.badge.clock"
        case "evergreen":  return "infinity"
        default:           return "doc.text"
        }
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Space.s2) {
            // Above-market meter — pill above the buttons. Drivers see
            // whether the posted rate lands ABOVE / AT / BELOW market
            // for the lane (last 90d delivered loads, ±25% distance) so
            // they know whether to one-tap Book Now or counter higher.
            if let cmp = comparison {
                rateMeterPill(cmp)
            }

            // Booking state machine — Idle → Submitting → Booked / Error.
            switch bookState {
            case .idle:
                bookNowButton
                bidButton

            case .submitting:
                submittingButton

            case .booked(_, let status):
                bookedCard(status: status)

            case .error(let msg):
                errorCard(msg)
                bookNowButton    // give them retry without re-opening sheet
                bidButton
            }
        }
        .sheet(isPresented: $showCounterOffer) {
            CounterOfferSheet(
                loadId: load.id,
                backendLoadId: load.backendLoadId,
                postedRate: load.rate,
                miles: canonicalDistanceMiles.map { Int($0.rounded()) } ?? 0,
                marketAvgRPM: comparison?.marketAvgRPM,
                currency: authoritativeLoadDetail?.currency,
                transportMode: authoritativeTransportMode,
                inheritedTruckDetentionTerms: inheritedTruckDetentionTerms,
                onSubmitted: { showCounterOffer = false }
            )
            .eusoSheet()
        }
    }

    // MARK: Buttons (split out so the state machine stays readable)

    private var bookNowButton: some View {
        Button {
            Task { await book() }
        } label: {
            Text("Book now · \(authoritativeMoney(load.rate))")
                .font(EType.bodyStrong)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal)
                )
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!commercialAuthorityReady)
        .opacity(commercialAuthorityReady ? 1 : 0.55)
    }

    private var bidButton: some View {
        Button {
            showCounterOffer = true
            onBid?()
        } label: {
            Text("Bid a different rate")
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                )
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!commercialAuthorityReady)
        .opacity(commercialAuthorityReady ? 1 : 0.55)
    }

    private var submittingButton: some View {
        HStack(spacing: Space.s2) {
            ProgressView().tint(.white)
            Text("Booking…")
                .font(EType.bodyStrong)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal)
        )
    }

    private func bookedCard(status: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: status == "auto_accepted" ? "checkmark.seal.fill" : "paperplane.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(status == "auto_accepted" ? "Booked · auto-accepted" : "Bid sent · awaiting shipper")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(status == "auto_accepted"
                 ? "Your bid matched a shipper auto-accept rule. The load is yours. Head to My Loads to start the trip."
                 : "Your bid is in the chain. You'll get a realtime push the moment the shipper accepts, counters or assigns to another carrier.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onBook?()
                // Push-hosted: pop the RoleDetailLayer (dismiss() would
                // be a no-op with no presentation). Sheet-hosted: the
                // normal dismissal. (Audit M25.)
                if hostedInPush {
                    NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
                } else {
                    dismiss()
                }
            } label: {
                Text(status == "auto_accepted" ? "Open My Loads" : "Done")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(PressableCardStyle())
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
        )
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.warning)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.warning.opacity(0.12))
        )
    }

    // MARK: Rate meter (above-market pill)

    private func rateMeterPill(_ cmp: RatesAPI.LaneComparison) -> some View {
        // Canonical envelope: the server is the SOLE authority on
        // whether the rate is comparable. NEVER show a position/
        // percentile/market band when comparable == false — fall back
        // to the honest reason (zero-fabrication mandate).
        let position = cmp.position ?? ""
        let percentile = cmp.percentile ?? 0
        let (label, color, glyph): (String, Color, String) = {
            guard cmp.comparable else {
                switch cmp.referenceReason {
                case "needs_ws100_flat":
                    return ("ENTER WS-100 FLAT TO BENCHMARK", palette.textTertiary, "info.circle")
                case "unit_unconvertible", "unconvertible":
                    return ("CAN'T BENCHMARK THIS RATE TYPE YET", palette.textTertiary, "questionmark.circle")
                default:
                    return ("REFERENCE ONLY · n=\(cmp.sampleSize)", palette.textTertiary, "chart.bar")
                }
            }
            switch position {
            case "ABOVE_MARKET": return ("ABOVE MARKET · \(percentile)th pct", Brand.success, "arrow.up.right.circle.fill")
            case "BELOW_MARKET": return ("BELOW MARKET · \(percentile)th pct", Brand.danger, "arrow.down.right.circle.fill")
            default:             return ("AT MARKET · \(percentile)th pct",     Brand.warning, "equal.circle.fill")
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(EType.micro.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                // Market band only when the server actually returned one
                // AND the rate is comparable — no $0.00/$0.00 fabrication.
                // Currency-aware glyph + canonical unit so a MX/CA or
                // $/FEU / $/ton-mi lane labels honestly (not a hardcoded
                // '$.../mi').
                if cmp.comparable,
                   let lo = cmp.marketMinRPM, let avg = cmp.marketAvgRPM, let hi = cmp.marketMaxRPM {
                    let pfx = rateMeterCurrencyPrefix(cmp.currency)
                    let unitLabel = (cmp.unit ?? cmp.canonicalUnit)
                        .replacingOccurrences(of: "$/", with: "")
                    Text(String(format: "%@%.2f / %@%.2f / %@%.2f /%@",
                                pfx, lo, pfx, avg, pfx, hi, unitLabel))
                        .font(EType.micro.monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if !cmp.recommendation.isEmpty {
                Text(cmp.recommendation)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !cmp.comparable {
                if cmp.referenceReason == "insufficient_data" || cmp.referenceReason == nil {
                    Text("Reference only · n=\(cmp.sampleSize) comparable loads")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            } else if cmp.source == "national_benchmark" || cmp.source == "national_reference" {
                Text("National benchmark · \(cmp.sampleSize) lane comps")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            } else {
                Text("Platform data · \(cmp.sampleSize) lane comps · last 90d")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            // Honest benchmark provenance label (e.g. 'Baltic BDTI ·
            // reference only · feed not connected'). LABEL ONLY — the
            // verdict pill above is gated on cmp.comparable, so a
            // verdictEligible=false citation never adds a verdict.
            if let citation = cmp.benchmarkCitation, !citation.label.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: citation.connected ? "checkmark.seal" : "info.circle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(citation.label)
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.5))
        )
    }

    /// Currency-aware symbol (CAD→'CA$', MXN→'MX$', else '$') so the
    /// market band on a MX/CA lane labels honestly.
    private func rateMeterCurrencyPrefix(_ c: String) -> String {
        switch c.uppercased() {
        case "CAD": return "CA$"
        case "MXN": return "MX$"
        default:    return "$"
        }
    }

    // MARK: Booking action

    /// Fires `loadBidding.submit` at the posted rate. Drivers can't book
    /// loads directly per `LOAD_BOOKER_ROLES` (CATALYST/BROKER/DISPATCH
    /// only), but they CAN bid — and a bid at the posted rate is the
    /// canonical "Book Now" affordance the web platform uses too. The
    /// shipper either auto-accepts (server returns `status: "auto_accepted"`)
    /// or queues for review (`status: "pending"`). Either way the
    /// driver gets realtime feedback through the `bid:awarded` /
    /// `bid:received` socket events.
    private func book() async {
        guard let backendId = load.backendLoadId else {
            bookState = .error("Load id is missing. Refresh the load board and try again.")
            return
        }
        if isTruckLoad && inheritedTruckDetentionTerms == nil {
            bookState = .error(
                authoritativeLoadError ??
                "Signed truck detention terms are unavailable. Refresh the load before bidding."
            )
            return
        }
        let requestKey = bookRequestKey ?? UUID().uuidString.lowercased()
        bookRequestKey = requestKey
        bookState = .submitting
        do {
            let ack = try await EusoTripAPI.shared.loadBidding.submit(
                loadId: backendId,
                bidAmount: load.rate,
                rateType: "flat",
                equipmentType: load.equipment.lowercased() == "any" ? nil : load.equipment.lowercased(),
                truckDetentionTerms: nil,
                expiresInHours: 24,
                requestKey: requestKey
            )
            guard let confirmedStatus = ack.confirmedStatus else {
                bookState = .error("The bid was not confirmed. The load remains available and no award was recorded.")
                return
            }
            bookRequestKey = nil
            bookState = .booked(bidId: ack.id, status: confirmedStatus)
            // Notify the marketplace store so the load card reflects the
            // new "bid placed" state without waiting for the next refresh.
            NotificationCenter.default.post(
                name: .eusoLoadPosted,
                object: nil,
                userInfo: ["loadId": String(backendId), "bidPlaced": true]
            )
        } catch {
            let ns = error as NSError
            // Surface the server's user-facing message verbatim when
            // tRPC supplied one ("Set up your EusoWallet payout account
            // before bidding…", "Carrier missing CDL-H endorsement…",
            // "You have already submitted a bid…"). Falls back to a
            // generic line for transport-level failures.
            //
            // 2026-06-23: keep 401 and 403 distinct. A 401 sends the
            // user back through real auth; a 403 keeps the server's
            // role/mode/compliance gate visible so we do not claim an
            // account mismatch is a stale session.
            let msg: String = {
                if let api = error as? EusoTripAPIError {
                    switch api {
                    case .unauthenticated:
                        // Route the driver to re-auth through the SAME
                        // app-observed channel every "Sign out" affordance
                        // uses — `eusoLogoutRequested` is picked up at the
                        // app root (EusoTripApp.swift) and calls
                        // `session.signOut()`, which lands them on Sign In.
                        // The prior `eusoSessionRefreshRequested` post had
                        // NO observer anywhere, so an expired-session Book
                        // Now showed this banner and then dead-ended (tester
                        // "I need this load and I can't book"). Now the
                        // banner is backed by a real path back to a booking-
                        // capable session.
                        NotificationCenter.default.post(
                            name: Notification.Name("eusoLogoutRequested"),
                            object: nil
                        )
                        return "Your session expired. Sign in again, then retry this load."
                    case .forbidden(let message):
                        return message
                    case .trpcError(let m):
                        return m
                    case .httpStatus(let code, _):
                        if code == 401 || code == 403 {
                            return "This account isn't allowed to bid on this lane (HTTP \(code))."
                        }
                        return "EusoTrip returned error \(code). Your bid was not confirmed — try again in a moment."
                    case .decodingFailed:
                        return "EusoTrip answered, but the app could not read the reply, so your bid is not confirmed either way. Try again. If it persists, retry from the load board."
                    case .notConfigured:
                        return "API not configured. Try restarting the app."
                    case .badURL:
                        return "Bid URL was malformed. Refresh the load board and try again."
                    case .empty:
                        return "EusoTrip sent back an empty reply, so your bid was not confirmed. Try again."
                    case .queuedForOfflineReplay:
                        return "You're offline — this will be sent automatically when you reconnect."
                    }
                }
                if ns.domain == NSURLErrorDomain { return "Network unavailable. Check your connection and try again." }
                return error.localizedDescription
            }()
            bookState = .error(msg)
        }
    }

    /// SPOT / CONTRACT pill rendered in the load detail header. The
    /// `commercial.agreement.contractDuration` enum returned by
    /// `loads.getCommercialContext` distinguishes:
    ///   • "spot"        — single-load market price (red/magenta tint)
    ///   • "short_term"  — repeat-route allocation
    ///   • "long_term"   — committed lane (green tint)
    ///   • "evergreen"   — ongoing master contract
    /// When the agreement isn't loaded yet (or none exists) we render
    /// nothing — drivers shouldn't see a spinner badge.
    @ViewBuilder
    private var spotContractBadge: some View {
        if let dur = commercial?.agreement?.contractDuration {
            switch dur {
            case "spot":
                EusoBadge(label: "SPOT RATE", kind: .hot,
                          icon: Image(systemName: "bolt.fill"))
            case "short_term":
                badgePill(text: "SHORT TERM", color: Brand.warning)
            case "long_term":
                badgePill(text: "LANE CONTRACT", color: Brand.success)
            case "evergreen":
                badgePill(text: "EVERGREEN", color: LinearGradient.diagonal)
            default:
                badgePill(text: dur.uppercased(), color: palette.textTertiary)
            }
        }
    }

    private func badgePill<S: ShapeStyle>(text: String, color: S) -> some View {
        Text(text)
            .font(EType.micro.weight(.heavy))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    // MARK: Section wrapper

    @ViewBuilder
    private func sectionCard<Content: View>(title: String,
                                            subtitle: String?,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                if let subtitle {
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            content()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    @ViewBuilder
    private func kvRow(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Hero matched-geometry helper

/// Optional matchedGeometryEffect applier — no-op when the sheet
/// caller didn't thread a Namespace, otherwise tags the view as
/// the destination anchor for a §3.1 zoom transition from a load
/// card source. Mirrors `OptionalMatchedGeometry` in DriverTabPanes.
private struct LoadDetailHeroMatch: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - Counter-Offer Sheet
//
// Drivers tap "Bid a different rate" → this sheet opens with the
// posted rate pre-filled. They edit the amount, optionally attach
// conditions ("if pickup before 14:00", "+ $200 detention waiver"),
// and submit. Backed by `loadBidding.submit` — server inserts a
// loadBids row with bidderRole='driver', runs the auto-accept rules,
// and fans an event so the catalyst sees it on their bid board within
// seconds.
//
// $/mi delta vs the posted spot rate is shown live so the driver
// can negotiate at the right magnitude rather than free-typing
// against a number that means nothing without context.

struct CounterOfferSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let loadId: String
    /// Backend numeric id, required to open a bid chain. Every live
    /// row from `loads.search` supplies it. The sheet posts to
    /// `loadBidding.submit` (the canonical web-platform endpoint),
    /// which is keyed on this numeric id. When nil, `submit()` fails
    /// fast with a refresh-the-load-board message rather than firing a
    /// doomed mutation — symmetric with `book()`.
    let backendLoadId: Int?
    let postedRate: Double
    let miles: Int
    /// Lane market average $/mi from `rates.compareLaneRate`. When
    /// supplied, the sheet renders the live $/mi delta against the
    /// market average too — driver sees both "vs posted" AND "vs
    /// market" so they can negotiate at the right magnitude.
    let marketAvgRPM: Double?
    /// Currency comes from the authoritative load row. Nil remains unlabeled;
    /// this sheet never converts an unknown currency into USD.
    let currency: String?
    let transportMode: String?
    let inheritedTruckDetentionTerms: TruckDetentionNegotiatedTerms?
    var onSubmitted: () -> Void = {}

    @State private var amount: Double
    @State private var conditions: String = ""
    @State private var overrideDetentionTerms: Bool
    @State private var detentionTermsDraft: TruckDetentionTermsDraft
    @State private var isSubmitting: Bool = false
    @State private var lastError: String?
    @State private var ack: SubmitOutcome?
    @State private var requestKey: String?

    enum SubmitOutcome: Equatable {
        case bidding(id: Int?, status: String)   // loadBidding.submit
    }

    init(loadId: String,
         backendLoadId: Int? = nil,
         postedRate: Double,
         miles: Int,
         marketAvgRPM: Double? = nil,
         currency: String? = nil,
         transportMode: String? = nil,
         inheritedTruckDetentionTerms: TruckDetentionNegotiatedTerms? = nil,
         onSubmitted: @escaping () -> Void = {}) {
        self.loadId = loadId
        self.backendLoadId = backendLoadId
        self.postedRate = postedRate
        self.miles = miles
        self.marketAvgRPM = marketAvgRPM
        self.currency = currency
        self.transportMode = transportMode
        self.inheritedTruckDetentionTerms = inheritedTruckDetentionTerms
        self.onSubmitted = onSubmitted
        // Begin from the signed posted amount. Any premium is an explicit
        // user action through the percentage controls below.
        _amount = State(initialValue: postedRate)
        _overrideDetentionTerms = State(
            initialValue: transportMode?.lowercased() == "truck" && inheritedTruckDetentionTerms == nil
        )
        _detentionTermsDraft = State(
            initialValue: inheritedTruckDetentionTerms.map(TruckDetentionTermsDraft.init(terms:)) ??
                TruckDetentionTermsDraft()
        )
    }

    private var isTruckLoad: Bool { transportMode?.lowercased() == "truck" }

    private var selectedCurrency: String? {
        if overrideDetentionTerms, let selected = detentionTermsDraft.currency?.rawValue {
            return selected
        }
        return inheritedTruckDetentionTerms?.currency.rawValue ?? currency
    }

    private var detentionTermsReady: Bool {
        guard isTruckLoad else { return true }
        if overrideDetentionTerms { return detentionTermsDraft.negotiatedTerms != nil }
        return inheritedTruckDetentionTerms != nil
    }

    private func money(_ amount: Double, fractionDigits: Int = 0) -> String {
        let number = amount.formatted(
            .number.precision(.fractionLength(fractionDigits))
        )
        return selectedCurrency.map { "\($0) \(number)" } ?? number
    }

    private var deltaPerMile: Double {
        guard miles > 0 else { return 0 }
        return (amount - postedRate) / Double(miles)
    }

    /// $/mi vs market average — only meaningful when the caller
    /// provided `marketAvgRPM`. nil = no market comparison rendered.
    private var deltaVsMarketPerMile: Double? {
        guard let mkt = marketAvgRPM, miles > 0 else { return nil }
        return (amount / Double(miles)) - mkt
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackChevron { dismiss() }
                Spacer()
                Text("Counter-offer")
                    .font(EType.bodyStrong)
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if ack != nil {
                        ackView
                    } else {
                        formView
                    }
                    Color.clear.frame(height: Space.s8)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s2)
            }
            if ack == nil {
                CTAButton(title: isSubmitting ? "Sending…" : "Send counter-offer") {
                    Task { await submit() }
                }
                .opacity(isSubmitting ? 0.6 : 1)
                .disabled(isSubmitting || amount <= 0 || !detentionTermsReady)
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s5)
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
    }

    @ViewBuilder
    private var formView: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("POSTED RATE")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(money(postedRate))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                if miles > 0 {
                    Text("\(miles) mi · \(money(postedRate / Double(miles), fractionDigits: 2))/mi posted")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("YOUR COUNTER")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack {
                    if let selectedCurrency {
                        Text(selectedCurrency)
                            .font(EType.caption.weight(.bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    TextField("Counter amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
                if miles > 0 {
                    Text(
                        "\(money(amount / Double(miles), fractionDigits: 2))/mi · " +
                        "\(deltaPerMile >= 0 ? "+" : "")\(money(deltaPerMile, fractionDigits: 2))/mi vs posted"
                    )
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(deltaPerMile >= 0 ? Brand.success : Brand.danger)
                }
                if let dvsm = deltaVsMarketPerMile {
                    Text(
                        "\(dvsm >= 0 ? "+" : "")\(money(dvsm, fractionDigits: 2))/mi vs market avg"
                    )
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(dvsm >= 0 ? Brand.success : Brand.warning)
                }
                HStack {
                    quickBumpButton(label: "+5%",  factor: 1.05)
                    quickBumpButton(label: "+10%", factor: 1.10)
                    quickBumpButton(label: "+15%", factor: 1.15)
                }
            }
        }
        if isTruckLoad {
            ActiveCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("TRUCK DETENTION")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)

                    if let inheritedTruckDetentionTerms {
                        TruckDetentionTermsSummary(
                            terms: inheritedTruckDetentionTerms,
                            context: "INHERITED FROM SIGNED LOAD"
                        )
                        Toggle("Propose different detention terms", isOn: $overrideDetentionTerms)
                            .tint(Brand.blue)
                            .frame(minHeight: 44)
                    } else {
                        Label(
                            "No signed detention terms were returned for this truck load. Enter a complete proposal before bidding.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if overrideDetentionTerms {
                        TruckDetentionTermsEditor(draft: $detentionTermsDraft)
                    } else {
                        Text("This bid inherits the signed load terms without changing them.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CONDITIONS (optional)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. \"pickup before 14:00\"",
                          text: $conditions, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        if let err = lastError {
            Text(err)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
        }
    }

    @ViewBuilder
    private var ackView: some View {
        let statusLabel: String = {
            switch ack {
            case .bidding(_, let s): return s.capitalized
            case .none:              return "Pending"
            }
        }()
        let isAutoAccepted: Bool = {
            if case .bidding(_, let s) = ack, s == "auto_accepted" { return true }
            return false
        }()
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Image(systemName: isAutoAccepted ? "checkmark.seal.fill" : "paperplane.fill")
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(isAutoAccepted ? "Bid auto-accepted" : "Counter-offer sent")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                }
                Text("\(money(amount)) · \(statusLabel)")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Text(isAutoAccepted
                     ? "Your bid matched a shipper auto-accept rule. The load is yours. Head to My Loads to start the trip."
                     : "The shipper sees your counter on their bid board. You'll get a realtime push once they accept, reject or counter back.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        CTAButton(title: isAutoAccepted ? "Open My Loads" : "Done") {
            onSubmitted()
            dismiss()
        }
    }

    private func quickBumpButton(label: String, factor: Double) -> some View {
        Button {
            amount = round(postedRate * factor)
        } label: {
            Text(label)
                .font(EType.caption.weight(.semibold))
                .padding(.horizontal, Space.s3).padding(.vertical, 6)
                .background(Capsule().fill(palette.bgCardSoft))
                .overlay(Capsule().stroke(palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    private func submit() async {
        guard !isSubmitting else { return }
        guard let backendId = backendLoadId else {
            lastError = "Load id is missing. Refresh the load board and try again."
            return
        }
        let detentionTerms: TruckDetentionNegotiatedTerms?
        if isTruckLoad && overrideDetentionTerms {
            guard let terms = detentionTermsDraft.negotiatedTerms else {
                lastError = detentionTermsDraft.validationMessage ?? "Complete the proposed detention terms."
                return
            }
            detentionTerms = terms
        } else if isTruckLoad && inheritedTruckDetentionTerms == nil {
            lastError = "Signed truck detention terms are unavailable. Enter a complete proposal before bidding."
            return
        } else {
            // Nil is the server contract's explicit inheritance instruction.
            detentionTerms = nil
        }
        let idempotencyKey = requestKey ?? UUID().uuidString.lowercased()
        requestKey = idempotencyKey
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let resp = try await EusoTripAPI.shared.loadBidding.submit(
                loadId: backendId,
                bidAmount: amount,
                rateType: "flat",
                conditions: conditions.isEmpty ? nil : conditions,
                truckDetentionTerms: detentionTerms,
                expiresInHours: 24,
                requestKey: idempotencyKey
            )
            guard let confirmedStatus = resp.confirmedStatus else {
                lastError = "This bid was not confirmed. No counter-offer is shown as sent."
                return
            }
            requestKey = nil
            ack = .bidding(id: resp.id, status: confirmedStatus)
            lastError = nil
        } catch {
            // Honest, diagnosable message for EVERY failure class — not just
            // tRPC. `bidActionMessage` surfaces the real reason: the verbatim
            // tRPC copy (wallet/CDL/dup-bid/mode-eligibility), an auth line,
            // a network line, or a decode line. Mirrors the `book()` fix at
            // this file's booking action. 403/FORBIDDEN no longer reaches
            // this branch as `.unauthenticated` — `perform()` keeps it
            // distinct so permission gates surface their own message.
            if let api = error as? EusoTripAPIError, case .unauthenticated = api {
                // Give the driver a real path back to a bid-capable session —
                // the same channel every "Sign out" affordance uses
                // (`eusoLogoutRequested` is observed at the app root and lands
                // them on Sign In). Without this a genuine session expiry
                // showed a banner and then dead-ended.
                NotificationCenter.default.post(
                    name: Notification.Name("eusoLogoutRequested"),
                    object: nil
                )
            }
            lastError = EusoTripAPIError.bidActionMessage(for: error, noun: "counter")
        }
    }
}
