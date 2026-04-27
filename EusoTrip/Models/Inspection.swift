//
//  Inspection.swift
//  EusoTrip — Codable shapes for inspections router (DVIR / pre-trip / post-trip).
//
//  Authority: frontend/server/routers/inspections.ts
//    inspections.getTemplate   query    → InspectionTemplate
//    inspections.submit        mutation → InspectionSubmitResponse
//    inspections.getHistory    query    → [InspectionHistoryEntry]
//    inspections.getPrevious   query    → [InspectionPreviousEntry]
//    inspections.getOpenDefects query   → [InspectionDefectEntry]
//    inspections.createDVIR    mutation → DVIRCreateResponse
//    inspections.getDVIRHistory query   → [DVIRHistoryEntry]
//    inspections.getDVIRCategories query → [DVIRCategory]
//
//  Per 49 CFR 396.11 – 396.13.
//

import Foundation

// MARK: - Type enum

enum InspectionType: String, Codable, Hashable, CaseIterable {
    case preTrip  = "pre_trip"
    case postTrip = "post_trip"
    case dvir     = "dvir"

    var displayName: String {
        switch self {
        case .preTrip:  return "Pre-trip"
        case .postTrip: return "Post-trip"
        case .dvir:     return "DVIR"
        }
    }
}

// MARK: - Item status

enum InspectionItemStatus: String, Codable, Hashable {
    case pass
    case fail
    case na
}

// MARK: - Template (GET inspections.getTemplate)

/// Top-level template response.
struct InspectionTemplate: Codable, Hashable {
    let type: String
    let categories: [InspectionCategory]
}

/// A group of related inspection points (Engine, Brakes, Tires, etc.).
struct InspectionCategory: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let items: [InspectionTemplateItem]
}

/// A single checklist point inside a category.
struct InspectionTemplateItem: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let required: Bool
}

// MARK: - Demo fixture (offline-preview fallback)
//
// When the device has no route to `inspections.getTemplate` (simulator without
// the dev API, first-launch offline, etc.) the Pre-trip DVIR view model falls
// back to this fixture so the Figma-faithful walkthrough keeps advancing
// through the state machine (010 → 011 → 012 → …) instead of dead-ending on
// a "Couldn't load DVIR" error banner. Mirrors the shape of the production
// FMCSA 49 CFR 396.11 pre-trip walkaround.
//
extension InspectionTemplate {
    static func demoPreTrip() -> InspectionTemplate {
        InspectionTemplate(
            type: InspectionType.preTrip.rawValue,
            categories: [
                InspectionCategory(
                    id: "engine",
                    name: "Engine Compartment",
                    items: [
                        InspectionTemplateItem(id: "oil_level",         name: "Oil Level",              required: true),
                        InspectionTemplateItem(id: "coolant_level",     name: "Coolant Level",          required: true),
                        InspectionTemplateItem(id: "power_steering",    name: "Power Steering Fluid",   required: true),
                        InspectionTemplateItem(id: "belts_hoses",       name: "Belts & Hoses",          required: true),
                        InspectionTemplateItem(id: "air_compressor",    name: "Air Compressor",         required: true),
                    ]
                ),
                InspectionCategory(
                    id: "brakes",
                    name: "Brake System",
                    items: [
                        InspectionTemplateItem(id: "service_brakes",    name: "Service Brakes",         required: true),
                        InspectionTemplateItem(id: "parking_brake",     name: "Parking Brake",          required: true),
                        InspectionTemplateItem(id: "air_pressure",      name: "Air Pressure Build-up",  required: true),
                        InspectionTemplateItem(id: "brake_chambers",    name: "Brake Chambers",         required: true),
                        InspectionTemplateItem(id: "slack_adjusters",   name: "Slack Adjusters",        required: true),
                    ]
                ),
                InspectionCategory(
                    id: "tires_wheels",
                    name: "Tires, Wheels & Rims",
                    items: [
                        InspectionTemplateItem(id: "tread_depth",       name: "Tread Depth",            required: true),
                        InspectionTemplateItem(id: "tire_pressure",     name: "Tire Pressure",          required: true),
                        InspectionTemplateItem(id: "rim_condition",     name: "Rim Condition",          required: true),
                        InspectionTemplateItem(id: "lug_nuts",          name: "Lug Nuts",               required: true),
                    ]
                ),
                InspectionCategory(
                    id: "lights",
                    name: "Lights & Reflectors",
                    items: [
                        InspectionTemplateItem(id: "headlights",        name: "Headlights (high/low)",  required: true),
                        InspectionTemplateItem(id: "turn_signals",      name: "Turn Signals",           required: true),
                        InspectionTemplateItem(id: "brake_lights",      name: "Brake Lights",           required: true),
                        InspectionTemplateItem(id: "clearance_markers", name: "Clearance Markers",      required: true),
                        InspectionTemplateItem(id: "reflectors",        name: "Reflectors",             required: false),
                    ]
                ),
                InspectionCategory(
                    id: "coupling",
                    name: "Coupling System",
                    items: [
                        InspectionTemplateItem(id: "fifth_wheel",       name: "Fifth Wheel",            required: true),
                        InspectionTemplateItem(id: "king_pin",          name: "King Pin / Apron",       required: true),
                        InspectionTemplateItem(id: "locking_jaws",      name: "Locking Jaws",           required: true),
                        InspectionTemplateItem(id: "air_glad_hands",    name: "Air & Electric Lines",   required: true),
                    ]
                ),
                InspectionCategory(
                    id: "cab",
                    name: "In-cab Controls",
                    items: [
                        InspectionTemplateItem(id: "horn",              name: "Horn",                   required: true),
                        InspectionTemplateItem(id: "wipers_washers",    name: "Wipers & Washers",       required: true),
                        InspectionTemplateItem(id: "mirrors",           name: "Mirrors",                required: true),
                        InspectionTemplateItem(id: "seat_belt",         name: "Seat Belt",              required: true),
                        InspectionTemplateItem(id: "gauges",            name: "Gauges & Warning Lamps", required: true),
                        InspectionTemplateItem(id: "eld_device",        name: "ELD Device",             required: true),
                    ]
                ),
                InspectionCategory(
                    id: "emergency",
                    name: "Emergency Equipment",
                    items: [
                        InspectionTemplateItem(id: "fire_extinguisher", name: "Fire Extinguisher",      required: true),
                        InspectionTemplateItem(id: "triangles",         name: "Warning Triangles (3)",  required: true),
                        InspectionTemplateItem(id: "spare_fuses",       name: "Spare Electrical Fuses", required: false),
                    ]
                ),
                InspectionCategory(
                    id: "trailer",
                    name: "Trailer",
                    items: [
                        InspectionTemplateItem(id: "trailer_brakes",    name: "Trailer Brakes",         required: true),
                        InspectionTemplateItem(id: "trailer_lights",    name: "Trailer Lights",         required: true),
                        InspectionTemplateItem(id: "doors_hinges",      name: "Doors & Hinges",         required: true),
                        InspectionTemplateItem(id: "load_securement",   name: "Load Securement",        required: true),
                        InspectionTemplateItem(id: "mud_flaps",         name: "Mud Flaps",              required: false),
                    ]
                ),
            ]
        )
    }
}

// MARK: - Submission (POST inspections.submit)

/// Payload driven by the Pre-Trip DVIR view — matches `inspectionItemSchema`.
struct InspectionSubmissionItem: Codable, Hashable {
    let id: String
    let category: String
    let name: String
    let status: InspectionItemStatus
    let notes: String?
    let photoUrl: String?
}

struct InspectionSubmission: Encodable {
    let vehicleId: String
    let trailerId: String?
    let type: String
    let odometer: Int
    let items: [InspectionSubmissionItem]
    let defectsFound: Bool
    let defectsCorrected: Bool?
    let safeToOperate: Bool
    let driverSignature: String
    let notes: String?
}

struct InspectionSubmitResponse: Codable, Hashable {
    let id: String
    let status: String
    let submittedAt: String
    let submittedBy: String?
    let vehicleId: String
    let type: String
    let defectsFound: Bool
    let safeToOperate: Bool
}

// MARK: - History / Previous / Defects

struct InspectionHistoryEntry: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let date: String
    let driver: String?
    let defectsFound: Bool
    let defectsCorrected: Bool?
    let safeToOperate: Bool
    let status: String?
}

struct InspectionPreviousEntry: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let date: String
    let status: String
    let defects: Int
}

struct InspectionDefectEntry: Codable, Hashable, Identifiable {
    let id: String
    let vehicleId: String
    let inspectionId: String
    let category: String
    let item: String
    let description: String
    let severity: String
    let reportedAt: String
    let status: String
}

// MARK: - DVIR (createDVIR / getDVIRHistory / getDVIRCategories)

struct DVIRCreateResponse: Codable, Hashable {
    let success: Bool
    let dvirId: Int?
    let reportType: String?
    let defectsCount: Int?
    let error: String?
}

struct DVIRHistoryEntry: Codable, Hashable {
    let id: Int?
    let vehicleId: Int?
    let driverId: Int?
    let reportType: String?
    let reportDate: String?
    let odometerMiles: Int?
    let overallCondition: String?
    let defectsFound: Int?
    let status: String?
    let unitNumber: String?
    let make: String?
    let model: String?
}

struct DVIRCategory: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let group: String
}
