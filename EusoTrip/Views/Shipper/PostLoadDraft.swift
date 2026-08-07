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

/// One machine-evaluable operational fact for an industry workflow.
///
/// Mirrors the server's `IndustryOperationalFactRequirement.valueType`
/// (`server/services/industryVerticalRegistry.ts`): a fact is a string, a
/// positive number, or a boolean, and the server checks the TYPE, not just
/// presence — a `"true"` string never satisfies a boolean determination.
///
/// The same value set travels on BOTH `industryVerticals.assessDraft`
/// (`operationalFacts`) and `shippers.create` (`verticalData`), because
/// `validateIndustryVerticalAssessmentForLoad` compares the two JSON objects
/// and rejects the assessment as stale when they differ.
enum IndustryOperationalFact: Encodable, Hashable {
    case text(String)
    case number(Double)
    case flag(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):   try container.encode(value)
        case .number(let value): try container.encode(value)
        case .flag(let value):   try container.encode(value)
        }
    }
}

struct IndustryWorkflowHandoff {
    let sectorId: String
    let ruleSetId: Int
    let workflowId: String
    let productName: String?
    let cargoType: String?
    let trailerCode: String?
    let requiredEndorsements: [String]
    let specialEquipment: [String]
    let accessorialAllowList: [String]
    let hazmatAuthRequired: Bool
    let preCoolRequired: Bool
    let continuousMonitoring: Bool
}

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
        /// HERE ISO-3166 alpha-3 code for autosuggest country-bias; nil for
        /// the multi-country buckets (no single HERE code → unbiased, honest).
        var hereCountryCode: String? {
            switch self { case .US: return "USA"; case .CA: return "CAN"; case .MX: return "MEX"; default: return nil }
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
    /// The unit `weight` is expressed in — the ONE value both the local
    /// classification mirror and the wire read.
    ///
    /// 2026-08-07: this used to exist only as a hardcoded `"lbs"` inside the
    /// mirror, while `shippers.create` received no unit at all. The server
    /// requires a quantity unit for every dangerous-goods post
    /// (`assessCargoClassification` → "regulated-material quantity unit"), so
    /// the mirror said "ready", the button went green, and the post was then
    /// refused. Both readers now resolve the same stored value.
    ///
    /// It is not an invented default: the wizard's Step-2 field is labelled
    /// "WEIGHT (LB)" (251_PostLoadStep2Equipment), so pounds is what the
    /// poster is entering. A surface that offers a unit picker sets this.
    @Published var weightUnit: String = "lbs"
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
    @Published var industrySectorId: String? = nil
    @Published var industryRuleSetId: Int? = nil
    @Published var industryAssessmentId: String? = nil
    @Published var industryAssessmentStatus: String? = nil
    @Published var industryAssessmentWarnings: [String] = []
    @Published var industryAssessmentError: String? = nil
    @Published var isAssessingIndustry: Bool = false
    @Published var industryReviewAcknowledged: Bool = false
    /// Operational facts the POSTER supplied for the selected workflow, keyed
    /// by the server's fact key (`productType`, `vehicleCount`, `dscsaCovered`
    /// …). Nine of the twelve canonical workflows — and five sectors — require
    /// at least one, and the assessment returns `needs_input` until they are
    /// present, which blocks the post.
    ///
    /// Facts the wizard already owns are derived in `derivedOperationalFacts`;
    /// anything set here wins, because a poster's answer outranks a mapping.
    /// Nothing is ever defaulted: a sector's boolean determinations
    /// (`dscsaCovered`, `fsmaCovered`, `coveredInterstateMove`,
    /// `veterinaryMovementDocumentRequired`) are legal calls only the poster
    /// can make, so they are never derived.
    @Published var operationalFacts: [String: IndustryOperationalFact] = [:]
    private var industryAssessmentRequestId = UUID()
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

    // ─── 2026-08-07 · cargo-classification attestation ────────────────
    // The poster's determination + evidence, on the ONE shared primitive
    // (Views/Components/CargoClassificationAttestation). Required by
    // `shippers.create` AND `industryVerticals.assessDraft`. Starts empty
    // — no determination, no source, no evidence reference. The fields
    // above may SUGGEST an identity to the control; they never establish
    // one, and they are never submitted as the attestation.
    @Published var classification = CargoClassificationAttestation()

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
    @Published var isHydratingDraft: Bool = false
    @Published var hydrateError: String? = nil
    @Published var hydratedDraftId: String? = nil

    /// Server-emitted `LD-` number once the load lands. Cleared when
    /// the user starts a new draft.
    func reset() {
        origin = ""; destination = ""; pickupDate = nil; deliveryDate = nil
        // Clear the geocoded coordinates too — otherwise "Post another" inherits
        // the previous load's lat/lng under a blank origin/destination field.
        originLat = nil; originLng = nil; destLat = nil; destLng = nil
        stops = []; cargoType = .general; equipmentType = ""
        vertical = nil; trailer = nil
        industrySectorId = nil; industryRuleSetId = nil
        industryAssessmentId = nil; industryAssessmentStatus = nil
        industryAssessmentWarnings = []; industryAssessmentError = nil
        isAssessingIndustry = false; industryReviewAcknowledged = false
        operationalFacts = [:]; submittedOperationalFacts = [:]
        industryAssessmentRequestId = UUID()
        attachedDocuments = []
        reportingMarks = ""; aarClass = ""
        bicCode = ""; isoCode = ""; imoNumber = ""; mmsi = ""
        ePodLockOverride = nil
        weight = nil; weightUnit = "lbs"; commodity = ""
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
        isHydratingDraft = false; hydrateError = nil; hydratedDraftId = nil
    }

    func applyIndustryWorkflow(_ handoff: IndustryWorkflowHandoff) {
        industrySectorId = handoff.sectorId
        industryRuleSetId = handoff.ruleSetId
        industryAssessmentId = nil
        industryAssessmentStatus = nil
        industryAssessmentWarnings = []
        industryAssessmentError = nil
        industryReviewAcknowledged = false
        // Facts are keyed per workflow; a new workflow asks new questions, so
        // the previous answers are dropped rather than carried into a
        // requirement set they were never answers to.
        operationalFacts = [:]; submittedOperationalFacts = [:]
        industryAssessmentRequestId = UUID()

        vertical = Vertical(rawValue: handoff.workflowId)
        if let rawCargo = handoff.cargoType,
           let resolvedCargo = CargoType(rawValue: rawCargo) {
            cargoType = resolvedCargo
        }
        if let rawTrailer = handoff.trailerCode,
           let resolvedTrailer = TrailerCode(rawValue: rawTrailer) {
            trailer = resolvedTrailer
            equipmentType = resolvedTrailer.rawValue
        }
        if let productName = handoff.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !productName.isEmpty {
            commodity = productName
        }
        requiredEndorsements = handoff.requiredEndorsements
        specialEquipment = handoff.specialEquipment
        accessorialsAllowed = handoff.accessorialAllowList
        hazmatAuthRequired = handoff.hazmatAuthRequired
        preCoolRequired = handoff.preCoolRequired
        continuousMode = handoff.continuousMonitoring
    }

    struct ServerDraft: Decodable {
        struct Location: Decodable {
            let address: String?
            let city: String?
            let state: String?
            let zipCode: String?
            let lat: Double?
            let lng: Double?

            private enum CodingKeys: String, CodingKey {
                case address, city, state, zipCode, lat, lng
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                address = try c.decodeIfPresent(String.self, forKey: .address)
                city = try c.decodeIfPresent(String.self, forKey: .city)
                state = try c.decodeIfPresent(String.self, forKey: .state)
                zipCode = try c.decodeIfPresent(String.self, forKey: .zipCode)
                lat = Self.decodeDouble(c, .lat)
                lng = Self.decodeDouble(c, .lng)
            }

            var displayText: String {
                let cityState = [city, state]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !address.isEmpty {
                    if !cityState.isEmpty, !address.localizedCaseInsensitiveContains(cityState) {
                        return "\(address), \(cityState)"
                    }
                    return address
                }
                return cityState
            }

            private static func decodeDouble<K: CodingKey>(
                _ c: KeyedDecodingContainer<K>,
                _ key: K
            ) -> Double? {
                if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
                if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
                if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
                return nil
            }
        }

        let id: String
        let loadNumber: String?
        let origin: Location?
        let destination: Location?
        let cargoType: String?
        let rate: Double?
        let weight: Double?
        let notes: String?
        let pickupDate: String?
        let deliveryDate: String?
        let transportMode: String?
        let trailer: String?
        let vertical: String?
        let attachedDocuments: [String]?
        let ePodLockEnabled: Bool?

        private enum CodingKeys: String, CodingKey {
            case id, loadNumber, origin, destination, cargoType, rate, weight, notes
            case pickupDate, deliveryDate, transportMode, trailer, vertical
            case attachedDocuments, ePodLockEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            loadNumber = try c.decodeIfPresent(String.self, forKey: .loadNumber)
            origin = try c.decodeIfPresent(Location.self, forKey: .origin)
            destination = try c.decodeIfPresent(Location.self, forKey: .destination)
            cargoType = try c.decodeIfPresent(String.self, forKey: .cargoType)
            rate = Self.decodeDouble(c, .rate)
            weight = Self.decodeDouble(c, .weight)
            notes = try c.decodeIfPresent(String.self, forKey: .notes)
            pickupDate = try c.decodeIfPresent(String.self, forKey: .pickupDate)
            deliveryDate = try c.decodeIfPresent(String.self, forKey: .deliveryDate)
            transportMode = try c.decodeIfPresent(String.self, forKey: .transportMode)
            trailer = try c.decodeIfPresent(String.self, forKey: .trailer)
            vertical = try c.decodeIfPresent(String.self, forKey: .vertical)
            attachedDocuments = try c.decodeIfPresent([String].self, forKey: .attachedDocuments)
            if let decodedBool = try c.decodeIfPresent(Bool.self, forKey: .ePodLockEnabled) {
                ePodLockEnabled = decodedBool
            } else if let decodedInt = try c.decodeIfPresent(Int.self, forKey: .ePodLockEnabled) {
                ePodLockEnabled = decodedInt != 0
            } else if let decodedString = try c.decodeIfPresent(String.self, forKey: .ePodLockEnabled) {
                ePodLockEnabled = decodedString == "1" || decodedString.lowercased() == "true"
            } else {
                ePodLockEnabled = nil
            }
        }

        private static func decodeDouble<K: CodingKey>(
            _ c: KeyedDecodingContainer<K>,
            _ key: K
        ) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
            if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
            return nil
        }
    }

    func hydrateFromServerDraft(id draftId: String) async {
        if hydratedDraftId == draftId { return }
        isHydratingDraft = true
        hydrateError = nil
        struct In: Encodable { let id: String }
        do {
            let row: ServerDraft = try await EusoTripAPI.shared.query(
                "loads.getDraft",
                input: In(id: draftId)
            )
            apply(serverDraft: row)
            hydratedDraftId = draftId
        } catch {
            hydrateError = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
        isHydratingDraft = false
    }

    private func apply(serverDraft row: ServerDraft) {
        origin = row.origin?.displayText ?? ""
        destination = row.destination?.displayText ?? ""
        originLat = row.origin?.lat
        originLng = row.origin?.lng
        destLat = row.destination?.lat
        destLng = row.destination?.lng
        pickupDate = row.pickupDate.flatMap(Self.parseISODate)
        deliveryDate = row.deliveryDate.flatMap(Self.parseISODate)
        if let cargo = row.cargoType, let resolved = CargoType(rawValue: cargo) {
            cargoType = resolved
        }
        rate = row.rate
        weight = row.weight
        notes = row.notes ?? ""
        if let mode = row.transportMode, let resolved = Mode(rawValue: mode) {
            self.mode = resolved
        }
        if let trailer = row.trailer, let resolved = TrailerCode(rawValue: trailer) {
            self.trailer = resolved
            equipmentType = resolved.rawValue
        }
        if let vertical = row.vertical, let resolved = Vertical(rawValue: vertical) {
            self.vertical = resolved
        }
        if let docs = row.attachedDocuments {
            attachedDocuments = Set(docs.compactMap(DocumentType.init(rawValue:)))
        }
        if let locked = row.ePodLockEnabled {
            ePodLockOverride = locked
        }
    }

    private static func parseISODate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? plain.date(from: raw)
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
            case .hazmatFieldsRequired: return "Hazmat loads require UN, class and proper shipping name."
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

    private struct IndustryAssessmentInput: Encodable {
        let clientRequestId: String
        let sectorId: String
        let ruleSetId: Int
        let workflowId: String
        let transportMode: String
        let originCountryCode: String
        let destinationCountryCode: String
        let productName: String?
        let cargoType: String
        // Same three attestation fields the create call carries — the
        // assessor keys its regulatory workflow off the poster's
        // determination, not off a derived guess.
        let dangerousGoodsStatus: String
        let classificationSource: String?
        let classificationEvidenceRef: String?
        let unNumber: String?
        let properShippingName: String?
        let hazmatClass: String?
        let packingGroupStatus: String?
        let packingGroup: String?
        let technicalName: String?
        let emergencyPhone: String?
        let subsidiaryHazards: [String]?
        let packagingType: String?
        let equipmentType: String?
        // The classification quantity + unit the create call will resolve.
        // `validateIndustryVerticalAssessmentForLoad` compares the assessed
        // draft against the create payload field by field, so omitting these
        // made EVERY assessed post fail with "the cargo details changed after
        // industry assessment" the moment a weight was entered.
        let quantity: Double?
        let quantityUnit: String?
        let temperatureMin: Double?
        let temperatureMax: Double?
        let temperatureUnit: String?
        /// Workflow + sector operational facts. Nine of the twelve canonical
        /// workflows require at least one; without them the assessment is
        /// permanently `needs_input`.
        let operationalFacts: [String: IndustryOperationalFact]?
    }

    private struct IndustryAssessmentOutput: Decodable {
        struct Result: Decodable {
            let requiredInputs: [String]
            let blockingReasons: [String]
            let warnings: [String]
        }

        let assessmentId: String
        let status: String
        let result: Result
    }

    // REMOVED 2026-08-07 — `suggestedDangerousGoodsStatus`, which derived a
    // determination from `cargoType == .hazmat`.
    //
    // It had zero call sites, and its own comment described it as a value "the
    // control may open on" — which is exactly what the attestation must never
    // do. Nothing is pre-selected; the shipper attests and the app records. A
    // live inference helper sitting one call away from the wire is a trap: the
    // next person to wire it up reintroduces cargoType inference without ever
    // touching a rule that says not to. The determination now comes only from
    // `classification`, which only the poster can complete.

    /// The equipment the server will classify against.
    ///
    /// `shippers.create` resolves it as `equipmentType ?? trailer`, so the
    /// assessment has to be made against the same resolution — assessing
    /// against a bare `equipmentType` while the create call falls through to
    /// the trailer code is exactly the drift that makes the assessment stale.
    var resolvedEquipmentType: String? {
        let typed = equipmentType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return trailer?.rawValue
    }

    /// The load facts the server's classification assessor needs that the
    /// attestation does not own.
    var classificationContext: CargoClassificationAttestation.CargoContext {
        CargoClassificationAttestation.CargoContext(
            productName: commodity.trimmingCharacters(in: .whitespacesAndNewlines),
            equipmentType: resolvedEquipmentType ?? "",
            transportMode: mode.rawValue,
            quantity: classificationQuantity,
            // The unit the mirror reports is the unit the wire carries — read
            // from the same stored value, never restated as a literal.
            quantityUnit: classificationQuantity != nil ? weightUnit : ""
        )
    }

    /// The quantity the server will classify against.
    ///
    /// `shippers.create` resolves it as `quantity ?? weight`; this wizard has
    /// only `weight`, so that is the quantity — but only when it is a real
    /// positive figure. A zero or absent weight is NOT a quantity, and saying
    /// otherwise would make the local mirror disagree with the server.
    var classificationQuantity: Double? {
        guard let weight, weight.isFinite, weight > 0 else { return nil }
        return weight
    }

    /// The unit that travels with `classificationQuantity`. Sent as
    /// `weightUnit` on `shippers.create` and as `quantityUnit` on
    /// `industryVerticals.assessDraft`, so the two payloads agree — the
    /// assessment is rejected as stale when they do not.
    var classificationQuantityUnit: String? {
        guard classificationQuantity != nil else { return nil }
        let trimmed = weightUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Operational facts this wizard genuinely owns, mapped onto the server's
    /// fact keys for the selected workflow. Every value here is something the
    /// poster typed on a wizard field that means exactly this — nothing is
    /// inferred, and a workflow whose facts the wizard does not collect
    /// contributes nothing, so the assessment says `needs_input` and names
    /// them instead of the post failing for an unexplained reason.
    private var derivedOperationalFacts: [String: IndustryOperationalFact] {
        guard let workflow = vertical else { return [:] }
        var facts: [String: IndustryOperationalFact] = [:]
        let product = commodity.trimmingCharacters(in: .whitespacesAndNewlines)
        let containerNumber = bicCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let containerSize = isoCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch workflow {
        case .refrigerated:
            if !product.isEmpty { facts["productType"] = .text(product) }
        case .dryBulkPneumatic:
            if !product.isEmpty { facts["commodity"] = .text(product) }
        case .heavyHaulSpecialized:
            if let quantity = classificationQuantity { facts["grossWeight"] = .number(quantity) }
        case .householdGoods:
            if let quantity = classificationQuantity { facts["estimatedWeight"] = .number(quantity) }
        case .intermodalContainer:
            if !containerNumber.isEmpty { facts["containerNumber"] = .text(containerNumber) }
            if !containerSize.isEmpty { facts["containerSize"] = .text(containerSize) }
        case .generalFreight, .hazmat, .tankerLiquidBulk,
             .flatbedOpenDeck, .autoTransport, .ltlPartial, .livestock:
            break
        }
        return facts
    }

    /// The exact operational-fact object sent to BOTH `assessDraft` and
    /// `shippers.create`. Poster-supplied answers override derived ones.
    var resolvedOperationalFacts: [String: IndustryOperationalFact] {
        var facts = derivedOperationalFacts
        for (key, value) in operationalFacts { facts[key] = value }
        return facts
    }

    /// The fact set the CURRENT assessment was actually made against. The post
    /// sends this one, not a freshly-resolved set, so the two payloads cannot
    /// diverge between the assessment and the create call.
    private(set) var submittedOperationalFacts: [String: IndustryOperationalFact] = [:]

    /// Honest reason the wizard cannot post yet, or nil when the poster has
    /// completed the attestation.
    var classificationBlockReason: String? {
        classification.blockReason(context: classificationContext)
    }

    /// Mirror the regulated identity the poster typed on the wizard's hazmat
    /// sub-form into the attestation (one way — the wizard owns those three
    /// fields, the attestation owns the wire). `properShippingName` is only a
    /// proper shipping name on hazmat cargo; on anything else it is the plain
    /// commodity and must not travel as a regulated identifier.
    func mirrorIdentityIntoClassification() {
        classification.unNumber = unNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        classification.hazmatClass = hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines)
        classification.properShippingName = cargoType == .hazmat
            ? properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
    }

    private func exactCountryCode(_ country: Country) -> String? {
        switch country {
        case .US: return "US"
        case .CA: return "CA"
        case .MX: return "MX"
        case .UK: return "GB"
        case .EU, .Asia: return nil
        }
    }

    private func refreshIndustryAssessment(requireReviewAcknowledgement: Bool = true) async throws {
        guard let sectorId = industrySectorId,
              let ruleSetId = industryRuleSetId,
              let workflowId = vertical?.rawValue else {
            industryAssessmentId = nil
            industryAssessmentStatus = nil
            industryAssessmentWarnings = []
            submittedOperationalFacts = [:]
            return
        }
        guard let originCode = exactCountryCode(originCountry),
              let destinationCode = exactCountryCode(destinationCountry) else {
            throw NSError(
                domain: "EusoTrip.IndustryVertical",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Choose an exact origin and destination country before applying this industry workflow."
                ]
            )
        }

        let product = commodity.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the attestation's regulated identity in step with what the
        // poster typed on the hazmat sub-form before it goes on the wire.
        mirrorIdentityIntoClassification()
        // Resolved ONCE, then sent on both calls, so the assessed draft and
        // the create payload cannot drift within a single post.
        let facts = resolvedOperationalFacts
        submittedOperationalFacts = facts
        let response: IndustryAssessmentOutput = try await EusoTripAPI.shared.mutation(
            "industryVerticals.assessDraft",
            input: IndustryAssessmentInput(
                clientRequestId: industryAssessmentRequestId.uuidString.lowercased(),
                sectorId: sectorId,
                ruleSetId: ruleSetId,
                workflowId: workflowId,
                transportMode: mode.rawValue,
                originCountryCode: originCode,
                destinationCountryCode: destinationCode,
                productName: product.isEmpty ? nil : product,
                cargoType: cargoType.rawValue,
                dangerousGoodsStatus: classification.wireStatus,
                classificationSource: classification.wireSource,
                classificationEvidenceRef: classification.wireEvidenceRef,
                unNumber: classification.wireUnNumber,
                properShippingName: classification.wireProperShippingName,
                hazmatClass: classification.wireHazmatClass,
                packingGroupStatus: classification.wirePackingGroupStatus,
                packingGroup: classification.wirePackingGroup,
                technicalName: classification.wireTechnicalName,
                emergencyPhone: classification.wireEmergencyPhone,
                subsidiaryHazards: classification.wireSubsidiaryHazards,
                packagingType: classification.wirePackagingType,
                equipmentType: resolvedEquipmentType,
                quantity: classificationQuantity,
                quantityUnit: classificationQuantityUnit,
                temperatureMin: reeferTempLow,
                temperatureMax: reeferTempHigh,
                temperatureUnit: (reeferTempLow != nil || reeferTempHigh != nil) ? "F" : nil,
                operationalFacts: facts.isEmpty ? nil : facts
            )
        )

        industryAssessmentId = response.assessmentId
        industryAssessmentStatus = response.status
        industryAssessmentWarnings = response.result.warnings
        if response.status == "blocked" {
            let detail = response.result.blockingReasons.joined(separator: " ")
            throw NSError(
                domain: "EusoTrip.IndustryVertical",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "This industry workflow is blocked." : detail]
            )
        }
        if response.status == "needs_input" {
            let fields = response.result.requiredInputs.joined(separator: ", ")
            throw NSError(
                domain: "EusoTrip.IndustryVertical",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        fields.isEmpty ? "Complete the industry workflow inputs." : "Complete: \(fields)."
                ]
            )
        }
        if requireReviewAcknowledgement
            && response.status == "requires_review"
            && !industryReviewAcknowledged {
            throw NSError(
                domain: "EusoTrip.IndustryVertical",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Review and acknowledge the jurisdiction coverage before posting."
                ]
            )
        }
    }

    func prepareIndustryAssessmentForReview() async {
        guard industrySectorId != nil else { return }
        isAssessingIndustry = true
        industryAssessmentError = nil
        do {
            try await refreshIndustryAssessment(requireReviewAcknowledgement: false)
        } catch {
            industryAssessmentError = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
        isAssessingIndustry = false
    }

    func submit() async {
        do {
            try validate()
        } catch {
            postError = (error as? ValidationError)?.errorDescription
                     ?? error.localizedDescription
            return
        }
        // 2026-08-07 — cargo classification. Mirror the identity the poster
        // typed, then refuse with the exact missing inputs. No derived
        // determination is ever submitted on the poster's behalf.
        mirrorIdentityIntoClassification()
        if let reason = classificationBlockReason {
            postError = reason
            return
        }
        isPosting = true; postError = nil
        do {
            try await refreshIndustryAssessment()
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
                let productName: String?; let category: String?
                // Cargo-classification attestation — REQUIRED by
                // `shippers.create`; the post is refused without it.
                let dangerousGoodsStatus: String
                let classificationSource: String?
                let classificationEvidenceRef: String?
                let properShippingName: String?
                let packingGroupStatus: String?
                let packingGroup: String?
                let technicalName: String?
                let emergencyPhone: String?
                let packagingType: String?
                let subsidiaryHazards: [String]?
                let unNumber: String?; let hazmatClass: String?
                let tempMin: Double?; let tempMax: Double?; let tempUnit: String?
                let preCoolRequired: Bool?; let continuousMonitoring: Bool?
                let rate: Double?; let weight: Double?; let notes: String?; let pickupDate: String?
                // `shippers.create` classifies against `quantity ?? weight`
                // with `quantityUnit ?? weightUnit`. This wizard's cargo
                // figure is a WEIGHT, so it travels as weight + weightUnit —
                // `quantity`/`quantityUnit` are deliberately not sent, because
                // the server writes `quantityUnit` into the load's VOLUME unit
                // column and a mass would be the wrong fact there.
                let weightUnit: String?
                let transportMode: String?
                let originCountry: String?; let destinationCountry: String?
                let isCrossBorder: Bool?
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
                /// The operational facts the assessment was made against. The
                /// server re-normalizes both objects and refuses the post when
                /// they differ, so this must be byte-for-byte the same set
                /// sent to `industryVerticals.assessDraft`.
                let verticalData:         [String: IndustryOperationalFact]?
                let industrySectorId:     String?
                let industryVerticalAssessmentId: String?
                let industryVerticalReviewAcknowledged: Bool?
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
                    productName: commodity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : commodity.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: industrySectorId ?? vertical?.rawValue,
                    dangerousGoodsStatus: classification.wireStatus,
                    classificationSource: classification.wireSource,
                    classificationEvidenceRef: classification.wireEvidenceRef,
                    properShippingName: classification.wireProperShippingName,
                    packingGroupStatus: classification.wirePackingGroupStatus,
                    packingGroup: classification.wirePackingGroup,
                    technicalName: classification.wireTechnicalName,
                    emergencyPhone: classification.wireEmergencyPhone,
                    packagingType: classification.wirePackagingType,
                    subsidiaryHazards: classification.wireSubsidiaryHazards,
                    unNumber: classification.wireUnNumber,
                    hazmatClass: classification.wireHazmatClass,
                    tempMin: reeferTempLow,
                    tempMax: reeferTempHigh,
                    tempUnit: (reeferTempLow != nil || reeferTempHigh != nil) ? "F" : nil,
                    preCoolRequired: preCoolRequired ? true : nil,
                    continuousMonitoring: continuousMode ? true : nil,
                    rate: rate,
                    weight: weight,
                    notes: composedNotes().isEmpty ? nil : composedNotes(),
                    pickupDate: pickupDate.map { iso.string(from: $0) },
                    weightUnit: classificationQuantityUnit,
                    transportMode: mode.rawValue,
                    originCountry: exactCountryCode(originCountry),
                    destinationCountry: exactCountryCode(destinationCountry),
                    isCrossBorder: isCrossBorder ? true : nil,
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
                    verticalData:          submittedOperationalFacts.isEmpty
                        ? nil
                        : submittedOperationalFacts,
                    industrySectorId:      industrySectorId,
                    industryVerticalAssessmentId: industryAssessmentId,
                    industryVerticalReviewAcknowledged:
                        industryAssessmentStatus == "requires_review"
                            ? industryReviewAcknowledged
                            : nil,
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
