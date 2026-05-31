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

    // MARK: - Environment

    @Environment(\.palette)     private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss)     private var dismiss

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

    enum BookState: Equatable {
        case idle
        case submitting
        case booked(bidId: Int?, status: String)
        case error(String)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                routeCard
                rateRow
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
                    topic: "Equipment compliance (Mar 23, 2026)"
                )
                if let f = feePreview {
                    feeBreakdownCard(f)
                }
                escortCard
                brokerCard
                actionButtons
                Color.clear.frame(height: Space.s5)
            }
            .padding(Space.s5)
        }
        .scrollIndicators(.hidden)
        .background(palette.bgSheet.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            // Canonical close X. Replaces the bespoke inline button
            // so this sheet shares the same hit-target geometry +
            // press animation as every other sheet in the app per
            // the 2026 UX motion doc.
            SheetCloseButton { dismiss() }
                .padding(Space.s4)
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
            // Escort context — separate task so a slow / failing escort
            // call doesn't block the broker card from rendering. The
            // escort card collapses to its "loading" state when the
            // optional `escorts` is still nil; on error we fall through
            // to the same `[]` empty case (silent fail beats a red
            // toast on a fast-moving sheet).
            do {
                escorts = try await EusoTripAPI.shared.loads
                    .getEscortAssignment(loadId: load.id)
            } catch {
                escorts = []
            }
        }
        .task(id: load.id) {
            // Adaptive fee preview — `adaptiveFee.estimate` is cheap
            // (no DB write, no audit log) so we call it on every
            // sheet open. Maps the load's hazmat flag + equipment
            // string + miles into the playbook's enum domain.
            let isHaz = load.hazmat
            let equip = mapEquipmentForFee(load.equipment)
            let vert  = isHaz ? "hazmat" : mapVerticalForFee(load.equipment)
            do {
                feePreview = try await EusoTripAPI.shared.adaptiveFee.estimate(
                    loadRate: load.rate,
                    vertical: vert,
                    equipmentType: equip,
                    hazmatClass: isHaz ? "class_3" : "none",
                    distanceMiles: Double(load.miles),
                    loadType: commercial?.agreement?.contractDuration ?? "spot"
                )
            } catch {
                feePreview = nil
            }
        }
        .task(id: load.id) {
            // Lane benchmark from `rates.compareLaneRate` — drives the
            // ABOVE_MARKET / AT_MARKET / BELOW_MARKET pill above the
            // book/bid buttons. Skip the call when the AvailableLoad
            // adapter couldn't extract origin/dest state codes (rare —
            // mostly preview rows) so we don't send a malformed query.
            guard let oSt = load.originState,
                  let dSt = load.destState,
                  load.miles > 0 else {
                comparison = nil
                return
            }
            do {
                comparison = try await EusoTripAPI.shared.rates.compareLaneRate(
                    originState: oSt,
                    destState: dSt,
                    rate: load.rate,
                    distance: Double(load.miles),
                    cargoType: load.equipment.lowercased(),
                    lookbackDays: 90
                )
                comparisonError = false
            } catch {
                comparison = nil
                comparisonError = true
            }
        }
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
        // Hero id used by §3.1 matchedGeometryEffect. Falls back to
        // the load's own id when the caller didn't pass an explicit
        // source id.
        let heroId = heroSourceId ?? load.id
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Text(load.id.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-id", namespace: heroNamespace))
                spotContractBadge
                if load.hotScore >= 4 {
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
                Text(load.origin)
                    .font(EType.h1).foregroundStyle(LinearGradient.diagonal)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-origin", namespace: heroNamespace))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(load.destination)
                    .font(EType.h1).foregroundStyle(LinearGradient.diagonal)
                    .modifier(LoadDetailHeroMatch(id: "load-\(heroId)-dest", namespace: heroNamespace))
            }
            .lineLimit(2)

            Text("\(load.miles) mi · \(load.equipment.uppercased()) · \(load.weight.uppercased())")
                .font(EType.caption).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Route card

    private var routeCard: some View {
        let lane = HereMapView.Lane(
            id: load.id,
            originTitle: load.origin,
            destinationTitle: load.destination,
            pickup:   CLLocationCoordinate2D(latitude: load.originLat,
                                             longitude: load.originLng),
            delivery: CLLocationCoordinate2D(latitude: load.destLat,
                                             longitude: load.destLng)
        )
        return sectionCard(title: "ROUTE",
                           subtitle: "\(load.miles) mi · estimated \(estimatedDriveTime)") {
            ZStack(alignment: .bottomLeading) {
                // 2026-05-22: migrated off the legacy raster HereMapView onto
                // the OMV vector renderer + live add-on layer (HereLiveMapView),
                // matching the 205_ShipperLoadDetail hero map. Pickup/delivery
                // pins + route connector on the vector basemap; shipper
                // situational add-ons (weather + traffic + sponsored ad-zones).
                HereLiveMapView(
                    center: .init(
                        (lane.pickup.latitude + lane.delivery.latitude) / 2,
                        (lane.pickup.longitude + lane.delivery.longitude) / 2
                    ),
                    zoom: 6,
                    route: [.init(lane.pickup), .init(lane.delivery)],
                    baseLayers: [
                        .route(
                            polyline: [.init(lane.pickup), .init(lane.delivery)],
                            colorHex: "#1473FF"
                        ),
                        .markers([
                            .init(at: .init(lane.pickup), kind: .pickup, label: lane.originTitle),
                            .init(at: .init(lane.delivery), kind: .delivery, label: lane.destinationTitle)
                        ])
                    ],
                    addOns: .shipperTracking
                )
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md,
                                                style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md,
                                         style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                pickupDeliveryStops
                    .padding(10)
            }
        }
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
                Text("DELIVERY · ETA \(estimatedDeliveryDay)")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(Capsule(style: .continuous).fill(.black.opacity(0.55)))
    }

    private var estimatedDriveTime: String {
        // Rough heuristic: highway avg 52 mph.
        let hours = Double(load.miles) / 52.0
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private var estimatedDeliveryDay: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · HH:mm 'CT'"
        return f.string(from: Date().addingTimeInterval(Double(load.miles) * 70))
    }

    // MARK: Rate row

    private var rateRow: some View {
        HStack(spacing: Space.s3) {
            ratePill(value: "$\(Int(load.rate))",
                     label: "TOTAL",
                     gradient: true)
            ratePill(value: String(format: "$%.2f", load.rpm),
                     label: "PER MILE",
                     gradient: false)
            ratePill(value: "\(load.miles) mi",
                     label: "DISTANCE",
                     gradient: false)
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
                                   subtitle: "Gross >46,000 lb — carrier must carry permit",
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
                prohibitedRow(icon: "road.lanes.curved.left",
                              text: "No commercial tunnels carrying Class 3 hazmat (Lincoln Tunnel, Holland Tunnel).")
                    .opacity(load.hazmat ? 1 : 0.5)
                prohibitedRow(icon: "building.2.fill",
                              text: "No downtown truck routes between 07:00–09:30 and 16:00–18:30 local.")
                prohibitedRow(icon: "arrow.up.arrow.down",
                              text: "Bridges with posted weight <46,000 lb — alternate via I-highways only.")
                if load.equipment == "Flatbed" || load.equipment == "Step Deck" {
                    prohibitedRow(icon: "exclamationmark.triangle",
                                  text: "Oversized load: follow state DOT permit routing only. No county or city bypass.")
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
                HStack(spacing: Space.s2) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("No escort assigned")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Request one from dispatch if this lane needs a lead or chase car.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
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
                    #if canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
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
        let posLabel: String
        switch r.position {
        case "lead":  posLabel = "Lead"
        case "chase": posLabel = "Chase"
        case "both":  posLabel = "Lead + Chase"
        default:      posLabel = r.position.capitalized
        }
        if let name = r.companyName, !name.isEmpty { return "\(posLabel) · \(name)" }
        if let name = r.escortName,  !name.isEmpty { return "\(posLabel) · \(name)" }
        return posLabel
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
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
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

                Button {
                    handleMessageTap()
                } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(LinearGradient.diagonal)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Message counterparty")
            }
        }
    }

    /// Message button never goes dead. Three cases:
    ///   1. Caller passed `onMessageBroker` — invoke it (legacy path
    ///      where the surface owns its own threading).
    ///   2. We have a real broker (`commercial.broker`) — open the
    ///      messaging thread with that company via the canonical
    ///      `eusoMessagingThreadOpen` notification, which both the
    ///      shipper and driver surfaces already route to
    ///      `MessagesScreen` with the thread pre-selected.
    ///   3. Otherwise (shipper-direct, or commercial still loading) —
    ///      fall through to ESANG so the user can ask "who's the
    ///      shipper on LD-…?" and the assistant routes them, instead
    ///      of staring at a dead button.
    /// Founder report 2026-05-06 — the message button was wired to
    /// `onMessageBroker?()` which is `nil` whenever the LoadDetailSheet
    /// is presented from a surface that doesn't pass the closure.
    private func handleMessageTap() {
        if let onMessageBroker {
            onMessageBroker()
            return
        }
        // Server resolves whoever posted the load — broker, shipper,
        // dispatch, driver — into a single `counterparty` field on
        // CommercialContext. We route to that user regardless of
        // role, so the Message button works whether the load was
        // posted by a brokerage, a shipper directly, a dispatcher
        // on a fleet's behalf, or an owner-operator. Founder
        // mandate 2026-05-06 — "whether its a broker or just
        // shipper or its dispatch it needs to work when contacting
        // whoever posts a load."
        if let cp = commercial?.counterparty {
            NotificationCenter.default.post(
                name: Notification.Name("eusoMessagingThreadOpen"),
                object: nil,
                userInfo: [
                    "userId":      cp.userId,
                    "companyId":   cp.companyId as Any,
                    "displayName": cp.companyName ?? cp.userName ?? cp.role.capitalized,
                    "role":        cp.role,
                    "loadId":      load.backendLoadId.map(String.init) ?? load.id,
                ]
            )
            return
        }
        // Legacy broker fallback — kept for the brief window when
        // a build hits the new client but old server (which doesn't
        // return `counterparty`).
        if let broker = commercial?.broker {
            NotificationCenter.default.post(
                name: Notification.Name("eusoMessagingThreadOpen"),
                object: nil,
                userInfo: [
                    "userId":      broker.userId,
                    "companyId":   broker.companyId as Any,
                    "displayName": broker.companyName ?? broker.userName ?? "Broker",
                    "role":        "BROKER",
                    "loadId":      load.backendLoadId.map(String.init) ?? load.id,
                ]
            )
            return
        }
        // Commercial context still loading — drop the user into
        // ESANG with the load id pre-loaded so they can ask "who
        // do I message about this load?" without typing it.
        NotificationCenter.default.post(
            name: Notification.Name("eusoeSangOpenWithLoadContext"),
            object: nil,
            userInfo: [
                "loadId": load.backendLoadId.map(String.init) ?? load.id,
                "intent": "message_counterparty",
            ]
        )
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
            return "—"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var brokerPrimaryLine: String {
        if let bn = commercial?.broker?.companyName, !bn.isEmpty { return bn }
        if commercial?.broker == nil, commercial != nil {
            // Confirmed shipper-direct — fall back to whatever name the
            // load card already had so the card isn't blank.
            return load.broker.isEmpty ? "—" : load.broker
        }
        return load.broker.isEmpty ? "—" : load.broker
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
                miles: load.miles,
                marketAvgRPM: comparison?.marketAvgRPM,
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
            Text("Book now · $\(Int(load.rate))")
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
                 ? "Your bid matched a shipper auto-accept rule. The load is yours — head to My Loads to start the trip."
                 : "Your bid is in the chain. You'll get a realtime push the moment the shipper accepts, counters, or assigns to another carrier.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onBook?()
                dismiss()
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
        let (label, color, glyph): (String, Color, String) = {
            switch cmp.position {
            case "ABOVE_MARKET": return ("ABOVE MARKET · \(cmp.percentile)th pct", Brand.success, "arrow.up.right.circle.fill")
            case "BELOW_MARKET": return ("BELOW MARKET · \(cmp.percentile)th pct", Brand.danger, "arrow.down.right.circle.fill")
            default:             return ("AT MARKET · \(cmp.percentile)th pct",     Brand.warning, "equal.circle.fill")
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
                Text(String(format: "$%.2f / $%.2f / $%.2f /mi",
                            cmp.marketMinRPM, cmp.marketAvgRPM, cmp.marketMaxRPM))
                    .font(EType.micro.monospacedDigit())
                    .foregroundStyle(palette.textTertiary)
            }
            Text(cmp.recommendation)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if cmp.source == "national_benchmark" {
                Text("National benchmark · \(cmp.sampleSize) lane comps")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            } else {
                Text("Platform data · \(cmp.sampleSize) lane comps · last 90d")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
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
            bookState = .error("Load id is missing — refresh the load board and try again.")
            return
        }
        bookState = .submitting
        do {
            let ack = try await EusoTripAPI.shared.loadBidding.submit(
                loadId: backendId,
                bidAmount: load.rate,
                rateType: "flat",
                equipmentType: load.equipment.lowercased() == "any" ? nil : load.equipment.lowercased(),
                expiresInHours: 24
            )
            bookState = .booked(bidId: ack.id, status: ack.status)
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
            // 2026-05-05: explicit handling for `.unauthenticated` was
            // missing — server 401/403 surfaced as the cryptic
            // `EusoTripAPIError error 0` from `localizedDescription`,
            // which is what the founder hit on Book Now ("does nothing
            // says something about authentication"). Now we emit a
            // direct human line and post a session-refresh notification
            // so the surface can prompt re-auth without dead-ending.
            let msg: String = {
                if let api = error as? EusoTripAPIError {
                    switch api {
                    case .unauthenticated:
                        NotificationCenter.default.post(
                            name: Notification.Name("eusoSessionRefreshRequested"),
                            object: nil
                        )
                        return "Your session expired or this account isn't allowed to bid on this lane. Sign in again or switch to a carrier / dispatcher account."
                    case .trpcError(let m):
                        return m
                    case .httpStatus(let code, _):
                        if code == 401 || code == 403 {
                            return "This account isn't allowed to bid on this lane (HTTP \(code))."
                        }
                        return "Server error \(code). Try again in a moment."
                    case .decodingFailed:
                        return "We couldn't read the server's response. Try again — if it persists, retry from the load board."
                    case .notConfigured:
                        return "API not configured. Try restarting the app."
                    case .badURL:
                        return "Bid URL was malformed. Refresh the load board and try again."
                    case .empty:
                        return "Server returned an empty response. Try again."
                    }
                }
                if ns.domain == NSURLErrorDomain { return "Network unavailable — check your connection and try again." }
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
// and submit. Backed by `drivers.counterOffer` — server inserts a
// loadBids row with bidderRole='driver', status='countered', and
// fans an event so the catalyst sees it on their bid board within
// seconds.
//
// $/mi delta vs the posted spot rate is shown live so the driver
// can negotiate at the right magnitude rather than free-typing
// against a number that means nothing without context.

struct CounterOfferSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let loadId: String
    /// Backend numeric id when the caller has it (every live row
    /// from `loads.search` does). When present, the sheet posts to
    /// `loadBidding.submit` (the canonical web-platform endpoint);
    /// when nil, falls back to the legacy `drivers.counterOffer`
    /// path which only needs the loadNumber string.
    let backendLoadId: Int?
    let postedRate: Double
    let miles: Int
    /// Lane market average $/mi from `rates.compareLaneRate`. When
    /// supplied, the sheet renders the live $/mi delta against the
    /// market average too — driver sees both "vs posted" AND "vs
    /// market" so they can negotiate at the right magnitude.
    let marketAvgRPM: Double?
    var onSubmitted: () -> Void = {}

    @State private var amount: Double
    @State private var conditions: String = ""
    @State private var isSubmitting: Bool = false
    @State private var lastError: String?
    @State private var ack: SubmitOutcome?

    enum SubmitOutcome: Equatable {
        case bidding(id: Int?, status: String)   // loadBidding.submit
        case legacy(status: String)              // drivers.counterOffer
    }

    init(loadId: String,
         backendLoadId: Int? = nil,
         postedRate: Double,
         miles: Int,
         marketAvgRPM: Double? = nil,
         onSubmitted: @escaping () -> Void = {}) {
        self.loadId = loadId
        self.backendLoadId = backendLoadId
        self.postedRate = postedRate
        self.miles = miles
        self.marketAvgRPM = marketAvgRPM
        self.onSubmitted = onSubmitted
        // Seed with posted rate + 5% — the typical driver counter
        // when the broker's posted rate is just-below-market.
        _amount = State(initialValue: round(postedRate * 1.05))
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
                .disabled(isSubmitting || amount <= 0)
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
                Text(String(format: "$%.0f", postedRate))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                if miles > 0 {
                    Text(String(format: "%d mi · $%.2f/mi posted", miles, postedRate / Double(miles)))
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
                    Text("$")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    TextField("Counter amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
                if miles > 0 {
                    Text(String(format: "$%.2f/mi · %@$%.2f/mi vs posted",
                                amount / Double(miles),
                                deltaPerMile >= 0 ? "+" : "",
                                deltaPerMile))
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(deltaPerMile >= 0 ? Brand.success : Brand.danger)
                }
                if let dvsm = deltaVsMarketPerMile {
                    Text(String(format: "%@$%.2f/mi vs market avg",
                                dvsm >= 0 ? "+" : "",
                                dvsm))
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
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CONDITIONS (optional)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. \"+ $200 detention waiver\", \"pickup before 14:00\"",
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
            case .legacy(let s):     return s.capitalized
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
                Text(String(format: "$%.0f · %@", amount, statusLabel))
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                Text(isAutoAccepted
                     ? "Your bid matched a shipper auto-accept rule. The load is yours — head to My Loads to start the trip."
                     : "The shipper sees your counter on their bid board. You'll get a realtime push once they accept, reject, or counter back.")
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
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            // Prefer `loadBidding.submit` — same endpoint the web
            // platform's bid management page uses, fans realtime
            // events to the shipper, runs auto-accept rules, and
            // returns whether the bid was instantly accepted.
            if let backendId = backendLoadId {
                let resp = try await EusoTripAPI.shared.loadBidding.submit(
                    loadId: backendId,
                    bidAmount: amount,
                    rateType: "flat",
                    conditions: conditions.isEmpty ? nil : conditions,
                    expiresInHours: 24
                )
                ack = .bidding(id: resp.id, status: resp.status)
            } else {
                // Legacy path — `drivers.counterOffer` accepts the
                // loadNumber string. Used when the caller didn't
                // surface the numeric loadId (older preview rows).
                let resp = try await EusoTripAPI.shared.drivers.counterOffer(
                    loadId: loadId,
                    amount: amount,
                    conditions: conditions.isEmpty ? nil : conditions
                )
                ack = .legacy(status: resp.status)
            }
            lastError = nil
        } catch {
            // Surface tRPC user-facing messages verbatim — common
            // ones include the EusoWallet payout-account precondition,
            // duplicate-bid 409, and CDL/hazmat endorsement gates.
            if let api = error as? EusoTripAPIError, case .trpcError(let m) = api {
                lastError = m
            } else {
                lastError = "Couldn't send counter — try again."
            }
        }
    }
}
