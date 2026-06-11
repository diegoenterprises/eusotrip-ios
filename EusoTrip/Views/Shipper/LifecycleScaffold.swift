//
//  LifecycleScaffold.swift
//  EusoTrip — Shipper · Round 4 / Arc E shared lifecycle scaffold.
//
//  Every 260–279 lifecycle brick consumes
//  `shippers.getLifecycleSnapshot(loadId)` through this scaffold so the
//  20 surfaces share one snapshot store, one RemoteState machine, one
//  header recipe, and one bottom-nav slot wiring. Per-stage content is
//  injected via a `body:` closure that receives the live snapshot.
//
//  Doctrine:
//    • No fabricated runtime data — every field surfaces from the
//      server. Missing rows render em-dash sentinels via `dashIfEmpty`.
//    • Shipper bottom nav: Home · Loads · [eSang] · Bids · Me. Lifecycle
//      screens drilled from Loads keep Loads `isCurrent: true`.
//    • Live updates: socket subscription on
//      `LOAD_STATUS_CHANGED`/`LOAD_GEOFENCE_ENTER`/`LOAD_BOL_SIGNED`/
//      `LOAD_POD_SUBMITTED` refresh the snapshot.
//

import SwiftUI

// MARK: - Em-dash sentinels (no fabricated values per Cohort B doctrine)

@inlinable
func dashIfEmpty(_ s: String?) -> String { (s?.isEmpty == false ? s! : "-") }

@inlinable
func dashIfNil<T: Numeric>(_ n: T?) -> String {
    guard let v = n else { return "-" }
    return "\(v)"
}

@inlinable
func usd(_ amount: Double?) -> String {
    guard let v = amount, v > 0 else { return "-" }
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

@inlinable
func usd0(_ amount: Double?) -> String {
    guard let v = amount, v > 0 else { return "-" }
    return "$\(Int(v))"
}

@inlinable
func humanISO(_ iso: String?, format: String = "MMM d · HH:mm") -> String {
    guard let iso = iso, !iso.isEmpty else { return "-" }
    let isoFmt = ISO8601DateFormatter()
    isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFmt.date(from: iso)
    if date == nil {
        isoFmt.formatOptions = [.withInternetDateTime]
        date = isoFmt.date(from: iso)
    }
    guard let d = date else { return iso }
    let fmt = DateFormatter()
    fmt.dateFormat = format
    return fmt.string(from: d)
}

@inlinable
func relativeETA(from iso: String?) -> String {
    guard let iso = iso, !iso.isEmpty else { return "-" }
    let isoFmt = ISO8601DateFormatter()
    isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFmt.date(from: iso)
    if date == nil {
        isoFmt.formatOptions = [.withInternetDateTime]
        date = isoFmt.date(from: iso)
    }
    guard let d = date else { return iso }
    let secs = d.timeIntervalSinceNow
    if secs <= 0 { return "now" }
    let m = Int(secs / 60); let h = m / 60; let mm = m % 60
    if h == 0 { return "\(m) min" }
    return "\(h)h \(mm)m"
}

// `@inlinable` removed — body references `internal` types
// (`ShipperAPI.LifecycleSnapshot` and the `pickup`/`delivery`/`city`/
// `state` properties on it), and `@inlinable` requires every referenced
// symbol to be `@usableFromInline` or public. Marking the API-mirror
// surface public would force every other call site to track it; the
// hot path here is one-off lifecycle header rendering, so dropping the
// inline hint is the right trade.
func laneDisplay(_ snap: ShipperAPI.LifecycleSnapshot) -> String {
    let p = snap.pickup
    let d = snap.delivery
    let from = [p?.city, p?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    let to   = [d?.city, d?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    if from.isEmpty && to.isEmpty { return "-" }
    if from.isEmpty { return "- → \(to)" }
    if to.isEmpty { return "\(from) → -" }
    return "\(from) → \(to)"
}

func resolveProduct(_ snap: ShipperAPI.LifecycleSnapshot, role: String?) -> TripProduct {
    TripProduct.resolveDirect(
        cargoType: snap.load.cargoType,
        hazmatClass: snap.load.hazmatClass,
        vertical: TripVertical(role: role)
    )
}

// MARK: - Shipper bottom nav (canonical 5-slot doctrine)
//
// Matches the canonical bottom-nav contract in `ShipperScreenWrap`:
// Home / Create Load / [ESANG orb] / Loads / Me. The previous version
// painted Home / Loads / Bids / Me — wrong (no Create Load, no ESANG
// orb, "Bids" is not a real shipper tab) — and slot taps fell through
// to no-op or web continuation because `ShipperNavRoute.map` has no
// "bids" entry. Founder reported 2026-05-04 that leaf screens reached
// from Me had dead nav slots.
//
// Detail screens reachable from any tab pass `currentSlot: .none`
// (no pill highlighted) — same convention used by every screen
// registered through `wrapShipperScreen(currentSlot: .none) { ... }`.

func shipperLifecycleNav(currentSlot: ShipperBottomNavSlot = .none) -> BottomNav {
    BottomNav(
        leading: [
            NavSlot(label: "Home",
                    systemImage: "house.fill",
                    isCurrent: currentSlot == .home),
            NavSlot(label: "Create Load",
                    systemImage: "plus.rectangle.on.rectangle",
                    isCurrent: currentSlot == .createLoad),
        ],
        trailing: [
            NavSlot(label: "Loads",
                    systemImage: "shippingbox.fill",
                    isCurrent: currentSlot == .loads),
            NavSlot(label: "Me",
                    systemImage: "person.fill",
                    isCurrent: currentSlot == .me),
        ],
        orbState: .idle
    )
}

// MARK: - Section header + helpers (used by every lifecycle screen)

struct LifecycleSection: View {
    @Environment(\.palette) private var palette
    let label: String
    let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }
}

struct LifecycleRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
        }
    }
}

struct LifecycleStatTile: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let icon: String
    var danger: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            Text(value).font(.system(size: 15, weight: .heavy)).foregroundStyle(danger ? Brand.danger : palette.textPrimary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(danger ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

struct LifecycleCard<Content: View>: View {
    @Environment(\.palette) private var palette
    let content: Content
    var accentDanger: Bool = false
    var accentWarning: Bool = false
    var accentGradient: Bool = false
    init(accentDanger: Bool = false, accentWarning: Bool = false, accentGradient: Bool = false, @ViewBuilder content: () -> Content) {
        self.accentDanger = accentDanger
        self.accentWarning = accentWarning
        self.accentGradient = accentGradient
        self.content = content()
    }
    var body: some View {
        let strokeStyle: AnyShapeStyle = {
            if accentDanger { return AnyShapeStyle(Brand.danger.opacity(0.55)) }
            if accentWarning { return AnyShapeStyle(Brand.warning.opacity(0.55)) }
            if accentGradient {
                return AnyShapeStyle(LinearGradient(colors: [Brand.blue.opacity(0.7), Brand.magenta.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            return AnyShapeStyle(palette.borderFaint)
        }()
        return VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(strokeStyle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Lifecycle scaffold view

struct LifecycleScaffold<Body: View>: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String
    /// Eyebrow chip text. e.g. "SHIPPER · POSTED · STAGE 1 OF 8".
    let eyebrow: String
    /// Stage value passed to ShipperLoadCycleView. Use the canonical
    /// loads.status enum string ("posted", "bidding", "in_transit", …).
    let cycleStatus: String
    /// Per-stage body content — receives the live snapshot.
    let bodyContent: (ShipperAPI.LifecycleSnapshot) -> Body

    @StateObject private var snap = ShipperLifecycleSnapshotStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .task {
            snap.loadId = loadId
            await snap.refresh()
        }
        .refreshable { await snap.refresh() }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch snap.state {
        case .loading:
            loadingHeader
            ProgressView().padding()
        case .loaded(let optionalSnapshot):
            if let live = optionalSnapshot {
                header(snapshot: live)
                ShipperLoadCycleView(
                    status: cycleStatus,
                    product: resolveProduct(live, role: session.user?.role),
                    vertical: TripVertical(role: session.user?.role)
                )
                bodyContent(live)
            } else {
                emptyHeader
            }
        case .empty:
            emptyHeader
        case .error(let err):
            errorHeader(err)
        }
    }

    private func header(snapshot live: ShipperAPI.LifecycleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(live.load.loadNumber).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(laneDisplay(live)).font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private var loadingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Loading…").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Pulling the latest from the load record.").font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private var emptyHeader: some View {
        EusoEmptyState(
            systemImage: "doc.text",
            title: "Load not found",
            subtitle: "The load you tapped is no longer in the system. Pull to refresh or pick another load from the list."
        )
    }

    private func errorHeader(_ err: Error) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
            }
            Text(err.localizedDescription).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await snap.refresh() } } label: {
                Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

import MapKit

/// LifecycleMapCard — drops a HERE basemap onto every lifecycle stage
/// (260–279) so the founder-doctrine "make sure HERE Maps is visual in
/// every place it is located" mandate is honored across the Shipper
/// post-load → settled flow. Each stage feeds the snapshot in; the card
/// renders pickup, truck-pin (lastGeofence), and delivery as appropriate.
///
/// Pin selection rules (mirrors what a dispatcher actually wants to see
/// at each stage):
///   • Stage 5  (BIDDING / AWARDED / PRE-PICKUP) — pickup + delivery
///   • Stage 6  (APPROACHING / AT GATE / AT DOCK) — truck + pickup
///   • Stage 6.5 (IN TRANSIT / HOS / EXCEPTION)   — pickup + truck + delivery
///   • Stage 7  (DELIVERY APPROACHING)            — truck + delivery
///   • Stage 8  (CANCELLED / EXCURSION)           — pickup + truck + delivery
///
/// The card auto-collapses to an empty-state caption when none of the
/// three coords are present on the snapshot — no fabricated lat/lngs,
/// no fake pins.
struct LifecycleMapCard: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var geocodeStore = LifecycleGeocodeStore.shared
    let live: ShipperAPI.LifecycleSnapshot
    /// Stable load identifier — used as the geocode-cache key so the
    /// fallback HERE Geocoding round-trip only fires once per load+side
    /// across a session (and survives app relaunches via UserDefaults).
    /// Defaults to the snapshot's load id so existing call sites that
    /// pass `live: live` keep working without an explicit loadId.
    var loadId: String? = nil
    var label: String = "LIVE MAP"
    var icon: String = "map.fill"
    /// Which pin set to render. See doc comment above.
    var mode: Mode = .full
    /// Override the rendered card height (default 220 pt — enough to read
    /// the basemap, small enough that the lifecycle card stack scrolls
    /// naturally on a 6.1" iPhone).
    var height: CGFloat = 220

    enum Mode {
        /// pickup + delivery only (no truck pin yet — Stage 5).
        case lane
        /// truck + pickup (Stages 6 / on-site).
        case truckAtPickup
        /// truck + delivery (Stage 7 — delivery approaching).
        case truckAtDelivery
        /// pickup + truck + delivery (full active route).
        case full
    }

    var body: some View {
        let pins = resolvedPins()

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if HereMapsConfig.hasBearerCredentials {
                    Text("MAP DATA")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
            }

            if pins.pickup == nil && pins.delivery == nil && pins.truck == nil {
                emptyMap
            } else {
                lifecycleLiveMap(pins)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var emptyMap: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No GPS coordinates yet")
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Map fills in once the carrier accepts and the driver pings.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Resolves the pickup / delivery / truck coordinates for the live map,
    /// reusing the same geocode-store resolution the legacy `computeStops`
    /// used — but tagged by side so `HereLiveMapView` renders typed
    /// (pickup / delivery / truck) pins instead of position-inferred ones.
    /// Coords resolution priority per side:
    ///   1. Snapshot's lat/lng (server-side geocode already ran)
    ///   2. LifecycleGeocodeStore cache (HERE-resolved, persisted)
    ///   3. Fire HERE Geocoding async + return nil for now (the store's
    ///      `objectWillChange` triggers a re-render when coords land)
    /// No fabricated lat/lng — a side stays nil until HERE resolves it; the
    /// empty-state caption renders only when all three sides are nil.
    private func resolvedPins() -> (pickup: HereLatLng?, delivery: HereLatLng?, truck: HereLatLng?) {
        let wantPickup = mode == .lane || mode == .truckAtPickup || mode == .full
        let wantDelivery = mode == .lane || mode == .truckAtDelivery || mode == .full
        let resolvedLoadId = loadId ?? "load-\(live.load.id)"

        var pickup: HereLatLng?
        var delivery: HereLatLng?

        if wantPickup, let p = live.pickup {
            let line = synthesizeAddressLine(
                facilityName: p.facilityName, address: p.address, city: p.city, state: p.state)
            if let coord = geocodeStore.coords(
                loadId: resolvedLoadId, side: .pickup,
                lat: p.lat, lng: p.lng, addressLine: line
            ) {
                pickup = HereLatLng(coord.latitude, coord.longitude)
            }
        }
        if wantDelivery, let d = live.delivery {
            let line = synthesizeAddressLine(
                facilityName: d.facilityName, address: d.address, city: d.city, state: d.state)
            if let coord = geocodeStore.coords(
                loadId: resolvedLoadId, side: .delivery,
                lat: d.lat, lng: d.lng, addressLine: line
            ) {
                delivery = HereLatLng(coord.latitude, coord.longitude)
            }
        }

        var truck: HereLatLng?
        if mode == .truckAtPickup || mode == .truckAtDelivery || mode == .full,
           let g = live.lastGeofence,
           !(g.latitude == 0 && g.longitude == 0) {
            // Gate null-island (0,0): a freshly-emitted geofence whose GPS
            // hasn't locked yet (or a malformed row) must NOT drop the truck
            // puck in the Gulf of Guinea. Mirror Carrier/311_CarrierActiveLoad.
            truck = HereLatLng(g.latitude, g.longitude)
        }
        return (pickup, delivery, truck)
    }

    /// Synthesize a single-line address suitable for HERE Geocoding.
    /// Prefer the most specific available components — facility name +
    /// street + city + state — falling back to whatever's present.
    /// HERE's geocoder tolerates loose strings well.
    private func synthesizeAddressLine(
        facilityName: String?,
        address: String?,
        city: String?,
        state: String?
    ) -> String {
        var parts: [String] = []
        if let f = facilityName, !f.isEmpty { parts.append(f) }
        if let a = address, !a.isEmpty, a != facilityName { parts.append(a) }
        if let c = city, !c.isEmpty { parts.append(c) }
        if let s = state, !s.isEmpty { parts.append(s) }
        return parts.joined(separator: ", ")
    }

    /// The live HERE vector map for this lifecycle stage: typed pickup /
    /// delivery / truck pins on the OMV basemap, a route connector when both
    /// endpoints are known, and shipper situational add-ons (weather +
    /// traffic + sponsored ad-zones). Migrated 2026-05-22 off the legacy
    /// raster `HereMapView(stops:extraAnnotations:)`.
    private func lifecycleLiveMap(
        _ pins: (pickup: HereLatLng?, delivery: HereLatLng?, truck: HereLatLng?)
    ) -> some View {
        let present = [pins.pickup, pins.delivery, pins.truck].compactMap { $0 }
        let center = HereLatLng(
            present.map { $0.lat }.reduce(0, +) / Double(max(present.count, 1)),
            present.map { $0.lng }.reduce(0, +) / Double(max(present.count, 1))
        )
        let routePts = [pins.pickup, pins.delivery].compactMap { $0 }

        var markers: [HereMarker] = []
        if let p = pins.pickup   { markers.append(HereMarker(at: p, kind: .pickup,   label: "Pickup")) }
        if let d = pins.delivery { markers.append(HereMarker(at: d, kind: .delivery, label: "Delivery")) }
        if let t = pins.truck    { markers.append(HereMarker(at: t, kind: .truck,    label: "Truck")) }

        var baseLayers: [HereMapLayer] = []
        if routePts.count >= 2 {
            baseLayers.append(.route(polyline: routePts, colorHex: "#1473FF"))
        }
        baseLayers.append(.markers(markers))

        return HereLiveMapView(
            center: center,
            zoom: routePts.count >= 2 ? 6 : 9,
            route: routePts,
            baseLayers: baseLayers,
            addOns: .shipperTracking
        )
    }
}

/// LifecycleAnimationStrip — renders the right EquipmentKind animation
/// for the load's modality + cargo, with every `[data-bind]` text node
/// in the SVG substituted from the live LifecycleSnapshot via
/// `BindableEquipmentAnimation`.
///
/// Founder ask 2026-05-10: ship the universal animation surface across
/// every shipper / driver lifecycle screen so the freight reads as a
/// real load (real UN number, real reporting marks, real ETA, real
/// dock id) instead of the SVG's baked default sample.
///
/// This view is the iOS counterpart to the web `<AnimationView>` that
/// the bundle's `RUNTIME_INTEGRATION_GUIDE.md` documents. Same binding
/// contract, same data-bind keys, same fallback-to-baked-default
/// behavior when the snapshot doesn't carry a value.
struct LifecycleAnimationStrip: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    var label: String = "EQUIPMENT"
    var height: CGFloat = 200

    /// Real assigned dock door for this load — the same
    /// `appointments.getByLoad.dockNumber` read the driver lifecycle
    /// screens (024/037/039) hydrate. Nil until it resolves or when no
    /// door is assigned; the SVG dock chip then falls through to
    /// facility / city / the honest em-dash — never the baked
    /// "DOCK 12" Figma sample (Wave-A1 fabrication kill, 2026-06-10).
    @State private var dockNumber: String?

    /// Lifecycle-continuity clock epoch (Wave B, 2026-06-10) — keyed
    /// to the STRIP's first appearance, not the SVG string, so the
    /// wheel/strobe phase carries across the hero → loading →
    /// unloading variant swap instead of resetting on every crossfade.
    @State private var stripEpoch = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: equipmentKind.iconName)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(stateLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }

            // Wave B (2026-06-10) — the strip now renders the LIFECYCLE
            // state variant, not the hero: at the dock the shipper sees
            // the loading procedure file (the bind-rich catalog the
            // census found fully orphaned), at the receiver the
            // unloading file, in transit the hero. Selection rides the
            // live load status through the canonical
            // `AnimationState(loadStatus:)` map.
            if let svg = EquipmentAnimationCache.shared
                .svg(for: equipmentKind, state: animationState) {
                BindableEquipmentAnimation(
                    svgString: svg,
                    context: animationContext,
                    clockReference: stripEpoch
                )
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            } else {
                emptyAnimation
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .task(id: live.load.id) {
            // Warm the loading/unloading variants for the active load's
            // kind so the lifecycle swap crossfades without a first-
            // parse hitch (Wave B preload, spec gap 1).
            EquipmentAnimationCache.shared.preloadStateVariants(for: equipmentKind)
            // Best-effort, nil-tolerant: no appointment / no door →
            // dockNumber stays nil and the chip resolves honestly.
            let appt = try? await EusoTripAPI.shared.appointments
                .getByLoad(loadId: String(live.load.id))
            let door = appt?.dockNumber?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            dockNumber = (door?.isEmpty == false) ? door : nil
        }
    }

    /// Which procedure file renders — driven by the REAL lifecycle
    /// status (loading block → Loading variant, unloading block →
    /// Unloading variant, everything else → hero).
    private var animationState: AnimationState {
        AnimationState(loadStatus: live.load.status)
    }

    private var animationContext: LoadAnimationContext {
        LoadAnimationContext.from(snapshot: live, dockNumber: dockNumber)
    }

    private var stateLabel: String {
        live.load.status.uppercased().replacingOccurrences(of: "_", with: " ")
    }

    /// Maps the snapshot's equipmentType to the canonical model via
    /// the ONE shared resolver (`EquipmentKind.resolve(from:)`, Wave B
    /// 2026-06-10) — the strip's private matcher missed the T-030 six
    /// + auto-carrier, so a livestock load painted a dry van here
    /// while ConvoyAnimationStrip matched it correctly. Hazmat-aware,
    /// dry-van honest floor.
    private var equipmentKind: EquipmentKind {
        EquipmentKind.resolve(
            from: live.load.equipmentType,
            hazmat: (live.load.hazmatClass?.isEmpty == false),
            modality: .truck
        )
    }

    private var emptyAnimation: some View {
        VStack(spacing: 6) {
            Image(systemName: equipmentKind.iconName)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("Equipment animation not bundled yet")
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// SF Symbol icon for each `EquipmentKind` — used in the
/// LifecycleAnimationStrip header label and any future surface that
/// needs a glyph alongside the rendered animation.
extension EquipmentKind {
    var iconName: String {
        switch vertical {
        case .truck:  return "truck.box.fill"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        }
    }
}
