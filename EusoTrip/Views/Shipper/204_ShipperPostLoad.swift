//
//  204_ShipperPostLoad.swift
//  EusoTrip — Shipper · Post a Load (brick 204).
//
//  Parity-reconciled to `02 Shipper/Code/204_ShipperPostLoad.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: 4-step stepper (LANE → EQUIPMENT → PRICING → REVIEW),
//  TopBar (eyebrow + step counter + back chevron + Post a load title
//  + close X), IridescentHairline, lane card with bullet-circle
//  endpoints + dashed connector + swap button, route-meta pill,
//  schedule tile pair, equipment preview (locked behind step 2 with
//  hazmat diamond glyph), target rate estimate card, Continue/Submit
//  CTA per-step.
//
//  Real data preserved: ShipperPostLoadStore + shippers.create
//  mutation pipeline (validation, optional fields → nil coalesce,
//  reset form on success). Form bindings unchanged. Cargo type
//  picker kept on the EQUIPMENT step. Weight/rate/notes on the
//  PRICING step.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.2 anchor MATRIX-50 row this brick is calibrated against:
//    LD-260427-A38FB12C7E · Houston TX → Dallas TX · MC-306 · UN1203 ·
//    50,000 lb · target $1,950 (= $8.16/mi, +3% above $7.92/mi spot).
//
//  BottomNav: Home / Create Load (current) / Loads / Me — out of scope
//  per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - 4-step state machine

private enum PostLoadStep: Int, CaseIterable, Identifiable {
    case lane      = 1
    case equipment = 2
    case pricing   = 3
    case review    = 4

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .lane:      return "LANE"
        case .equipment: return "EQUIPMENT"
        case .pricing:   return "PRICING"
        case .review:    return "REVIEW"
        }
    }
    var next: PostLoadStep? { PostLoadStep(rawValue: rawValue + 1) }
    var prev: PostLoadStep? { PostLoadStep(rawValue: rawValue - 1) }
}

// MARK: - Screen root

struct ShipperPostLoad: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperPostLoadStore()

    // Wizard state
    @State private var step: PostLoadStep = .lane

    // Form state — preserved from prior surface
    @State private var origin: String = ""
    @State private var destination: String = ""
    // Geocoded coordinates captured by `HereAddressField`. Sent with
    // `shippers.create` so distance / map render without a server-
    // side re-geocode round-trip. Founder report 2026-05-05 — the
    // 204 Post Load screen was using plain `TextField` for
    // origin/destination, not the autocomplete-aware HereAddressField
    // that step 250 uses, so users typing "Housto" got iOS keyboard
    // predictions but no platform autocomplete. Swapped below.
    @State private var originLat: Double? = nil
    @State private var originLng: Double? = nil
    @State private var destLat: Double? = nil
    @State private var destLng: Double? = nil
    @State private var cargoType: ShipperAPI.CargoType = .general
    @State private var hasPickupDate: Bool = false
    @State private var pickupDate: Date = Date()
    @State private var weightText: String = ""
    @State private var rateText: String = ""
    @State private var notes: String = ""

    // Equipment type picker — all verticals + product types per the
    // founder's "all verticals" doctrine. The selected type is sent
    // as `equipmentType` on `shippers.create`. Default = dry van.
    @State private var equipmentType: EquipmentChoice = .dryVan

    // Hazmat / tanker subform fields. Stored locally and packed into
    // the `notes` field at submit time (server schema doesn't yet
    // ship structured tanker spec columns; web parity).
    @State private var unNumber: String = ""
    @State private var hazmatClass: String = ""
    @State private var packingGroup: String = ""
    @State private var properShippingName: String = ""
    @State private var tankerHoseSpec: String = ""
    @State private var tankerFitting: String = ""

    // ERG (Emergency Response Guidebook) lookup state. When the user
    // types a UN number, debounce → fire `erg.searchByUN` → if a
    // match is found, auto-populate hazmat class + proper shipping
    // name + ERG guide. Web parity with the platform's ERG database.
    @State private var ergMatch: ErgAPI.MaterialDetail? = nil
    @State private var isLookingUpERG: Bool = false
    @State private var ergLookupError: String? = nil
    @State private var lastErgQueryKey: String = ""
    @State private var showErgSearchSheet: Bool = false
    @State private var ergSearchQuery: String = ""
    @State private var ergSearchHits: [ErgAPI.SearchHit] = []
    @State private var isSearchingERG: Bool = false

    // Reefer subform.
    @State private var reeferTempLowText:  String = ""
    @State private var reeferTempHighText: String = ""
    @State private var preCoolRequired:    Bool = false
    @State private var continuousMode:     Bool = true

    // Flatbed / oversized subform.
    @State private var flatbedStraps:          Bool = false
    @State private var flatbedTarps:           Bool = false
    @State private var flatbedChains:          Bool = false
    @State private var flatbedEdgeProtectors:  Bool = false
    @State private var oversizeLengthText:     String = ""
    @State private var oversizeWidthText:      String = ""
    @State private var oversizeHeightText:     String = ""
    @State private var oversizePermits:        Bool = false

    @State private var lastSuccess: ShipperAPI.PostLoadAck? = nil

    // MARK: - Autosave + cross-device continuity
    //
    // Founder ask 2026-05-07: "truly autosaves in case phone dies or
    // app closes" + "save on one device it should show up in their
    // account on the other, pure continuity".
    //
    // Strategy:
    // 1. Local crash-recovery: UserDefaults via PostLoadDraftSnapshot.
    // 2. Cross-device: NSUbiquitousKeyValueStore (Apple's free iCloud
    //    KVS — auto-syncs across user's devices, ~1KB / draft fits
    //    well under 1MB cap).
    // 3. Server-backed templates for true cross-platform parity:
    //    `loadTemplates.create` saves a named template; web platform
    //    sees it via the same router.
    @State private var didHydrateDraft: Bool = false
    @State private var showTemplatePicker: Bool = false
    @State private var showSaveTemplateSheet: Bool = false
    @State private var savingTemplate: Bool = false
    @State private var templateSaveAck: String? = nil
    @State private var templateNameDraft: String = ""

    /// Equipment-type choice covering truck (dry van / reefer /
    /// flatbed / step deck / conestoga / container / tanker variants
    /// / power-only), rail (TOFC / COFC / intermodal container),
    /// and vessel (container / bulk / tanker) verticals. Web parity
    /// with the platform's full LoadEquipmentType enum. Stored as
    /// the raw string sent to `shippers.create` so the catalyst's
    /// dispatcher / driver knows what physical asset to roll.
    enum EquipmentChoice: String, CaseIterable, Identifiable {
        // Truck verticals
        case dryVan        = "dry_van"
        case reefer        = "reefer"
        case flatbed       = "flatbed"
        case stepDeck      = "step_deck"
        case conestoga     = "conestoga"
        case container     = "container"
        case tankerHazmat  = "tanker_hazmat"
        case tankerPetro   = "tanker_petroleum"
        case tankerLiquid  = "tanker_liquid"
        case tankerGas     = "tanker_gas"
        case powerOnly     = "power_only"
        case oversized     = "oversized"
        // Rail vertical
        case railTOFC      = "rail_tofc"
        case railCOFC      = "rail_cofc"
        case railIntermodal = "rail_intermodal"
        // Vessel vertical
        case vesselContainer = "vessel_container"
        case vesselBulk      = "vessel_bulk"
        case vesselTanker    = "vessel_tanker"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .dryVan:           return "Dry van"
            case .reefer:           return "Reefer"
            case .flatbed:          return "Flatbed"
            case .stepDeck:         return "Step deck"
            case .conestoga:        return "Conestoga"
            case .container:        return "Container"
            case .tankerHazmat:     return "Tanker · Hazmat"
            case .tankerPetro:      return "Tanker · Petroleum"
            case .tankerLiquid:     return "Tanker · Liquid bulk"
            case .tankerGas:        return "Tanker · Gas"
            case .powerOnly:        return "Power only"
            case .oversized:        return "Oversized"
            case .railTOFC:         return "Rail · TOFC"
            case .railCOFC:         return "Rail · COFC"
            case .railIntermodal:   return "Rail · Intermodal"
            case .vesselContainer:  return "Vessel · Container"
            case .vesselBulk:       return "Vessel · Bulk"
            case .vesselTanker:     return "Vessel · Tanker"
            }
        }
        var systemImage: String {
            switch self {
            case .dryVan:           return "shippingbox.fill"
            case .reefer:           return "thermometer.snowflake"
            case .flatbed:          return "rectangle.expand.vertical"
            case .stepDeck:         return "rectangle.split.2x1"
            case .conestoga:        return "shippingbox.and.arrow.backward"
            case .container:        return "cube.box.fill"
            case .tankerHazmat:     return "exclamationmark.triangle.fill"
            case .tankerPetro:      return "fuelpump.fill"
            case .tankerLiquid:     return "drop.triangle.fill"
            case .tankerGas:        return "wind"
            case .powerOnly:        return "bolt.car.fill"
            case .oversized:        return "arrow.up.left.and.arrow.down.right"
            case .railTOFC:         return "tram.fill"
            case .railCOFC:         return "tram"
            case .railIntermodal:   return "cube.transparent.fill"
            case .vesselContainer:  return "ferry.fill"
            case .vesselBulk:       return "ferry"
            case .vesselTanker:     return "drop.fill"
            }
        }
        var vertical: String {
            switch self {
            case .railTOFC, .railCOFC, .railIntermodal: return "rail"
            case .vesselContainer, .vesselBulk, .vesselTanker: return "vessel"
            default: return "truck"
            }
        }
    }

    private let deliveryETAFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f
    }()

    // MARK: - HERE Routing — distance + ETA estimation
    //
    // Founder bug 2026-05-07: "the eta calculating still doesnt work
    // mate. still missing the enhancements you made to that post a
    // load wizard." The earlier copy promised "ETA computed · Auto-set
    // from pickup + lane" but never actually fired a router request.
    //
    // Fix: when origin + destination + pickupDate are all set, hit
    // `HereRoutingClient.route(stops:profile:)` with a standard US
    // semi truck profile. Store the resulting distance (meters) +
    // duration (seconds), derive the deliveryETA from pickupDate +
    // duration, and surface real values in the delivery tile.
    @State private var routeDistanceMeters: Int? = nil
    @State private var routeDurationSeconds: Int? = nil
    @State private var routingError: String? = nil
    @State private var isRouting: Bool = false

    /// Resolved state codes from the geocode hit. Used by the ESANG
    /// rate-vs-market meter on step 3 (Pricing) — `rates.compareLaneRate`
    /// is keyed by origin/destination state codes.
    @State private var originStateCode: String? = nil
    @State private var destStateCode: String? = nil

    /// ESANG AI rate market position (above/at/below market) for the
    /// posted rate vs comparable platform + national-benchmark loads.
    /// Web parity (founder ask 2026-05-07): the wizard now shows the
    /// same gradient meter the web Post Load form uses. Wired to
    /// `rates.compareLaneRate`.
    @State private var rateComparison: RatesAPI.LaneComparison? = nil
    @State private var rateCompareError: String? = nil
    @State private var isComparingRate: Bool = false
    @State private var lastRateCompareKey: String = ""

    /// Cached lat/lng tuple of the last query so we don't re-fire
    /// the routing call on every keystroke.
    @State private var lastRoutedKey: String = ""

    /// Computed delivery ETA = pickupDate + routeDurationSeconds.
    /// Returns nil until both values are present.
    private var computedDeliveryETA: Date? {
        guard hasPickupDate, let secs = routeDurationSeconds else { return nil }
        return pickupDate.addingTimeInterval(TimeInterval(secs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    stepper
                    if let ack = lastSuccess {
                        successBanner(ack)
                    }
                    if case .error(let message) = store.phase {
                        errorBanner(message)
                    }
                    stepBody
                    continueOrSubmitCTA
                    Color.clear.frame(height: 96)
                }
                .padding(Space.s5)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .screenTileRoot()
        // Re-fire HERE Routing whenever the lane endpoints' lat/lng
        // change. Address-field selection populates these and bumps
        // a rebuild; we reactively trigger the route computation so
        // the delivery tile populates as soon as a valid lane exists.
        .onChange(of: originLat) { _, _ in recomputeETAIfReady() }
        .onChange(of: originLng) { _, _ in recomputeETAIfReady() }
        .onChange(of: destLat)   { _, _ in recomputeETAIfReady() }
        .onChange(of: destLng)   { _, _ in recomputeETAIfReady() }
        // Also re-fire when the typed strings settle — fall-back
        // path for users who paste / type without tapping a
        // suggestion. `recomputeETAIfReady` will geocode the typed
        // text inline.
        .onChange(of: origin)      { _, _ in recomputeETAIfReady() }
        .onChange(of: destination) { _, _ in recomputeETAIfReady() }
        // Rate compare fires when posted rate or cargo type changes —
        // independent of routing, so the meter updates without
        // re-geocoding.
        .onChange(of: rateText)  { _, _ in recomputeRateCompareIfReady() }
        .onChange(of: cargoType) { _, _ in recomputeRateCompareIfReady() }
        // Hydrate any in-progress draft on first appear (crash
        // recovery + iCloud cross-device continuity). Skip on
        // subsequent appears so navigating back to step 1 doesn't
        // wipe in-progress edits.
        .onAppear {
            if !didHydrateDraft {
                hydrateDraftIfPresent()
                didHydrateDraft = true
            }
        }
        // Autosave on every meaningful field change. Collapsed into
        // a single onChange driven by `autosaveDigest` (a hash of
        // every watched value) — chaining 30+ `.onChange` modifiers
        // overwhelmed Swift's type-checker. The persist helper
        // writes to UserDefaults (local crash recovery) AND
        // NSUbiquitousKeyValueStore (iCloud KVS — cross-device).
        .onChange(of: autosaveDigest) { _, _ in persistDraft() }
        // ERG lookup fires off a separate UN-only debouncer so
        // typing in unrelated fields doesn't trigger a re-lookup.
        .onChange(of: unNumber) { _, _ in lookupERGIfReady() }
        // Listen to remote iCloud KVS changes — when the user edits
        // the draft on another signed-in device, NSUbiquitousKVStore
        // posts a change notification; we re-hydrate so the in-flight
        // wizard reflects the remote edits.
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )) { _ in
            hydrateDraftIfPresent()
        }
        // ERG search sheet (typeahead by name)
        .sheet(isPresented: $showErgSearchSheet) { ergSearchSheet }
    }

    // MARK: - ERG search sheet

    private var ergSearchSheet: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ERG · Find a material")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showErgSearchSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                TextField("UN number or material name", text: $ergSearchQuery)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .autocorrectionDisabled()
                    .onSubmit { searchERG() }
                    .onChange(of: ergSearchQuery) { _, _ in searchERG() }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            if isSearchingERG {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).tint(LinearGradient.diagonal)
                    Text("Searching ERG…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s2) {
                    ForEach(ergSearchHits) { hit in
                        Button { applyERGHit(hit) } label: {
                            ergSearchRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                    if ergSearchHits.isEmpty && !ergSearchQuery.isEmpty && !isSearchingERG {
                        Text("No ERG match for '\(ergSearchQuery)'")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
    }

    @ViewBuilder
    private func ergSearchRow(_ hit: ErgAPI.SearchHit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("UN\(hit.unNumber)")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Guide \(hit.guide)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    if hit.isTIH == true {
                        Text("TIH").font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.danger))
                    }
                }
                Text(hit.name.capitalized)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text("Class \(hit.hazardClass) · \(hit.placardName)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Draft autosave + iCloud KVS continuity

    /// JSON-encodable snapshot of every field the wizard captures.
    /// Bumped to `v: 2` when adding ERG/equipment fields beyond the
    /// original lane/cargo/rate set so older drafts in storage decode
    /// gracefully (missing fields become defaults).
    private struct PostLoadDraftSnapshot: Codable {
        var v: Int = 2
        var origin: String = ""
        var destination: String = ""
        var originLat: Double? = nil
        var originLng: Double? = nil
        var destLat: Double? = nil
        var destLng: Double? = nil
        var cargoTypeRaw: String = "general"
        var equipmentTypeRaw: String = "dry_van"
        var hasPickupDate: Bool = false
        var pickupDateUnix: Double = 0
        var weightText: String = ""
        var rateText: String = ""
        var notes: String = ""
        var unNumber: String = ""
        var hazmatClass: String = ""
        var packingGroup: String = ""
        var properShippingName: String = ""
        var tankerHoseSpec: String = ""
        var tankerFitting: String = ""
        var reeferTempLowText: String = ""
        var reeferTempHighText: String = ""
        var preCoolRequired: Bool = false
        var continuousMode: Bool = true
        var flatbedStraps: Bool = false
        var flatbedTarps: Bool = false
        var flatbedChains: Bool = false
        var flatbedEdgeProtectors: Bool = false
        var oversizeLengthText: String = ""
        var oversizeWidthText: String = ""
        var oversizeHeightText: String = ""
        var oversizePermits: Bool = false
        var savedAt: Double = 0
    }

    /// Single hash of every autosaved field. Drives one `.onChange`
    /// call — chaining 30+ `.onChange` modifiers tripped Swift's
    /// type-checker timeout. Built imperatively so the type-checker
    /// has nothing to infer beyond `String + String`.
    private var autosaveDigest: String {
        var s = ""
        s += origin; s += "|"
        s += destination; s += "|"
        s += originLat.map { String($0) } ?? ""; s += "|"
        s += originLng.map { String($0) } ?? ""; s += "|"
        s += destLat.map { String($0) } ?? ""; s += "|"
        s += destLng.map { String($0) } ?? ""; s += "|"
        s += cargoType.rawValue; s += "|"
        s += equipmentType.rawValue; s += "|"
        s += String(hasPickupDate); s += "|"
        s += String(Int(pickupDate.timeIntervalSince1970)); s += "|"
        s += weightText; s += "|"
        s += rateText; s += "|"
        s += notes; s += "|"
        s += unNumber; s += "|"
        s += hazmatClass; s += "|"
        s += packingGroup; s += "|"
        s += properShippingName; s += "|"
        s += tankerHoseSpec; s += "|"
        s += tankerFitting; s += "|"
        s += reeferTempLowText; s += "|"
        s += reeferTempHighText; s += "|"
        s += String(preCoolRequired); s += "|"
        s += String(continuousMode); s += "|"
        s += String(flatbedStraps); s += "|"
        s += String(flatbedTarps); s += "|"
        s += String(flatbedChains); s += "|"
        s += String(flatbedEdgeProtectors); s += "|"
        s += oversizeLengthText; s += "|"
        s += oversizeWidthText; s += "|"
        s += oversizeHeightText; s += "|"
        s += String(oversizePermits)
        return s
    }

    /// Per-user draft key — guards against draft cross-contamination
    /// when multiple accounts share a device. Falls back to a shared
    /// key when no userId is signed in (rare; pre-auth state).
    private var draftStorageKey: String {
        let uid = session.user?.id ?? "anon"
        return "shipper.postLoadDraft.\(uid)"
    }

    private func persistDraft() {
        guard didHydrateDraft else { return }   // skip on first hydrate pass
        let snap = PostLoadDraftSnapshot(
            v: 2,
            origin: origin,
            destination: destination,
            originLat: originLat, originLng: originLng,
            destLat: destLat, destLng: destLng,
            cargoTypeRaw: cargoType.rawValue,
            equipmentTypeRaw: equipmentType.rawValue,
            hasPickupDate: hasPickupDate,
            pickupDateUnix: pickupDate.timeIntervalSince1970,
            weightText: weightText,
            rateText: rateText,
            notes: notes,
            unNumber: unNumber,
            hazmatClass: hazmatClass,
            packingGroup: packingGroup,
            properShippingName: properShippingName,
            tankerHoseSpec: tankerHoseSpec,
            tankerFitting: tankerFitting,
            reeferTempLowText: reeferTempLowText,
            reeferTempHighText: reeferTempHighText,
            preCoolRequired: preCoolRequired,
            continuousMode: continuousMode,
            flatbedStraps: flatbedStraps,
            flatbedTarps: flatbedTarps,
            flatbedChains: flatbedChains,
            flatbedEdgeProtectors: flatbedEdgeProtectors,
            oversizeLengthText: oversizeLengthText,
            oversizeWidthText: oversizeWidthText,
            oversizeHeightText: oversizeHeightText,
            oversizePermits: oversizePermits,
            savedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: draftStorageKey)
            // iCloud KVS — synchronous in-memory write; .synchronize()
            // schedules upload. Cross-device propagation handled by
            // Apple's iCloud daemon.
            NSUbiquitousKeyValueStore.default.set(data, forKey: draftStorageKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    private func hydrateDraftIfPresent() {
        // Prefer iCloud copy when present (most-recently-edited
        // device wins); fall back to local UserDefaults.
        let cloud = NSUbiquitousKeyValueStore.default.data(forKey: draftStorageKey)
        let local = UserDefaults.standard.data(forKey: draftStorageKey)
        let chosen: Data? = {
            switch (cloud, local) {
            case (let c?, let l?):
                let cs = (try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: c))?.savedAt ?? 0
                let ls = (try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: l))?.savedAt ?? 0
                return cs >= ls ? c : l
            case (let c?, nil): return c
            case (nil, let l?): return l
            default: return nil
            }
        }()
        guard let data = chosen,
              let snap = try? JSONDecoder().decode(PostLoadDraftSnapshot.self, from: data) else {
            return
        }
        origin = snap.origin
        destination = snap.destination
        originLat = snap.originLat; originLng = snap.originLng
        destLat = snap.destLat; destLng = snap.destLng
        cargoType = ShipperAPI.CargoType(rawValue: snap.cargoTypeRaw) ?? .general
        equipmentType = EquipmentChoice(rawValue: snap.equipmentTypeRaw) ?? .dryVan
        hasPickupDate = snap.hasPickupDate
        if snap.pickupDateUnix > 0 {
            pickupDate = Date(timeIntervalSince1970: snap.pickupDateUnix)
        }
        weightText = snap.weightText
        rateText = snap.rateText
        notes = snap.notes
        unNumber = snap.unNumber
        hazmatClass = snap.hazmatClass
        packingGroup = snap.packingGroup
        properShippingName = snap.properShippingName
        tankerHoseSpec = snap.tankerHoseSpec
        tankerFitting = snap.tankerFitting
        reeferTempLowText = snap.reeferTempLowText
        reeferTempHighText = snap.reeferTempHighText
        preCoolRequired = snap.preCoolRequired
        continuousMode = snap.continuousMode
        flatbedStraps = snap.flatbedStraps
        flatbedTarps = snap.flatbedTarps
        flatbedChains = snap.flatbedChains
        flatbedEdgeProtectors = snap.flatbedEdgeProtectors
        oversizeLengthText = snap.oversizeLengthText
        oversizeWidthText = snap.oversizeWidthText
        oversizeHeightText = snap.oversizeHeightText
        oversizePermits = snap.oversizePermits
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftStorageKey)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: draftStorageKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · POST A LOAD · STEP \(step.rawValue) / \(PostLoadStep.allCases.count)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(autosaveLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Button(action: backTapped) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Post a load")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer()

                Button(action: closeTapped) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel and discard draft")
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var autosaveLine: String {
        switch store.phase {
        case .submitting: return "POSTING…"
        case .success:    return "POSTED"
        case .error:      return "DRAFT · ERROR"
        case .idle:       return "DRAFT · AUTOSAVED"
        }
    }

    private func backTapped() {
        if let p = step.prev {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) { step = p }
        } else {
            NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
        }
    }

    private func closeTapped() {
        NotificationCenter.default.post(name: .eusoShipperPostLoadDismiss, object: nil)
    }

    // MARK: - Stepper

    private var stepper: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    stepDot(for: s)
                    if s != PostLoadStep.allCases.last {
                        Rectangle()
                            .fill(s.rawValue < step.rawValue
                                  ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(palette.textTertiary.opacity(0.20)))
                            .frame(height: 2)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(PostLoadStep.allCases) { s in
                    Text(s.label)
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(s == step
                                         ? AnyShapeStyle(palette.textPrimary)
                                         : AnyShapeStyle(palette.textTertiary))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, Space.s2)
    }

    private func stepDot(for s: PostLoadStep) -> some View {
        let isActive = (s == step)
        let isComplete = (s.rawValue < step.rawValue)
        return ZStack {
            Circle()
                .fill((isActive || isComplete)
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.bgCard))
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .frame(width: 28, height: 28)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Text("\(s.rawValue)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isActive ? .white : palette.textTertiary)
            }
        }
        .accessibilityLabel("Step \(s.rawValue) of \(PostLoadStep.allCases.count)" +
                            (isActive ? ", current" : isComplete ? ", complete" : ""))
    }

    // MARK: - Step body switch

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .lane:      laneStepBody
        case .equipment: equipmentStepBody
        case .pricing:   pricingStepBody
        case .review:    reviewStepBody
        }
    }

    // MARK: - Step 1: LANE

    @ViewBuilder
    private var laneStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            laneSection
            routeMetaPill
            scheduleSection
        }
    }

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    laneField(label: "ORIGIN",
                              text: $origin,
                              lat: $originLat,
                              lng: $originLng,
                              placeholder: "City, ST or lat,lng · e.g. Houston, TX")
                    laneConnector
                    laneField(label: "DESTINATION",
                              text: $destination,
                              lat: $destLat,
                              lng: $destLng,
                              placeholder: "City, ST or lat,lng · e.g. Dallas, TX")
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                Button(action: swapEndpoints) {
                    swapButton
                }
                .buttonStyle(.plain)
                .padding(Space.s4)
                .accessibilityLabel("Swap origin and destination")
            }
        }
    }

    /// Lane row — origin or destination — uses `HereAddressField` for
    /// HERE-Geocoding-backed autocomplete + raw "lat,lng" paste
    /// support. Founder report 2026-05-05: the prior plain
    /// `TextField` produced ZERO autocomplete suggestions (only iOS
    /// keyboard's own predictive bar showed); now real HERE place
    /// suggestions appear inline.
    private func laneField(
        label: String,
        text: Binding<String>,
        lat: Binding<Double?>,
        lng: Binding<Double?>,
        placeholder: String
    ) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .stroke(LinearGradient.primary, lineWidth: 2)
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 5, height: 5)
            }
            .padding(.top, 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HereAddressField(
                    text: text,
                    lat: lat,
                    lng: lng,
                    placeholder: placeholder
                )
                .disabled(isSubmitting)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var laneConnector: some View {
        Rectangle()
            .fill(LinearGradient.primary)
            .frame(width: 2, height: 24)
            .mask(
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().frame(width: 2, height: 2)
                    }
                }
            )
            .padding(.leading, 6)
            .padding(.vertical, 4)
    }

    private var swapButton: some View {
        ZStack {
            Circle().fill(palette.bgCard).frame(width: 32, height: 32)
            Circle().strokeBorder(palette.borderFaint).frame(width: 32, height: 32)
            VStack(spacing: 2) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .heavy))
                Image(systemName: "arrow.left")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(palette.textPrimary)
        }
    }

    private func swapEndpoints() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
            let tmp = origin
            origin = destination
            destination = tmp
        }
    }

    private var routeMetaPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
            Text(routeMetaText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 10)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.06),
                                            Brand.magenta.opacity(0.06)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var routeMetaText: String {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if oTrim.isEmpty || dTrim.isEmpty {
            return "Add origin + destination — distance / ETA estimates auto-fill"
        }
        if isRouting {
            return "Computing distance + ETA via ESANG…"
        }
        if let err = routingError {
            return "Routing error: \(err)"
        }
        if let meters = routeDistanceMeters, let secs = routeDurationSeconds {
            let miles = Double(meters) / 1609.34
            let hours = Double(secs) / 3600.0
            return String(format: "%.0f mi · %.1f hr · standard US semi · ESANG-routed", miles, hours)
        }
        // Both addresses present and `recomputeETAIfReady` is in flight.
        return "Estimating distance · ETA · best-route via ESANG"
    }

    /// Fire HERE Routing whenever the lane endpoints OR pickup
    /// schedule change. Debounced via `lastRoutedKey`. When lat/lng
    /// haven't been captured yet (user typed an address but never
    /// tapped a HERE suggestion), forward-geocodes the typed text
    /// first so the ETA computes regardless of whether the user
    /// picked from the dropdown. Founder bug 2026-05-07: "ETA
    /// calculating still doesnt work mate" — typing 'Houston, TX'
    /// + 'Austin, TX' previously left the delivery tile stuck on
    /// 'Awaiting addresses · Pick HERE suggestions' because the
    /// HereAddressField only captures coordinates on tap.
    private func recomputeETAIfReady() {
        let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oTrim.isEmpty, !dTrim.isEmpty else {
            routeDistanceMeters = nil
            routeDurationSeconds = nil
            return
        }
        let key = "\(originLat ?? .nan),\(originLng ?? .nan)|\(destLat ?? .nan),\(destLng ?? .nan)|\(oTrim)|\(dTrim)"
        guard key != lastRoutedKey else { return }
        lastRoutedKey = key
        isRouting = true
        routingError = nil
        Task {
            do {
                let originResolved = try await ensureResolved(
                    text: oTrim,
                    cachedLat: originLat,
                    cachedLng: originLng
                )
                let destResolved = try await ensureResolved(
                    text: dTrim,
                    cachedLat: destLat,
                    cachedLng: destLng
                )
                // Backfill the @State bindings so the wizard's
                // submit step has resolved coordinates + state
                // codes without a second geocode round-trip. The
                // state codes also feed the ESANG rate compare on
                // step 3.
                await MainActor.run {
                    if originLat == nil { originLat = originResolved.coord.latitude }
                    if originLng == nil { originLng = originResolved.coord.longitude }
                    if destLat == nil   { destLat   = destResolved.coord.latitude   }
                    if destLng == nil   { destLng   = destResolved.coord.longitude  }
                    self.originStateCode = originResolved.stateCode
                    self.destStateCode   = destResolved.stateCode
                }
                let resp = try await HereRoutingClient.shared.route(
                    stops: HereStops(origin: originResolved.coord,
                                     destination: destResolved.coord),
                    profile: .standardUSSemiLoaded
                )
                let totalDuration = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.duration ?? 0) } ?? 0
                let totalLength   = resp.routes.first?.sections.reduce(0) { $0 + ($1.summary?.length ?? 0) }   ?? 0
                await MainActor.run {
                    self.routeDurationSeconds = totalDuration
                    self.routeDistanceMeters  = totalLength
                    self.isRouting = false
                    // Now that we have lane states + distance, fire
                    // the rate compare if the user has already typed
                    // a posted rate.
                    self.recomputeRateCompareIfReady()
                }
            } catch {
                await MainActor.run {
                    self.routingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isRouting = false
                }
            }
        }
    }

    // MARK: - ESANG rate vs market meter (rates.compareLaneRate)

    /// Fires `rates.compareLaneRate` when origin state + dest state +
    /// distance + a posted rate are all known. Web parity meter; same
    /// `LaneComparison` envelope the LoadDetailSheet renders next to
    /// the posted rate.
    private func recomputeRateCompareIfReady() {
        guard let oState = originStateCode, !oState.isEmpty,
              let dState = destStateCode,   !dState.isEmpty,
              let meters = routeDistanceMeters, meters > 0,
              let rate = parseDouble(rateText), rate > 0 else {
            rateComparison = nil
            rateCompareError = nil
            return
        }
        let miles = Double(meters) / 1609.34
        let key = "\(oState)|\(dState)|\(Int(miles))|\(Int(rate))|\(cargoType.rawValue)"
        guard key != lastRateCompareKey else { return }
        lastRateCompareKey = key
        isComparingRate = true
        rateCompareError = nil
        Task {
            do {
                let r = try await EusoTripAPI.shared.rates.compareLaneRate(
                    originState: oState,
                    destState:   dState,
                    rate:        rate,
                    distance:    miles,
                    cargoType:   cargoType.rawValue,
                    lookbackDays: 90
                )
                await MainActor.run {
                    self.rateComparison = r
                    self.isComparingRate = false
                }
            } catch {
                await MainActor.run {
                    self.rateCompareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isComparingRate = false
                }
            }
        }
    }

    // MARK: - ERG (Emergency Response Guidebook) lookup

    /// Fires `erg.searchByUN` when the user types a 4-digit UN
    /// number. Auto-populates hazmat class + proper shipping name +
    /// ERG guide on a successful match. Web parity with the
    /// platform's ERG database — same router (`erg.searchByUN`).
    private func lookupERGIfReady() {
        let raw = unNumber.uppercased()
            .replacingOccurrences(of: "UN", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Server requires at least 4 digits to lookup. Bail otherwise.
        guard raw.count >= 4, raw.allSatisfy(\.isNumber) else {
            ergMatch = nil
            ergLookupError = nil
            return
        }
        let key = raw
        guard key != lastErgQueryKey else { return }
        lastErgQueryKey = key
        isLookingUpERG = true
        ergLookupError = nil
        Task {
            do {
                let detail = try await EusoTripAPI.shared.erg.searchByUN(raw)
                await MainActor.run {
                    self.isLookingUpERG = false
                    if detail.found {
                        self.ergMatch = detail
                        // Auto-populate ONLY when the user hasn't
                        // already typed a value — never overwrite
                        // explicit entry.
                        if hazmatClass.isEmpty, let cls = detail.hazardClass {
                            hazmatClass = cls
                        }
                        if properShippingName.isEmpty, let name = detail.name {
                            properShippingName = name.uppercased()
                        }
                    } else {
                        self.ergMatch = nil
                        self.ergLookupError = "UN\(raw) not found in ERG"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLookingUpERG = false
                    self.ergLookupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    /// Apply a search-hit selection from the ERG search sheet —
    /// prefills UN + class + shipping name; the subsequent
    /// `erg.searchByUN` finishes hydrating the full match.
    private func applyERGHit(_ hit: ErgAPI.SearchHit) {
        unNumber = hit.unNumber
        hazmatClass = hit.hazardClass
        properShippingName = hit.placardName.isEmpty ? hit.name.uppercased() : hit.placardName
        showErgSearchSheet = false
    }

    /// `erg.search` typeahead — debounced inside the search sheet
    /// onSubmit / commit, fired with the current `ergSearchQuery`.
    private func searchERG() {
        let q = ergSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            ergSearchHits = []
            return
        }
        isSearchingERG = true
        Task {
            do {
                let resp = try await EusoTripAPI.shared.erg.search(query: q, limit: 12)
                await MainActor.run {
                    self.ergSearchHits = resp.results
                    self.isSearchingERG = false
                }
            } catch {
                await MainActor.run {
                    self.ergSearchHits = []
                    self.isSearchingERG = false
                }
            }
        }
    }

    /// Resolved geocode hit — coordinate + state code. Used by both
    /// the routing step (needs lat/lng) and the rate compare step
    /// (needs state code).
    private struct ResolvedAddress {
        let coord: CLLocationCoordinate2D
        let stateCode: String?
    }

    /// Returns a resolved address for the given typed text. Uses
    /// cached lat/lng (set by the address field on suggestion-tap)
    /// when both are present; otherwise forward-geocodes via the
    /// EusoTrip routing backend. State code is sourced from the
    /// geocode hit's address payload.
    private func ensureResolved(
        text: String,
        cachedLat: Double?,
        cachedLng: Double?
    ) async throws -> ResolvedAddress {
        if let lat = cachedLat, let lng = cachedLng {
            // Reverse-geocode for the state code — the lat/lng might
            // have been pasted directly, so we still need a state
            // resolution for the rate compare. Best-effort; falls
            // back to nil stateCode which compareLaneRate accepts.
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let state = try? await HereGeocodingClient.shared
                .reverseGeocode(at: coord, limit: 1)
                .first?
                .address.stateCode
            return ResolvedAddress(coord: coord, stateCode: state ?? nil)
        }
        let hits = try await HereGeocodingClient.shared.geocode(query: text, limit: 1)
        guard let first = hits.first else {
            throw HereMapsError.providerError("No geocode result for '\(text)'")
        }
        return ResolvedAddress(
            coord: CLLocationCoordinate2D(latitude: first.position.lat, longitude: first.position.lng),
            stateCode: first.address.stateCode
        )
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SCHEDULE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                pickupTile
                deliveryTile
            }
        }
    }

    private var pickupTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("PICKUP")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 4)
                // The "Schedule" label was inside the Toggle's title
                // string and `.labelsHidden()` failed to hide it
                // under dynamic type, so the founder saw "Sched-\nule"
                // wrap inside a tiny pill on the Post Load screen
                // (2026-05-05). Splitting the label out as a sibling
                // Text + passing an empty title to Toggle bypasses
                // both the label-hidden bug and the wrap.
                Text("SCHEDULE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Toggle("", isOn: $hasPickupDate.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                    .toggleStyle(GradientToggleStyle())
                    .labelsHidden()
            }
            if hasPickupDate {
                DatePicker("Pickup", selection: $pickupDate, in: Date()..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(LinearGradient.diagonal)
                    .disabled(isSubmitting)
            } else {
                Text("Catalyst proposes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Leave blank or schedule")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var deliveryTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DELIVERY")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            // Real ETA when both pickup is set + HERE returned a
            // duration. Falls back to honest copy otherwise.
            if let eta = computedDeliveryETA {
                Text(deliveryETAFormatter.string(from: eta))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG-routed · pickup + lane")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else if hasPickupDate && isRouting {
                Text("Computing…")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("ESANG-routed")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else if hasPickupDate {
                Text("Add addresses")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Type or pick a suggestion")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            } else {
                Text("Catalyst proposes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Set after pickup is scheduled")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - Step 2: EQUIPMENT

    @ViewBuilder
    private var equipmentStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            cargoTypePicker
            equipmentTypePicker
            weightField
            equipmentPreviewSection
            equipmentSubform
        }
    }

    /// Equipment-type picker — covers truck / rail / vessel
    /// verticals + every product type (dry van, reefer, flatbed,
    /// step deck, conestoga, container, tanker variants, power-only,
    /// oversized, rail TOFC/COFC/intermodal, vessel container/bulk/
    /// tanker). Web parity with the LoadEquipmentType enum on the
    /// server (serialized to `equipmentType` on `shippers.create`).
    private var equipmentTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("EQUIPMENT TYPE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(equipmentType.vertical.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EquipmentChoice.allCases) { choice in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                equipmentType = choice
                            }
                        } label: {
                            equipmentChip(for: choice)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func equipmentChip(for choice: EquipmentChoice) -> some View {
        let on = (equipmentType == choice)
        HStack(spacing: 6) {
            Image(systemName: choice.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(choice.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    /// Cargo-type-specific equipment subform. Web parity (founder ask
    /// 2026-05-07): hazmat tanker needs hose specs / fittings; reefer
    /// needs temp range + pre-cool flag; flatbed needs straps / tarps;
    /// chemicals + gas + petroleum extend the hazmat shape.
    /// State lives on @State vars below — they all flow into the
    /// `shippers.create` payload at submit time so the catalyst's
    /// driver knows what gear they need.
    @ViewBuilder
    private var equipmentSubform: some View {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            tankerSubform
        case .reefer:
            reeferSubform
        case .flatbed, .stepDeck, .conestoga, .oversized:
            flatbedSubform
        default:
            EmptyView()
        }
    }

    // MARK: tanker subform (hazmat / petroleum / chemicals / gas / liquid)

    @ViewBuilder
    private var tankerSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(cargoType == .hazmat || cargoType == .petroleum
                     ? "TANKER · HAZMAT REQUIREMENTS"
                     : "TANKER REQUIREMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            // Hose configuration — driver/catalyst needs to know what
            // fittings + diameter to bring. Stored in `notes` on the
            // load envelope until the backend ships a structured
            // tanker spec field.
            HStack(spacing: 8) {
                tankerChip(label: "2\" cam-lock",     selected: tankerHoseSpec == "2_camlock")
                tankerChip(label: "3\" cam-lock",     selected: tankerHoseSpec == "3_camlock")
                tankerChip(label: "4\" cam-lock",     selected: tankerHoseSpec == "4_camlock")
                tankerChip(label: "Dry-disconnect",   selected: tankerHoseSpec == "dry_disconnect")
            }
            HStack(spacing: 8) {
                tankerChip(label: "API adapter",       selected: tankerFitting == "api")
                tankerChip(label: "TTMA",              selected: tankerFitting == "ttma")
                tankerChip(label: "Other",             selected: tankerFitting == "other")
                Spacer(minLength: 0)
            }
            // UN / hazmat fields surface only for the hazmat/petroleum
            // / chemicals branches (gas + liquid are food-grade or
            // non-hazmat liquids). Mirrors the web Hazmat subform.
            if cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals {
                Divider().background(palette.borderFaint).padding(.vertical, 2)
                tankerHazmatRow
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private var tankerHazmatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("HAZMAT · 49 CFR 172")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // ERG search button — opens a typeahead sheet so the
                // user can find any UN material by name when they
                // don't know the number. Web parity with the
                // platform's `erg.search`.
                Button { showErgSearchSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9, weight: .heavy))
                        Text("ERG search")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    }
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "UN", text: $unNumber, placeholder: "UN1267", width: 90)
                hazmatTextField(label: "Class", text: $hazmatClass, placeholder: "3", width: 80)
                hazmatTextField(label: "PG", text: $packingGroup, placeholder: "II", width: 70)
            }
            hazmatTextField(label: "Proper shipping name",
                            text: $properShippingName,
                            placeholder: "Crude oil",
                            width: nil)
            // Live ERG match chip — prefilled by `erg.searchByUN`.
            if isLookingUpERG {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).tint(LinearGradient.diagonal)
                    Text("Looking up UN in ERG database…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            } else if let m = ergMatch, m.found {
                ergMatchChip(m)
            } else if let err = ergLookupError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    /// Compact "ERG matched" chip — material name + guide # + TIH /
    /// water-reactive flags. Tapping opens the existing 096 ERG
    /// detail surface for the full guide page.
    @ViewBuilder
    private func ergMatchChip(_ m: ErgAPI.MaterialDetail) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text((m.name ?? "—").capitalized)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if m.isTIH == true {
                        Text("TIH")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.danger))
                    }
                    if m.isWR == true {
                        Text("WR")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.info))
                    }
                }
                Text(ergMatchSubtitle(m))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func ergMatchSubtitle(_ m: ErgAPI.MaterialDetail) -> String {
        var bits: [String] = []
        if let g = m.guideNumber { bits.append("Guide \(g)") }
        if let c = m.hazardClass { bits.append("Class \(c)") }
        if let p = m.placard, !p.isEmpty { bits.append(p) }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder
    private func tankerChip(label: String, selected: Bool) -> some View {
        Button {
            toggleTankerSpec(label: label)
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft)))
                .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleTankerSpec(label: String) {
        let key: String
        switch label {
        case "2\" cam-lock":     key = "2_camlock"
        case "3\" cam-lock":     key = "3_camlock"
        case "4\" cam-lock":     key = "4_camlock"
        case "Dry-disconnect":   key = "dry_disconnect"
        case "API adapter":      key = "api"
        case "TTMA":             key = "ttma"
        case "Other":            key = "other"
        default:                 return
        }
        if ["2_camlock", "3_camlock", "4_camlock", "dry_disconnect"].contains(key) {
            tankerHoseSpec = (tankerHoseSpec == key) ? "" : key
        } else {
            tankerFitting = (tankerFitting == key) ? "" : key
        }
    }

    @ViewBuilder
    private func hazmatTextField(label: String,
                                 text: Binding<String>,
                                 placeholder: String,
                                 width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .tint(LinearGradient.diagonal)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: reefer subform

    @ViewBuilder
    private var reeferSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.snowflake")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("REEFER REQUIREMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                reeferTempField(label: "LOW °F",  binding: $reeferTempLowText,  placeholder: "33")
                reeferTempField(label: "HIGH °F", binding: $reeferTempHighText, placeholder: "40")
            }
            Toggle("Pre-cool required",
                   isOn: $preCoolRequired.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                .toggleStyle(GradientToggleStyle())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Toggle("Continuous mode",
                   isOn: $continuousMode.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                .toggleStyle(GradientToggleStyle())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func reeferTempField(label: String,
                                 binding: Binding<String>,
                                 placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 4) {
                TextField(placeholder, text: binding)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 60)
                Text("°F")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    // MARK: flatbed subform

    @ViewBuilder
    private var flatbedSubform: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FLATBED · OVERSIZED REQUIREMENTS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                flatbedFlag(title: "Straps", selected: flatbedStraps)
                    .onTapGesture { flatbedStraps.toggle() }
                flatbedFlag(title: "Tarps", selected: flatbedTarps)
                    .onTapGesture { flatbedTarps.toggle() }
                flatbedFlag(title: "Chains", selected: flatbedChains)
                    .onTapGesture { flatbedChains.toggle() }
                flatbedFlag(title: "Edge protectors", selected: flatbedEdgeProtectors)
                    .onTapGesture { flatbedEdgeProtectors.toggle() }
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "Length (ft)", text: $oversizeLengthText, placeholder: "53", width: 110)
                hazmatTextField(label: "Width (ft)",  text: $oversizeWidthText,  placeholder: "8.5", width: 110)
            }
            HStack(spacing: 8) {
                hazmatTextField(label: "Height (ft)", text: $oversizeHeightText, placeholder: "13.5", width: 110)
                Toggle("Permits required",
                       isOn: $oversizePermits.animation(.spring(response: 0.22, dampingFraction: 0.85)))
                    .toggleStyle(GradientToggleStyle())
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func flatbedFlag(title: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            Text(title)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(selected ? AnyShapeStyle(palette.textPrimary) : AnyShapeStyle(palette.textSecondary))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(palette.bgCardSoft))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var cargoTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CARGO TYPE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShipperAPI.CargoType.allCases) { type in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                cargoType = type
                            }
                        } label: {
                            cargoChip(for: type)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func cargoChip(for type: ShipperAPI.CargoType) -> some View {
        let on = (cargoType == type)
        HStack(spacing: 6) {
            Image(systemName: type.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(type.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEIGHT")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $weightText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                Text("lbs")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var equipmentPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQUIPMENT · PREVIEW")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                glyph(for: cargoType)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cargoType.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(equipmentSpecText)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(equipmentNoteText)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    @ViewBuilder
    private func glyph(for type: ShipperAPI.CargoType) -> some View {
        let lower = type.label.lowercased()
        if type.label.lowercased() == "hazmat" || lower.contains("petroleum") || lower.contains("chemicals") || lower.contains("liquid") || lower.contains("gas") || lower.contains("cryogenic") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(45))
                Text("3")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xB27300))
                    .offset(y: 4)
            }
        } else if lower.contains("refrigerated") || lower.contains("food") {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Brand.info, lineWidth: 2)
                    .frame(width: 30, height: 24)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: type.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    /// Equipment spec hint — DYNAMIC. Reads the live ERG match and
    /// user-entered UN/Class/PG when present; falls back to the
    /// equipment-type default + cargo-type default. Founder bug
    /// 2026-05-07 (screenshot): preview was hardcoded to "MC-306 ·
    /// UN1203 · PG II" while the user had typed UN1267 / Crude Oil
    /// — preview now reflects what the user actually entered.
    private var equipmentSpecText: String {
        // 1. Hazmat case → derive from ERG match + user fields.
        if let m = ergMatch, m.found, let un = m.unNumber {
            let cls = (m.hazardClass ?? hazmatClass).isEmpty ? "—" : (m.hazardClass ?? hazmatClass)
            let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
            let hose = tankerHoseSpec.isEmpty ? "" : " · \(hoseLabel(tankerHoseSpec))"
            return "UN\(un) · Class \(cls)\(pg)\(hose)"
        }
        // 2. User has typed a UN but ERG hasn't matched yet — show
        //    what they typed honestly.
        let typedUN = unNumber.uppercased().replacingOccurrences(of: "UN", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedUN.isEmpty {
            let cls = hazmatClass.isEmpty ? "—" : hazmatClass
            let pg  = packingGroup.isEmpty ? "" : " · PG \(packingGroup)"
            return "UN\(typedUN) · Class \(cls)\(pg)\(isLookingUpERG ? " · looking up…" : "")"
        }
        // 3. Equipment type drives the spec when no UN entered yet.
        switch equipmentType {
        case .tankerHazmat:    return "MC-306 · awaiting UN"
        case .tankerPetro:     return "MC-306 · petroleum"
        case .tankerLiquid:    return "MC-307 · food-grade liner"
        case .tankerGas:       return "MC-331 · gas / cryo"
        case .reefer:          return reeferTempLowText.isEmpty
                                       ? "53′ Reefer · spec pending"
                                       : "53′ Reefer · \(reeferTempLowText)–\(reeferTempHighText)°F"
        case .flatbed:         return "Flatbed · 48′/53′ · standard"
        case .stepDeck:        return "Step deck · 48′/53′"
        case .conestoga:       return "Conestoga · curtain-side"
        case .container:       return "20′ / 40′ / 53′ ISO container"
        case .oversized:       return oversizeDimsText.contains("—") ? "Oversized · dims pending" : oversizeDimsText
        case .powerOnly:       return "Power-only · driver bring own trailer"
        case .railTOFC:        return "Rail · TOFC (trailer-on-flatcar)"
        case .railCOFC:        return "Rail · COFC (container-on-flatcar)"
        case .railIntermodal:  return "Rail · intermodal container"
        case .vesselContainer: return "Vessel · ISO container"
        case .vesselBulk:      return "Vessel · bulk hold"
        case .vesselTanker:    return "Vessel · tanker"
        case .dryVan:          return "53′ Dry Van · standard"
        }
    }

    private var equipmentNoteText: String {
        // ERG match drives the safety-note line when present.
        if let m = ergMatch, m.found {
            var bits: [String] = []
            if let g = m.guideNumber { bits.append("ERG Guide \(g)") }
            if m.isTIH == true        { bits.append("⚠ Toxic-by-inhalation") }
            if m.isWR  == true        { bits.append("⚠ Water-reactive") }
            if let n = m.name, !n.isEmpty { bits.append(n.capitalized) }
            return bits.isEmpty ? "CHEMTREC +1-800-424-9300" : bits.joined(separator: " · ")
        }
        if let err = ergLookupError, !err.isEmpty {
            return err
        }
        switch cargoType.label.lowercased() {
        case "hazmat", "petroleum", "chemicals", "gas", "cryogenic":
            return "CHEMTREC +1-800-424-9300 · enter UN to load ERG"
        case "refrigerated", "food_grade", "food grade":
            return "Continuous temp logging · last-load-out check"
        case "intermodal":
            return "Chassis pool · per diem after free time"
        default:
            return "Standard tender · no special notes"
        }
    }

    // MARK: - Step 3: PRICING

    @ViewBuilder
    private var pricingStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            rateField
            targetRateCard
            notesField
        }
    }

    private var rateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POSTED RATE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 18)
                TextField("0", text: $rateText)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .keyboardType(.decimalPad)
                    .disabled(isSubmitting)
                Text("USD")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    /// ESANG AI rate-vs-market meter — replaces the prior stub
    /// "estimate vs spot" copy. Wired to `rates.compareLaneRate`
    /// (web-parity surface) and renders:
    ///   • Position pill: BELOW MARKET / AT MARKET / ABOVE MARKET
    ///     (color-coded against Brand.success / .info / .warning)
    ///   • Position rating: poor / fair / good / excellent based on
    ///     percentile bands (≤25 / 26-50 / 51-80 / 81+)
    ///   • Range bar: market min — your rate — market max
    ///   • RPM line: your $/mi vs market avg $/mi · sample size
    ///   • Recommendation copy from the server
    /// Surfaces the empty/loading/error states honestly.
    @ViewBuilder
    private var targetRateCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · RATE VS MARKET")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if let cmp = rateComparison {
                    Text(cmp.source == "national_benchmark" ? "national" : "platform")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if isComparingRate {
                Text("Comparing your rate against the lane…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if let err = rateCompareError {
                Text("Rate compare error: \(err)")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            } else if let cmp = rateComparison {
                rateMeterBody(cmp)
            } else if (parseDouble(rateText) ?? 0) <= 0 {
                Text("Add posted rate to see ESANG market position")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if originStateCode == nil || destStateCode == nil {
                Text("Resolving lane states for market compare…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if let routeErr = routingError {
                // Route call failed — surface here too so the user
                // doesn't see a stuck "computing distance" state on
                // step 3 with no path to recover. Mirrors the route
                // meta strip on step 1.
                Text("Route error: \(routeErr) — go back to step 1 to retry")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if (routeDistanceMeters ?? 0) <= 0 {
                Text("Distance computing — meter populates after route resolves")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(rateComparison == nil ? 0.25 : 0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    @ViewBuilder
    private func rateMeterBody(_ cmp: RatesAPI.LaneComparison) -> some View {
        let (positionLabel, positionColor) = positionStyling(for: cmp.position)
        let (ratingLabel, ratingColor) = ratingStyling(percentile: cmp.percentile,
                                                        position: cmp.position)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(dollars(cmp.yourRate))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "$%.2f / mi", cmp.yourRPM))
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(positionLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(positionColor))
            }
            // Range bar: market min -- your rate marker -- market max
            rateRangeBar(cmp: cmp)
            HStack(spacing: Space.s2) {
                Text(ratingLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(ratingColor))
                Text("\(cmp.percentile)th percentile · n=\(cmp.sampleSize)")
                    .font(EType.caption).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            Text(cmp.recommendation)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func rateRangeBar(cmp: RatesAPI.LaneComparison) -> some View {
        // Map yourRPM into [min, max] range for the marker offset.
        let lo = cmp.marketMinRPM
        let hi = cmp.marketMaxRPM
        let v  = cmp.yourRPM
        // Clamp + normalize. If hi == lo (rare), draw the marker
        // centered.
        let pct: Double = {
            guard hi > lo else { return 0.5 }
            let raw = (v - lo) / (hi - lo)
            return min(1.0, max(0.0, raw))
        }()
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Brand.success, Brand.info, Brand.warning],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2))
                    .offset(x: max(0, geo.size.width * pct - 8))
            }
        }
        .frame(height: 18)
        HStack {
            Text(String(format: "$%.2f / mi · min", lo))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
            Spacer(minLength: 0)
            Text(String(format: "$%.2f / mi · avg", cmp.marketAvgRPM))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
            Spacer(minLength: 0)
            Text(String(format: "$%.2f / mi · max", hi))
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    /// Server emits position uppercase like "ABOVE_MARKET". Map to
    /// human label + color for the pill.
    private func positionStyling(for raw: String) -> (String, Color) {
        switch raw.uppercased() {
        case "ABOVE_MARKET": return ("ABOVE MARKET", Brand.warning)
        case "BELOW_MARKET": return ("BELOW MARKET", Brand.info)
        case "AT_MARKET":    return ("AT MARKET",    Brand.success)
        default:             return (raw,            Brand.neutral)
        }
    }

    /// ESANG AI quality rating from the percentile + position. The
    /// shipper's posted rate is "excellent" for them when it's at
    /// or below the lane's midpoint (saves them money) and "poor"
    /// when it's at the high end (carrier-favorable, shipper pays
    /// more than they need to). Position label still flips the
    /// shipper-vs-carrier framing in the pill above.
    private func ratingStyling(percentile: Int, position: String) -> (String, Color) {
        // For shippers: lower rate = better deal. Percentile ≤25
        // means your rate is in the bottom quartile of comparable
        // lanes — excellent for the shipper. ≥80th percentile is
        // poor (overpaying). The middle bands: 26-50 = good, 51-79
        // = fair.
        switch percentile {
        case 0...25:  return ("EXCELLENT", Brand.success)
        case 26...50: return ("GOOD",      Brand.info)
        case 51...79: return ("FAIR",      Brand.warning)
        default:      return ("POOR",      Brand.danger)
        }
    }
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES (OPTIONAL)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField(
                "Anything carriers should know — temperature ranges, dock hours, COI…",
                text: $notes,
                axis: .vertical
            )
            .font(EType.body)
            .foregroundStyle(palette.textPrimary)
            .tint(LinearGradient.diagonal)
            .lineLimit(3...6)
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .disabled(isSubmitting)
        }
    }

    // MARK: - Step 4: REVIEW

    @ViewBuilder
    private var reviewStepBody: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            eusoTicketTypeBanner
            reviewSummaryCard
            equipmentReviewCard
            esangMarketReviewCard
        }
    }

    /// Banner showing what EusoTicket the load will generate. Web
    /// parity: the wizard data IS the EusoTicket. BOL for general
    /// freight, Run Ticket for crude oil / hazmat / petroleum tanker
    /// (per-haul measurement), Haul Receipt for the post-POD copy.
    /// Driver views the same record via 106B; shipper via 303 / 304 /
    /// 305.
    private var eusoTicketTypeBanner: some View {
        let (kind, blurb, icon) = eusoTicketKindForCurrentSelection
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Will generate · \(kind)")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(blurb)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// Resolves the EusoTicket kind based on current selections.
    /// Crude oil / hazmat / petroleum / chemicals tankers and bulk-
    /// liquid loads → Run Ticket (per-haul measurement). Everything
    /// else → BOL. Haul Receipt is generated POST-POD by the carrier
    /// — not chosen here.
    private var eusoTicketKindForCurrentSelection: (kind: String, blurb: String, icon: String) {
        let isTanker = [EquipmentChoice.tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker].contains(equipmentType)
        let isHazmat = cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals || cargoType == .gas
        if isTanker || isHazmat {
            return (
                kind: "Run Ticket",
                blurb: "Per-haul measurement record. Driver + shipper view the same EusoTicket. Required for crude / hazmat / tanker.",
                icon: "drop.triangle.fill"
            )
        }
        return (
            kind: "BOL · Bill of Lading",
            blurb: "Standard bill of lading. Acts as the receipt + chain-of-custody record. Driver + shipper view the same EusoTicket.",
            icon: "doc.richtext.fill"
        )
    }

    private var reviewSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("LANE")
            reviewRow(label: "Origin",      value: nonEmpty(origin))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Destination", value: nonEmpty(destination))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Distance",    value: distanceReviewText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Pickup",      value: hasPickupDate ? formatDate(pickupDate) : "Catalyst proposes")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Delivery ETA", value: deliveryReviewText)

            reviewSection("CARGO + EQUIPMENT")
            reviewRow(label: "Cargo type",     value: cargoType.label)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Equipment",      value: equipmentType.label)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Vertical",       value: equipmentType.vertical.uppercased())
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Weight",         value: parseDouble(weightText).map { "\(Int($0)) lbs" } ?? "—")

            reviewSection("FREIGHT CHARGE")
            reviewRow(label: "Posted rate",    value: parseDouble(rateText).map(dollars) ?? "—", isHero: true)
            if let cmp = rateComparison {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Vs market",  value: "\(cmp.position.replacingOccurrences(of: "_", with: " ")) · \(cmp.percentile)th pct")
            }

            if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reviewSection("NOTES")
                reviewRow(label: "Free-form",  value: notes)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    /// Shows the equipment-specific subform fields only when the
    /// selection actually has a subform (tanker / reefer / flatbed).
    /// Otherwise renders nothing — keeps step 4 honest about what
    /// data is in the record.
    @ViewBuilder
    private var equipmentReviewCard: some View {
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            tankerReviewCard
        case .reefer:
            reeferReviewCard
        case .flatbed, .stepDeck, .conestoga, .oversized:
            flatbedReviewCard
        default:
            EmptyView()
        }
    }

    private var tankerReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("TANKER REQUIREMENTS")
            reviewRow(label: "Hose spec",      value: hoseLabel(tankerHoseSpec))
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Fitting",        value: fittingLabel(tankerFitting))
            if cargoType == .hazmat || cargoType == .petroleum || cargoType == .chemicals {
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "UN",             value: nonEmpty(unNumber))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Hazmat class",   value: nonEmpty(hazmatClass))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Packing group",  value: nonEmpty(packingGroup))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Shipping name",  value: nonEmpty(properShippingName))
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var reeferReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("REEFER REQUIREMENTS")
            reviewRow(label: "Temp range", value: reeferTempRangeText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Pre-cool",   value: preCoolRequired ? "Required" : "Not required")
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Mode",       value: continuousMode ? "Continuous" : "Cycling")
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var flatbedReviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviewSection("FLATBED · OVERSIZED REQUIREMENTS")
            reviewRow(label: "Securing",    value: flatbedGearText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Dimensions",  value: oversizeDimsText)
            Divider().overlay(palette.borderFaint)
            reviewRow(label: "Permits",     value: oversizePermits ? "Required" : "Not required")
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    /// ESANG market meter reprised on the review step so the shipper
    /// sees their final price posture before submitting.
    @ViewBuilder
    private var esangMarketReviewCard: some View {
        if let cmp = rateComparison {
            VStack(alignment: .leading, spacing: 0) {
                reviewSection("ESANG · RATE VS MARKET")
                reviewRow(label: "Position",   value: cmp.position.replacingOccurrences(of: "_", with: " "))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Your $/mi",  value: String(format: "$%.2f", cmp.yourRPM))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Market avg", value: String(format: "$%.2f / mi", cmp.marketAvgRPM))
                Divider().overlay(palette.borderFaint)
                reviewRow(label: "Percentile", value: "\(cmp.percentile)th · n=\(cmp.sampleSize)")
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func reviewSection(_ title: String) -> some View {
        Text(title)
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, 6)
    }

    private func reviewRow(label: String, value: String, isHero: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(isHero ? .system(size: 22, weight: .bold) : EType.bodyStrong)
                .foregroundStyle(isHero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var distanceReviewText: String {
        guard let m = routeDistanceMeters, m > 0 else {
            if let err = routingError { return "error: \(err)" }
            return "—"
        }
        return String(format: "%.0f mi", Double(m) / 1609.34)
    }

    private var deliveryReviewText: String {
        if let eta = computedDeliveryETA {
            return deliveryETAFormatter.string(from: eta)
        }
        if hasPickupDate { return "—" }
        return "Catalyst proposes"
    }

    private var reeferTempRangeText: String {
        let lo = reeferTempLowText.trimmingCharacters(in: .whitespaces)
        let hi = reeferTempHighText.trimmingCharacters(in: .whitespaces)
        if lo.isEmpty && hi.isEmpty { return "—" }
        return "\(lo.isEmpty ? "—" : lo)°F – \(hi.isEmpty ? "—" : hi)°F"
    }

    private var flatbedGearText: String {
        var gear: [String] = []
        if flatbedStraps          { gear.append("straps") }
        if flatbedTarps           { gear.append("tarps") }
        if flatbedChains          { gear.append("chains") }
        if flatbedEdgeProtectors  { gear.append("edge protectors") }
        return gear.isEmpty ? "—" : gear.joined(separator: ", ")
    }

    private var oversizeDimsText: String {
        let l = oversizeLengthText.trimmingCharacters(in: .whitespaces)
        let w = oversizeWidthText.trimmingCharacters(in: .whitespaces)
        let h = oversizeHeightText.trimmingCharacters(in: .whitespaces)
        if l.isEmpty && w.isEmpty && h.isEmpty { return "—" }
        return "L \(l.isEmpty ? "—" : l) · W \(w.isEmpty ? "—" : w) · H \(h.isEmpty ? "—" : h) ft"
    }

    private func hoseLabel(_ raw: String) -> String {
        switch raw {
        case "2_camlock":     return "2\" cam-lock"
        case "3_camlock":     return "3\" cam-lock"
        case "4_camlock":     return "4\" cam-lock"
        case "dry_disconnect":return "Dry-disconnect"
        case "":              return "—"
        default:              return raw
        }
    }

    private func fittingLabel(_ raw: String) -> String {
        switch raw {
        case "api":   return "API adapter"
        case "ttma":  return "TTMA"
        case "other": return "Other"
        case "":      return "—"
        default:      return raw
        }
    }

    private func nonEmpty(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: d)
    }

    // MARK: - Banners

    private func successBanner(_ ack: ShipperAPI.PostLoadAck) -> some View {
        let kind = eusoTicketKindForCurrentSelection.kind
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Load posted · \(kind) generated")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(loadNumberSubtitle(ack))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                Text("Driver views the same EusoTicket from their Loads tab.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { withAnimation { lastSuccess = nil } } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadNumberSubtitle(_ ack: ShipperAPI.PostLoadAck) -> String {
        let trimmed = ack.loadNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Bids will land in your Bids inbox." }
        return "\(trimmed) · bids will land in your Bids inbox."
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't post that load")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { store.reset() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Continue / Submit CTA

    private var continueOrSubmitCTA: some View {
        Button(action: continueOrSubmit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if step == .review {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(ctaText)
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Capsule().fill(canAdvance
                               ? AnyShapeStyle(LinearGradient.primary)
                               : AnyShapeStyle(palette.tintNeutral.opacity(0.4)))
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .accessibilityLabel(ctaText)
    }

    private var ctaText: String {
        if case .success = store.phase, step == .review { return "Post another" }
        if step == .review {
            return isSubmitting ? "Posting…" : "Post this load"
        }
        guard let next = step.next else { return "Continue" }
        return "Continue · Step \(next.rawValue) of \(PostLoadStep.allCases.count) →"
    }

    private var canAdvance: Bool {
        if isSubmitting { return false }
        switch step {
        case .lane:
            let oTrim = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            let dTrim = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            return !oTrim.isEmpty && !dTrim.isEmpty
        case .equipment, .pricing, .review:
            return true
        }
    }

    private func continueOrSubmit() {
        if step == .review {
            if case .success = store.phase {
                resetForm()
                store.reset()
                step = .lane
                return
            }
            Task { await submit() }
        } else if let next = step.next {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                step = next
            }
        }
    }

    // MARK: - Submit pipeline (preserved verbatim)

    private var isSubmitting: Bool {
        if case .submitting = store.phase { return true }
        return false
    }

    private func submit() async {
        let pickupISO = hasPickupDate ? isoDate(pickupDate) : nil
        let weight    = parseDouble(weightText)
        let rate      = parseDouble(rateText)
        // Pack equipment-type + subform spec into the `notes` field
        // so the catalyst's dispatcher / driver gets the full
        // requirements at dispatch time. Server schema doesn't yet
        // have structured tanker / reefer / flatbed columns; web
        // parity at the application layer.
        let composedNotes = composeSubmissionNotes()
        await store.submit(
            origin: origin,
            destination: destination,
            cargoType: cargoType,
            rate: rate,
            weight: weight,
            notes: composedNotes,
            pickupDate: pickupISO,
            originLat: originLat,
            originLng: originLng,
            destLat: destLat,
            destLng: destLng
        )
        if case .success(let ack) = store.phase {
            self.lastSuccess = ack
            resetForm()
        }
    }

    /// Concatenates equipment + subform fields into a single notes
    /// string. Web parity — the catalyst's load-detail surface
    /// surfaces these as a "REQUIREMENTS" block under the BOL.
    /// Always prepends the user's free-form notes if non-empty.
    private func composeSubmissionNotes() -> String {
        var lines: [String] = []
        if !notes.isEmpty { lines.append(notes) }
        lines.append("Equipment: \(equipmentType.label) [\(equipmentType.rawValue)] · vertical=\(equipmentType.vertical)")
        switch equipmentType {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas, .vesselTanker:
            if !tankerHoseSpec.isEmpty { lines.append("Tanker hose: \(tankerHoseSpec)") }
            if !tankerFitting.isEmpty  { lines.append("Tanker fitting: \(tankerFitting)") }
            if !unNumber.isEmpty       { lines.append("UN: \(unNumber)") }
            if !hazmatClass.isEmpty    { lines.append("Hazmat class: \(hazmatClass)") }
            if !packingGroup.isEmpty   { lines.append("Packing group: \(packingGroup)") }
            if !properShippingName.isEmpty { lines.append("Proper shipping name: \(properShippingName)") }
        case .reefer:
            if !reeferTempLowText.isEmpty || !reeferTempHighText.isEmpty {
                lines.append("Reefer temp: \(reeferTempLowText)–\(reeferTempHighText)°F")
            }
            lines.append("Pre-cool: \(preCoolRequired ? "yes" : "no") · Continuous: \(continuousMode ? "yes" : "no")")
        case .flatbed, .stepDeck, .conestoga, .oversized:
            var gear: [String] = []
            if flatbedStraps          { gear.append("straps") }
            if flatbedTarps           { gear.append("tarps") }
            if flatbedChains          { gear.append("chains") }
            if flatbedEdgeProtectors  { gear.append("edge protectors") }
            if !gear.isEmpty { lines.append("Securing: \(gear.joined(separator: ", "))") }
            if !oversizeLengthText.isEmpty || !oversizeWidthText.isEmpty || !oversizeHeightText.isEmpty {
                lines.append("Dimensions: L=\(oversizeLengthText) W=\(oversizeWidthText) H=\(oversizeHeightText) ft")
            }
            if oversizePermits { lines.append("Permits required") }
        default:
            break
        }
        return lines.joined(separator: "\n")
    }

    private func resetForm() {
        origin = ""
        destination = ""
        originLat = nil; originLng = nil
        destLat   = nil; destLng   = nil
        cargoType = .general
        equipmentType = .dryVan
        hasPickupDate = false
        pickupDate = Date()
        weightText = ""
        rateText = ""
        notes = ""
        unNumber = ""
        hazmatClass = ""
        packingGroup = ""
        properShippingName = ""
        tankerHoseSpec = ""
        tankerFitting = ""
        reeferTempLowText = ""
        reeferTempHighText = ""
        preCoolRequired = false
        continuousMode = true
        flatbedStraps = false
        flatbedTarps = false
        flatbedChains = false
        flatbedEdgeProtectors = false
        oversizeLengthText = ""
        oversizeWidthText = ""
        oversizeHeightText = ""
        oversizePermits = false
        ergMatch = nil
        ergLookupError = nil
        rateComparison = nil
        routeDistanceMeters = nil
        routeDurationSeconds = nil
        // Wipe autosave so the next user doesn't see stale draft.
        clearDraft()
    }

    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperPostLoadDismiss = Notification.Name("eusoShipperPostLoadDismiss")
}

// MARK: - Screen wrapper

struct ShipperPostLoadScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperPostLoad()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_204(),
                trailing: shipperNavTrailing_204(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — out of scope per parity mandate §1.
private func shipperNavLeading_204() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                              isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle.fill",   isCurrent: true)]
}

private func shipperNavTrailing_204() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews

#Preview("204 · Shipper · Post Load · Night") {
    ShipperPostLoadScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("204 · Shipper · Post Load · Afternoon") {
    ShipperPostLoadScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
