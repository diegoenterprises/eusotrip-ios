//
//  PostLoadDraft.swift
//  EusoTrip — Shipper · Post-a-Load wizard shared state.
//
//  Threaded through 250–259 wizard steps. The 4-step canonical flow
//  (Lane → Equipment → Pricing → Review) reads + writes one draft;
//  sub-forms (multi-stop · hazmat · reefer) bind to the same draft so
//  there's one source of truth and one final `shippers.create` call.
//
//  No mocks: all field defaults are nil / empty so a partially-filled
//  draft renders em-dash sentinels until the shipper supplies the
//  field. Validation runs on each Next-button press and surfaces a
//  real inline error per field.
//

import SwiftUI

// T-008 (2026-05-20) — `Country` is shadowed inside `PostLoadDraft` by its
// nested `PostLoadDraft.Country` enum (6-case wizard UI). The canonical
// 3-case `Country` from `Services/FeeMultiplierEngine.swift` is what the
// fee engine accepts. A file-scope typealias resolves at file scope BEFORE
// PostLoadDraft is defined, so `FeeCountry` retains the canonical meaning
// even inside PostLoadDraft's nested scope. Same pattern for the canonical
// `TransportMode` (no collision today but futureproof).
fileprivate typealias FeeCountry = Country
fileprivate typealias FeeTransportMode = TransportMode

@MainActor
final class PostLoadDraft: ObservableObject {

    // MARK: - Step 0 · Mode + country

    /// Logistics mode. Drives the entire wizard's equipment list,
    /// regulatory checklist, and downstream compliance routing.
    /// `truck` covers all 12 truck-vertical roles; `rail` covers
    /// the 6 rail-vertical roles; `vessel` covers the 6 maritime
    /// roles. Drives `TripVertical` everywhere downstream.
    enum Mode: String, CaseIterable, Identifiable {
        case truck, rail, vessel
        var id: String { rawValue }
        var label: String {
            switch self { case .truck: return "Truck"; case .rail: return "Rail"; case .vessel: return "Vessel" }
        }
        var symbol: String {
            switch self { case .truck: return "truck.box"; case .rail: return "tram.fill"; case .vessel: return "ferry" }
        }
    }

    /// ISO-3166 country pair. Drives customs / hazmat regulatory
    /// dispatch (US: 49 CFR, ADR for EU, NOM for MX, IMDG for vessel,
    /// CTPAT for trusted-trader programs, etc.). Country labels are
    /// canonical per the platform's `cross_border` router schema.
    enum Country: String, CaseIterable, Identifiable {
        case US, CA, MX, EU, UK, Asia
        var id: String { rawValue }
        var label: String {
            switch self {
            case .US: return "United States"
            case .CA: return "Canada"
            case .MX: return "Mexico"
            case .EU: return "European Union"
            case .UK: return "United Kingdom"
            case .Asia: return "Asia (other)"
            }
        }
        var flag: String {
            switch self { case .US: return "🇺🇸"; case .CA: return "🇨🇦"; case .MX: return "🇲🇽"; case .EU: return "🇪🇺"; case .UK: return "🇬🇧"; case .Asia: return "🌏" }
        }
    }

    @Published var mode: Mode = .truck
    @Published var originCountry: Country = .US
    @Published var destinationCountry: Country = .US

    /// Cross-border = origin and destination differ. Drives a
    /// "Customs broker" sub-form on Step 2 + USMCA / VUCEM / CARM
    /// indicator chips on the Review screen.
    var isCrossBorder: Bool { originCountry != destinationCountry }

    /// USMCA-eligible lanes (US-CA-MX). Drives a verbatim chip on
    /// Review.
    var isUSMCA: Bool {
        let usmca: Set<Country> = [.US, .CA, .MX]
        return usmca.contains(originCountry) && usmca.contains(destinationCountry)
            && originCountry != destinationCountry
    }

    // MARK: - Step 1 · Lane

    @Published var origin: String = ""
    @Published var destination: String = ""
    /// Geocoded coordinates captured by `HereAddressField` (HERE
    /// autosuggest selection or "lat,lng" paste). Sent with
    /// `shippers.create` so the load detail map renders the lane and
    /// the server can route distance directly without re-geocoding.
    /// Falls back to server-side geocode on shippers.create when nil.
    @Published var originLat: Double? = nil
    @Published var originLng: Double? = nil
    @Published var destLat: Double? = nil
    @Published var destLng: Double? = nil
    @Published var pickupDate: Date? = nil
    @Published var deliveryDate: Date? = nil
    @Published var stops: [Stop] = []   // optional intermediate stops

    // MARK: - Step 2 · Equipment + cargo

    /// Server enum (loads.create accepts these literals only).
    enum CargoType: String, CaseIterable, Identifiable {
        case general, hazmat, refrigerated, oversized, liquid, gas, chemicals, petroleum
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:      return "General freight"
            case .hazmat:       return "Hazmat"
            case .refrigerated: return "Refrigerated"
            case .oversized:    return "Oversized"
            case .liquid:       return "Liquid (tanker)"
            case .gas:          return "Gas (tanker)"
            case .chemicals:    return "Chemicals"
            case .petroleum:    return "Petroleum"
            }
        }
    }

    @Published var cargoType: CargoType = .general
    @Published var equipmentType: String = ""
    @Published var weight: Double? = nil
    @Published var commodity: String = ""

    // ── T-005 / T-006 (canonical lock-in, 2026-05-20) ──
    // Canonical industry vertical (from Models/Vertical.swift) and trailer
    // code (Models/TrailerCode.swift). Replaces the old free-form
    // `equipmentType: String` for the truck-mode happy path; rail / vessel
    // modes still write the legacy String until T-034 lands the
    // RailCarKind + VesselClassKind UI. Both nullable so a partially-built
    // draft (no vertical chosen yet) renders the full TrailerCode list.
    /// Selected industry vertical (12 canonical buckets). Drives the
    /// trailer filter on Step 2 and the document requirements on Step 4.
    @Published var vertical: Vertical? = nil
    /// Selected trailer code. When set, `equipmentType` is kept synced
    /// to `trailer.rawValue` so legacy server-side parsers keep working.
    /// Server payload `shippers.create.trailer` reads this when present.
    @Published var trailer: TrailerCode? = nil

    // T-034 · 2026-05-20 — Cross-track identifier fields.
    // Rendered conditionally on the Step 2 equipment screen by mode:
    //   rail   → reporting marks + AAR car class
    //   vessel → BIC + ISO 6346 + IMO + MMSI
    // All optional/empty when unused. Stuffed into composedNotes() at
    // submit time as `[RAIL] MARKS=BNSF AAR=C113` or `[VESSEL] BIC=...`
    // blocks until `shippers.create` gains structured columns
    // (T-034b platform backlog).

    /// Rail mode — AAR reporting marks (e.g., "BNSF", "UP", "CSXT").
    @Published var reportingMarks: String = ""
    /// Rail mode — AAR car class code (e.g., "C113" for covered hopper,
    /// "T108" for tank car). Disambiguates equipment beyond the
    /// canonical RailCarKind enum which only captures families.
    @Published var aarClass: String = ""
    /// Vessel mode — BIC code (Bureau International des Containers).
    /// Standard 11-char container ID e.g., "MSCU1234567".
    @Published var bicCode: String = ""
    /// Vessel mode — ISO 6346 size + type code, 4 chars (e.g., "45G1"
    /// for 40' high-cube general-purpose container).
    @Published var isoCode: String = ""
    /// Vessel mode — IMO number (7-digit International Maritime
    /// Organization vessel identifier, e.g., "9123456").
    @Published var imoNumber: String = ""
    /// Vessel mode — MMSI (Maritime Mobile Service Identity), 9 digits.
    @Published var mmsi: String = ""

    /// T-009 · 2026-05-20 — canonical attached-documents set. Step 4
    /// Review surfaces every required document for the (vertical,
    /// isCrossBorder) tuple via `DocumentRequirements.forShipment(...)`
    /// and lets the shipper mark each one as on-file. The submit gate
    /// blocks Post when any document required at DRAFT / POSTED with
    /// `blocking == true` isn't in this set — later-state docs (LOADED /
    /// DELIVERED) ride along so the catalyst's load detail shows the
    /// full checklist, but they don't block the marketplace post.
    @Published var attachedDocuments: Set<DocumentType> = []

    // Hazmat sub-fields (only relevant when cargoType == .hazmat or
    // when equipmentType is a tanker spec'd for UN-coded cargo).
    @Published var unNumber: String = ""
    @Published var hazmatClass: String = ""
    @Published var packingGroup: String = ""
    @Published var properShippingName: String = ""
    @Published var ergGuide: Int? = nil
    @Published var chemtrecPhone: String = ""

    // Reefer sub-fields.
    @Published var reeferTempLow: Double? = nil
    @Published var reeferTempHigh: Double? = nil
    @Published var preCoolRequired: Bool = false
    @Published var continuousMode: Bool = true

    // MARK: - Step 2.5 · Catalyst / load requirements (web parity)
    //
    // Mirrors the web `LoadCreationWizard.tsx` step-4 fields the iOS
    // wizard was previously missing. Founder report 2026-05-06 —
    // "shipper post load wizard is missing some details, theres no
    // options for adding escort or escort requirement. or equipment
    // requirement thers a few key things missing."
    //
    // Each field threads into `shippers.create` so the load lands
    // server-side with the same metadata web posters set, and
    // downstream surfaces (driver eligibility filter, escort
    // marketplace, rate-board minimum-tier filter) light up
    // immediately.

    /// True when the load needs a lead/chase escort (oversized,
    /// hazmat-9, certain UN-coded chemicals). Drives the canonical
    /// EscortJobMarketplace inclusion + auto-routes the load to
    /// escort dispatch when posted.
    @Published var requiresEscort: Bool = false
    /// Optional escort headcount — 1 lead, 2 lead+chase, 3+ for
    /// permitted oversized convoys. nil = "router decides".
    @Published var escortCount: Int? = nil
    /// CDL endorsements the assigned driver must hold.
    /// Canonical values: "TWIC", "Hazmat", "Tanker", "DoublesTriples",
    /// "Passenger", "School Bus". Multi-select on the wizard step.
    @Published var requiredEndorsements: [String] = []
    /// Special equipment the trailer must carry — "tarps",
    /// "chains", "straps", "edge_protectors", "load_locks",
    /// "liftgate", "ramps", "pallet_jack". Multi-select.
    @Published var specialEquipment: [String] = []
    /// Minimum catalyst combined-single-limit insurance, in USD.
    /// Server-side rate sheets default to $1M; hazmat lanes typically
    /// require $5M; high-value cargo $10M+. Stored as a string so the
    /// server's zod parser handles big-number safely.
    @Published var minInsuranceCoverage: String = "1000000"
    /// FMCSA safety rating gate. Canonical values:
    /// "satisfactory" | "conditional" | "unrated" | "any". The
    /// scheduler / book-now flow rejects bidders whose rating is
    /// below this floor.
    @Published var minSafetyRating: String = "satisfactory"
    /// Hazmat operating-authority required on the catalyst's
    /// MC docket. Auto-true when `cargoType == .hazmat`.
    @Published var hazmatAuthRequired: Bool = false
    /// Allowlist of catalyst userIds that can see / bid on this load.
    /// Empty = open marketplace.
    @Published var preferredCatalystIds: [Int] = []
    /// Blocklist of catalyst userIds. Bids from these carriers are
    /// auto-rejected.
    @Published var blockedCatalystIds: [Int] = []
    /// True = only catalysts with an active contract for this lane
    /// can bid. False = open spot market.
    @Published var contractOnly: Bool = false
    /// True = require Apple-Pay / EusoWallet escrow before the bid is
    /// accepted. Surfaces a green "Escrow funded" pill on the iOS
    /// load detail when true.
    @Published var escrowRequired: Bool = false
    /// Optional appointment window enforcement. When true, the driver
    /// can't depart pickup until the EusoTicket appointment slot
    /// matches.
    @Published var appointmentRequired: Bool = false

    // MARK: - Step 3 · Pricing

    @Published var rate: Double? = nil
    @Published var fuelSurchargeRate: Double? = nil
    @Published var accessorialsAllowed: [String] = []
    @Published var contractTier: String = ""
    @Published var notes: String = ""

    /// Pricing strategy — matches the web wizard's step-6 enum.
    /// "auction" | "book_now" | "target".
    @Published var pricingStrategy: String = "auction"
    @Published var bookNowRate: Double? = nil
    @Published var minimumBid:   Double? = nil
    @Published var targetRate:   Double? = nil
    /// Auction window in hours (web default = 24).
    @Published var biddingDurationHours: Int = 24

    // MARK: - Submit state

    @Published var isPosting: Bool = false
    @Published var postError: String? = nil
    @Published var postedLoadNumber: String? = nil
    @Published var postedLoadId: String? = nil

    /// Server-emitted `LD-` number once the load lands. Cleared when
    /// the user starts a new draft.
    func reset() {
        origin = ""; destination = ""; pickupDate = nil; deliveryDate = nil
        stops = []; cargoType = .general; equipmentType = ""
        vertical = nil; trailer = nil
        attachedDocuments = []
        reportingMarks = ""; aarClass = ""
        bicCode = ""; isoCode = ""; imoNumber = ""; mmsi = ""
        ePodLockOverride = nil
        weight = nil; commodity = ""
        unNumber = ""; hazmatClass = ""; packingGroup = ""
        properShippingName = ""; ergGuide = nil; chemtrecPhone = ""
        reeferTempLow = nil; reeferTempHigh = nil
        preCoolRequired = false; continuousMode = true
        // Web-parity catalyst-requirement fields
        requiresEscort = false; escortCount = nil
        requiredEndorsements = []; specialEquipment = []
        minInsuranceCoverage = "1000000"; minSafetyRating = "satisfactory"
        hazmatAuthRequired = false
        preferredCatalystIds = []; blockedCatalystIds = []
        contractOnly = false; escrowRequired = false
        appointmentRequired = false
        rate = nil; fuelSurchargeRate = nil
        accessorialsAllowed = []; contractTier = ""; notes = ""
        pricingStrategy = "auction"
        bookNowRate = nil; minimumBid = nil; targetRate = nil
        biddingDurationHours = 24
        isPosting = false; postError = nil
        postedLoadNumber = nil; postedLoadId = nil
    }

    // MARK: - Validation

    enum ValidationError: Error, LocalizedError {
        case missingOrigin, missingDestination, missingPickup
        case hazmatFieldsRequired
        case reeferTempRequired
        var errorDescription: String? {
            switch self {
            case .missingOrigin:       return "Origin is required."
            case .missingDestination:  return "Destination is required."
            case .missingPickup:       return "Pickup date is required."
            case .hazmatFieldsRequired: return "Hazmat loads require UN, class, and proper shipping name."
            case .reeferTempRequired:  return "Reefer loads require a setpoint range."
            }
        }
    }

    func validate() throws {
        if origin.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError.missingOrigin
        }
        if destination.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError.missingDestination
        }
        if pickupDate == nil {
            throw ValidationError.missingPickup
        }
        if cargoType == .hazmat {
            if unNumber.isEmpty || hazmatClass.isEmpty || properShippingName.isEmpty {
                throw ValidationError.hazmatFieldsRequired
            }
        }
        if cargoType == .refrigerated {
            if reeferTempLow == nil || reeferTempHigh == nil {
                throw ValidationError.reeferTempRequired
            }
        }
    }

    // MARK: - Submit

    func submit() async {
        do {
            try validate()
        } catch {
            postError = (error as? ValidationError)?.errorDescription
                     ?? error.localizedDescription
            return
        }
        isPosting = true; postError = nil
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            // Hit `shippers.create` directly with a strict Zod payload.
            // The string-literal cargoType matches the server enum and
            // the existing typed wrapper at line 9755.
            //
            // originLat/originLng/destLat/destLng are sent when the user
            // picked a HERE autosuggest result or pasted "lat,lng" in
            // the address field. Server uses these to skip re-geocoding
            // and route distance directly. When nil the server geocodes
            // both ends as a fallback.
            // Hazmat cargo type auto-implies the hazmat-auth gate so a
            // shipper can't accidentally post UN-coded freight to a
            // non-hazmat catalyst.
            let resolvedHazmatAuth = hazmatAuthRequired || cargoType == .hazmat

            struct In: Encodable {
                let origin: String; let destination: String; let cargoType: String
                let rate: Double?; let weight: Double?; let notes: String?; let pickupDate: String?
                let originLat: Double?; let originLng: Double?
                let destLat:   Double?; let destLng:   Double?
                // Web-parity catalyst requirements (`LoadCreationWizard.tsx` step 4)
                let requiresEscort: Bool?
                let escortCount:    Int?
                let requiredEndorsements: [String]?
                let specialEquipment:     [String]?
                let minInsuranceCoverage: String?
                let minSafetyRating:      String?
                let hazmatAuthRequired:   Bool?
                let preferredCatalystIds: [Int]?
                let blockedCatalystIds:   [Int]?
                let contractOnly:         Bool?
                let escrowRequired:       Bool?
                let appointmentRequired:  Bool?
                // Pricing strategy block (web step 6)
                let pricingStrategy:      String?
                let bookNowRate:          Double?
                let minimumBid:           Double?
                let targetRate:           Double?
                let biddingDurationHours: Int?
                let equipmentType:        String?
                // T-005 · canonical lock-in 2026-05-20:
                // Server now receives the canonical TrailerCode + Vertical
                // raw values alongside the legacy `equipmentType` string.
                // Both fields are optional so an older client without
                // T-005 can still post. Server-side validators round-trip
                // through TrailerCode.RawValue / Vertical.RawValue when
                // present; equipmentType remains the fallback path until
                // every consumer migrates.
                let trailer:              String?
                let vertical:             String?
                // T-009 · 2026-05-20 — attached document set as raw values.
                // Server stores against the load row + uses them as the
                // initial "documents on file" set; future doc uploads
                // append. Empty array elided to nil so older servers
                // ignore the field.
                let attachedDocuments:    [String]?
                // T-011 · 2026-05-20 — ePOD lock flag. When true, EusoWallet
                // holds settlement disbursement until the driver's POD
                // capture passes the cryptographic chain-of-custody check
                // at DELIVERED. Auto-true for cross-border / hazmat /
                // rate > $5k / heavy-haul; shipper can override.
                let ePodLockEnabled:      Bool?
            }
            struct Out: Decodable {
                let success: Bool; let id: Int; let loadNumber: String
            }
            let result: Out = try await EusoTripAPI.shared.mutation(
                "shippers.create",
                input: In(
                    origin: origin,
                    destination: destination,
                    cargoType: cargoType.rawValue,
                    rate: rate,
                    weight: weight,
                    notes: composedNotes().isEmpty ? nil : composedNotes(),
                    pickupDate: pickupDate.map { iso.string(from: $0) },
                    originLat: originLat, originLng: originLng,
                    destLat:   destLat,   destLng:   destLng,
                    requiresEscort:        requiresEscort ? true : nil,
                    escortCount:           escortCount,
                    requiredEndorsements:  requiredEndorsements.isEmpty ? nil : requiredEndorsements,
                    specialEquipment:      specialEquipment.isEmpty ? nil : specialEquipment,
                    minInsuranceCoverage:  minInsuranceCoverage.isEmpty ? nil : minInsuranceCoverage,
                    minSafetyRating:       minSafetyRating.isEmpty ? nil : minSafetyRating,
                    hazmatAuthRequired:    resolvedHazmatAuth ? true : nil,
                    preferredCatalystIds:  preferredCatalystIds.isEmpty ? nil : preferredCatalystIds,
                    blockedCatalystIds:    blockedCatalystIds.isEmpty ? nil : blockedCatalystIds,
                    contractOnly:          contractOnly ? true : nil,
                    escrowRequired:        escrowRequired ? true : nil,
                    appointmentRequired:   appointmentRequired ? true : nil,
                    pricingStrategy:       pricingStrategy.isEmpty ? nil : pricingStrategy,
                    bookNowRate:           bookNowRate,
                    minimumBid:            minimumBid,
                    targetRate:            targetRate,
                    biddingDurationHours:  biddingDurationHours > 0 ? biddingDurationHours : nil,
                    equipmentType:         equipmentType.isEmpty ? nil : equipmentType,
                    trailer:               trailer?.rawValue,
                    vertical:              vertical?.rawValue,
                    attachedDocuments:     attachedDocuments.isEmpty ? nil : attachedDocuments.map(\.rawValue),
                    ePodLockEnabled:       ePodLockEnabled ? true : nil
                )
            )
            postedLoadNumber = result.loadNumber
            postedLoadId = String(result.id)
        } catch {
            postError = (error as? EusoTripAPIError)?.errorDescription
                     ?? error.localizedDescription
        }
        isPosting = false
    }

    /// Compose hazmat / reefer / multi-stop sub-form output into the
    /// `notes` field the server accepts today. When the server adds
    /// dedicated columns for these (multi-stop schema is in §5 of the
    /// plan), this seam goes away — the wizard mutation accepts the
    /// fields directly.
    private func composedNotes() -> String {
        var lines: [String] = []
        if !notes.isEmpty { lines.append(notes) }
        if cargoType == .hazmat {
            var hz: [String] = []
            if !unNumber.isEmpty           { hz.append("UN \(unNumber)") }
            if !hazmatClass.isEmpty        { hz.append("Class \(hazmatClass)") }
            if !packingGroup.isEmpty       { hz.append("PG \(packingGroup)") }
            if !properShippingName.isEmpty { hz.append("PSN: \(properShippingName)") }
            if let g = ergGuide            { hz.append("ERG #\(g)") }
            if !chemtrecPhone.isEmpty      { hz.append("CHEMTREC \(chemtrecPhone)") }
            if !hz.isEmpty { lines.append("[HAZMAT] " + hz.joined(separator: " · ")) }
        }
        if cargoType == .refrigerated, let lo = reeferTempLow, let hi = reeferTempHigh {
            var rf = ["Setpoint \(Int(lo))–\(Int(hi))°F"]
            if preCoolRequired { rf.append("pre-cool required") }
            if continuousMode  { rf.append("continuous mode") }
            lines.append("[REEFER] " + rf.joined(separator: " · "))
        }
        if !stops.isEmpty {
            let r = stops.map { stop in
                "\(stop.sequence). \(stop.address)\(stop.appointmentISO.map { " @ \($0)" } ?? "")"
            }.joined(separator: " | ")
            lines.append("[STOPS] " + r)
        }
        // T-034 · 2026-05-20 — Cross-track identifier serialization.
        // Until shippers.create grows structured rail/vessel columns,
        // these ride in the notes block so the catalyst's dispatcher
        // sees the equipment IDs at dispatch time. Server-side parsers
        // already accept this overflow pattern (see CARGO + STOPS).
        if mode == .rail, !reportingMarks.isEmpty || !aarClass.isEmpty {
            var parts: [String] = []
            if !reportingMarks.isEmpty { parts.append("MARKS=\(reportingMarks)") }
            if !aarClass.isEmpty        { parts.append("AAR=\(aarClass)") }
            lines.append("[RAIL] " + parts.joined(separator: " · "))
        }
        if mode == .vessel,
           !bicCode.isEmpty || !isoCode.isEmpty || !imoNumber.isEmpty || !mmsi.isEmpty {
            var parts: [String] = []
            if !bicCode.isEmpty   { parts.append("BIC=\(bicCode)") }
            if !isoCode.isEmpty   { parts.append("ISO=\(isoCode)") }
            if !imoNumber.isEmpty { parts.append("IMO=\(imoNumber)") }
            if !mmsi.isEmpty      { parts.append("MMSI=\(mmsi)") }
            lines.append("[VESSEL] " + parts.joined(separator: " · "))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - T-008 · FeeMultiplierEngine bridge (2026-05-20)
    //
    // The canonical fee engine (Services/FeeMultiplierEngine.swift)
    // requires its own enum vocabulary (Country: 3 cases · TransportMode:
    // 4 cases · Vertical · TrailerCode · Decimal distance / cycle days).
    // PostLoadDraft holds the broader UI enums (Country: 6 cases · Mode:
    // 3 cases · Double weight); this section bridges between them with
    // a single computed `FeeComputationInput` the wizard's Step 3 pricing
    // card reads. Unknown countries clamp to US so the engine never sees
    // an unsupported case — broker rate sheets still resolve.

    /// Canonical platform commission floor (5%). Read from the server
    /// in a follow-up firing — for now a single source of truth here.
    static let canonicalBaseRate: Decimal = 0.05

    /// Best-effort posting-cycle window. Until `shipper.lastPostedOnLane`
    /// lands as a server endpoint, default to 365 (one-off) so the cycle
    /// dampener applies the highest multiplier (1.10). Repeat shippers
    /// override this when the server starts returning the value.
    var shipperPostingCycleDays: Int { 365 }

    /// Map the wizard's 6-case Country enum to the engine's 3-case enum.
    /// EU / UK / Asia clamp to US so the engine has a defined multiplier
    /// — refinement tracked when ROW lanes ship. Return type uses the
    /// `FeeCountry` typealias to escape `PostLoadDraft.Country` shadowing.
    private func canonicalCountry(_ c: PostLoadDraft.Country) -> FeeCountry {
        switch c {
        case .US: return .US
        case .MX: return .MX
        case .CA: return .CA
        case .EU, .UK, .Asia: return .US   // fallback until engine grows ROW coverage
        }
    }

    /// Map the wizard's 3-case Mode enum to the engine's 4-case TransportMode.
    /// `barge` and `intermodal` come from the canonical TransportMode but
    /// the wizard doesn't expose them yet.
    private func canonicalMode(_ m: PostLoadDraft.Mode) -> FeeTransportMode {
        switch m {
        case .truck:  return .truck
        case .rail:   return .rail
        case .vessel: return .vessel
        }
    }

    /// Derive isHazmat from the strongest available signal: explicit cargo
    /// type, the trailer's intrinsic hazmat eligibility, or the vertical.
    var isHazmatComputed: Bool {
        if cargoType == .hazmat { return true }
        if trailer?.isHazmatEligible == true { return true }
        if vertical == .hazmat { return true }
        if vertical == .tankerLiquidBulk { return true }
        return false
    }

    /// Great-circle distance in miles between origin/destination coordinates.
    /// Returns 0 when either endpoint is unset — the engine treats 0 as
    /// "drayage" tier (highest distance multiplier).
    var distanceMiles: Decimal {
        guard let oLat = originLat, let oLng = originLng,
              let dLat = destLat,   let dLng = destLng else { return 0 }
        let r: Double = 3959   // Earth radius, statute miles
        let dLatR = (dLat - oLat) * .pi / 180
        let dLngR = (dLng - oLng) * .pi / 180
        let a = sin(dLatR / 2) * sin(dLatR / 2)
              + cos(oLat * .pi / 180) * cos(dLat * .pi / 180)
              * sin(dLngR / 2) * sin(dLngR / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return Decimal(r * c)
    }

    /// Build a complete `FeeComputationInput` from the current draft. Returns
    /// nil when the canonical inputs aren't ready yet (no trailer or vertical
    /// picked) so the pricing card can render its empty state instead of
    /// computing a fee against `.dryVan / .generalFreight` defaults.
    var feeInputs: FeeComputationInput? {
        guard let t = trailer else { return nil }
        let v = vertical ?? t.defaultVertical
        return FeeComputationInput(
            baseRate: Self.canonicalBaseRate,
            originCountry: canonicalCountry(originCountry),
            destinationCountry: canonicalCountry(destinationCountry),
            vertical: v,
            trailer: t,
            mode: canonicalMode(mode),
            isHazmat: isHazmatComputed,
            distanceMiles: distanceMiles,
            shipperPostingCycleDays: shipperPostingCycleDays,
            isCrossBorder: isCrossBorder,
        )
    }

    /// Convenience — invokes the engine when `feeInputs` is ready.
    var feeBreakdown: FeeBreakdown? {
        guard let inputs = feeInputs else { return nil }
        return FeeMultiplierEngine.compute(inputs)
    }

    // MARK: - T-009 · Document requirements (2026-05-20)

    /// Full required-document list for the current draft, derived from
    /// `DocumentRequirements.forShipment(vertical:isCrossBorder:)`. Returns
    /// an empty list when no vertical is picked yet (Step 2 still pending).
    var requiredDocuments: [DocumentRequirement] {
        guard let v = vertical else { return [] }
        return DocumentRequirements.forShipment(vertical: v, isCrossBorder: isCrossBorder)
    }

    /// Documents whose `blocking == true` and whose `requiredAt` is
    /// DRAFT or POSTED — i.e., documents the wizard must enforce BEFORE
    /// the shipper hits Post. Later-state blocking docs (LOADED /
    /// DELIVERED) are tracked on the load row and enforced by the FSM
    /// guard when the driver / catalyst attempts those transitions.
    var preFlightBlockingDocs: [DocumentRequirement] {
        requiredDocuments.filter { req in
            guard req.blocking else { return false }
            return req.requiredAt == .draft || req.requiredAt == .posted
        }
    }

    /// True when every pre-flight blocking document is in `attachedDocuments`.
    /// Step 4 disables the Post button while false.
    var canPostMarketplace: Bool {
        for req in preFlightBlockingDocs where !attachedDocuments.contains(req.document) {
            return false
        }
        return true
    }

    // MARK: - T-011 · ePOD lock (2026-05-20)
    //
    // ePOD lock = settlement disbursement waits for cryptographically-
    // verified proof of delivery before EusoWallet releases funds. Auto-
    // enabled for high-risk lanes per the canonical spec: cross-border
    // (customs fraud risk), hazmat (regulatory compliance), high-value
    // (rate > $5k → escrow protection), heavy haul (permits + escort
    // verification). Shipper can override by toggling on Step 4 (the
    // override surfaces a banner).

    /// User override — when nil, auto-derive from `requiresEpodLock`.
    /// When set, takes precedence (true = force on, false = force off).
    @Published var ePodLockOverride: Bool? = nil

    /// True when this load's risk profile triggers an automatic ePOD
    /// lock per the canonical thresholds.
    var requiresEpodLock: Bool {
        if isCrossBorder { return true }
        if isHazmatComputed { return true }
        if let r = rate, r > 5000 { return true }
        if vertical == .heavyHaulSpecialized { return true }
        return false
    }

    /// Final ePOD-lock decision sent to the server. Honors any explicit
    /// override; falls back to the auto-derived value.
    var ePodLockEnabled: Bool { ePodLockOverride ?? requiresEpodLock }

    // MARK: - Stop type for multi-stop builder

    struct Stop: Identifiable, Hashable {
        let id = UUID()
        var sequence: Int
        var address: String
        var contactName: String = ""
        var contactPhone: String = ""
        var appointmentISO: String? = nil
        var notes: String = ""
    }
}
