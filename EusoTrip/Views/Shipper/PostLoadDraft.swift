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

    // MARK: - Step 3 · Pricing

    @Published var rate: Double? = nil
    @Published var fuelSurchargeRate: Double? = nil
    @Published var accessorialsAllowed: [String] = []
    @Published var contractTier: String = ""
    @Published var notes: String = ""

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
        weight = nil; commodity = ""
        unNumber = ""; hazmatClass = ""; packingGroup = ""
        properShippingName = ""; ergGuide = nil; chemtrecPhone = ""
        reeferTempLow = nil; reeferTempHigh = nil
        preCoolRequired = false; continuousMode = true
        rate = nil; fuelSurchargeRate = nil
        accessorialsAllowed = []; contractTier = ""; notes = ""
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
            struct In: Encodable {
                let origin: String; let destination: String; let cargoType: String
                let rate: Double?; let weight: Double?; let notes: String?; let pickupDate: String?
                let originLat: Double?; let originLng: Double?
                let destLat:   Double?; let destLng:   Double?
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
                    destLat:   destLat,   destLng:   destLng
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
        return lines.joined(separator: "\n")
    }

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
