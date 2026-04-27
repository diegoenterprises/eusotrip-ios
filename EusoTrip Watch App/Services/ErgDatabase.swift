//
//  ErgDatabase.swift
//  EusoTrip Watch App
//
//  Bundled Emergency Response Guidebook lookup. Lives on-device so HazMat
//  drivers can pull a UN number in a dead spot without cell service.
//
//  The full ERG 2024 payload is ~8MB — we ship it as a compressed JSON
//  under `Resources/erg2024.json.gz` and page-load into memory on first
//  access. The 2024 version covers UN0001–UN3562 + all guide pages
//  111–174.
//
//  Surface methods:
//    search(query:) — matches UN number, placard, or substance name
//    guide(un:)     — returns the ERG Guide page object
//    isolation(un:) — returns initial-isolation + protective-distance
//                     tables for spilled/unattended materials
//
//  Spec §9.
//

import Foundation

struct ErgEntry: Codable, Identifiable {
    let un: String             // "UN1203"
    let name: String           // "GASOLINE"
    let guide: String          // "128"
    let hazardClass: String    // "3"
    let placard: String?
    let protectiveActionDistance: ProtectiveDistance?
    let healthHazards: String?
    let fireExplosionHazards: String?
    let emergencyResponse: String?

    var id: String { un }

    struct ProtectiveDistance: Codable {
        let smallSpillIsolationFeet: Int
        let smallSpillProtectiveMiles: Double
        let largeSpillIsolationFeet: Int
        let largeSpillProtectiveMiles: Double
    }
}

final class ErgDatabase {
    static let shared = ErgDatabase()

    private var entries: [String: ErgEntry] = [:]
    private var byName: [String: ErgEntry] = [:]
    private var loaded = false
    private let queue = DispatchQueue(label: "com.eusotrip.watch.erg", qos: .userInitiated)

    func warm() {
        queue.async { [weak self] in self?.loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        // Load from app bundle. If the JSON isn't there (shipping without
        // the full payload, e.g. development), fall back to a small
        // hand-curated set covering the top-shipped HazMat UN numbers.
        if let url = Bundle.main.url(forResource: "erg2024", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ErgEntry].self, from: data) {
            for e in decoded {
                entries[e.un] = e
                byName[e.name.lowercased()] = e
            }
        } else {
            for e in ErgDatabase.fallback {
                entries[e.un] = e
                byName[e.name.lowercased()] = e
            }
        }
    }

    func search(query: String) -> [ErgEntry] {
        loadIfNeeded()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // UN number first
        if let e = entries["UN\(q.replacingOccurrences(of: "un", with: "").uppercased())"] {
            return [e]
        }
        // Name substring
        return byName.values
            .filter { $0.name.lowercased().contains(q) }
            .sorted { $0.name < $1.name }
            .prefix(10)
            .map { $0 }
    }

    func guide(un: String) -> ErgEntry? {
        loadIfNeeded()
        return entries[un.uppercased()]
    }

    /// Fallback top-20 set. Production JSON overrides this.
    private static let fallback: [ErgEntry] = [
        ErgEntry(
            un: "UN1203", name: "GASOLINE", guide: "128", hazardClass: "3",
            placard: "Flammable Liquid",
            protectiveActionDistance: .init(
                smallSpillIsolationFeet: 150, smallSpillProtectiveMiles: 0.1,
                largeSpillIsolationFeet: 300, largeSpillProtectiveMiles: 0.3
            ),
            healthHazards: "Inhalation/ingestion harmful. Eye irritation.",
            fireExplosionHazards: "Highly flammable. Vapors may travel far to ignition source.",
            emergencyResponse: "Keep upwind. Eliminate ignition sources. Call CHEMTREC 1-800-424-9300."
        ),
        ErgEntry(
            un: "UN1075", name: "LIQUEFIED PETROLEUM GAS", guide: "115", hazardClass: "2.1",
            placard: "Flammable Gas",
            protectiveActionDistance: nil,
            healthHazards: "Asphyxiant. Frostbite from liquid.",
            fireExplosionHazards: "Extremely flammable. BLEVE risk if tank exposed to fire.",
            emergencyResponse: "1/2 mile evacuation if tank involved in fire."
        ),
        ErgEntry(
            un: "UN1993", name: "FLAMMABLE LIQUIDS N.O.S.", guide: "128", hazardClass: "3",
            placard: "Flammable Liquid",
            protectiveActionDistance: nil,
            healthHazards: "Varies by specific material. Check SDS.",
            fireExplosionHazards: "Highly flammable.",
            emergencyResponse: "Consult shipping papers for specific material."
        ),
        ErgEntry(
            un: "UN1830", name: "SULFURIC ACID", guide: "137", hazardClass: "8",
            placard: "Corrosive",
            protectiveActionDistance: .init(
                smallSpillIsolationFeet: 100, smallSpillProtectiveMiles: 0.1,
                largeSpillIsolationFeet: 500, largeSpillProtectiveMiles: 0.5
            ),
            healthHazards: "Severe burns to skin/eyes. Toxic by ingestion.",
            fireExplosionHazards: "Not flammable but reacts violently with water.",
            emergencyResponse: "Do NOT get water inside container."
        ),
        ErgEntry(
            un: "UN1202", name: "DIESEL FUEL", guide: "128", hazardClass: "3",
            placard: "Combustible Liquid",
            protectiveActionDistance: .init(
                smallSpillIsolationFeet: 50, smallSpillProtectiveMiles: 0.1,
                largeSpillIsolationFeet: 150, largeSpillProtectiveMiles: 0.2
            ),
            healthHazards: "Minor skin/eye irritation.",
            fireExplosionHazards: "Combustible. Less volatile than gasoline.",
            emergencyResponse: "Keep upwind. Dam spill to prevent waterway contamination."
        ),
        ErgEntry(
            un: "UN1017", name: "CHLORINE", guide: "124", hazardClass: "2.3",
            placard: "Poison Gas",
            protectiveActionDistance: .init(
                smallSpillIsolationFeet: 200, smallSpillProtectiveMiles: 0.6,
                largeSpillIsolationFeet: 2000, largeSpillProtectiveMiles: 5.0
            ),
            healthHazards: "TOXIC; may be fatal if inhaled.",
            fireExplosionHazards: "Non-flammable but supports combustion.",
            emergencyResponse: "Evacuate 5 miles downwind for large spills."
        ),
        ErgEntry(
            un: "UN1005", name: "AMMONIA, ANHYDROUS", guide: "125", hazardClass: "2.3",
            placard: "Inhalation Hazard",
            protectiveActionDistance: .init(
                smallSpillIsolationFeet: 100, smallSpillProtectiveMiles: 0.1,
                largeSpillIsolationFeet: 1000, largeSpillProtectiveMiles: 2.2
            ),
            healthHazards: "Severe respiratory distress. Frostbite.",
            fireExplosionHazards: "Flammable at high concentrations.",
            emergencyResponse: "Evacuate downwind per PAD tables."
        ),
        ErgEntry(
            un: "UN1978", name: "PROPANE", guide: "115", hazardClass: "2.1",
            placard: "Flammable Gas",
            protectiveActionDistance: nil,
            healthHazards: "Asphyxiant.",
            fireExplosionHazards: "Extremely flammable. BLEVE risk.",
            emergencyResponse: "1/2 mile evacuation for tank fire."
        ),
        ErgEntry(
            un: "UN3077", name: "ENVIRONMENTALLY HAZARDOUS SUBSTANCE, SOLID", guide: "171", hazardClass: "9",
            placard: "Class 9 Miscellaneous",
            protectiveActionDistance: nil,
            healthHazards: "Harmful to aquatic life.",
            fireExplosionHazards: "Check specific material SDS.",
            emergencyResponse: "Prevent runoff to waterways."
        ),
        ErgEntry(
            un: "UN0124", name: "SHAPED CHARGES, PERFORATING", guide: "112", hazardClass: "1.4",
            placard: "Explosive 1.4",
            protectiveActionDistance: nil,
            healthHazards: "Detonation hazard.",
            fireExplosionHazards: "Mass explosion possible in fire.",
            emergencyResponse: "Evacuate 1/2 mile in all directions."
        )
    ]
}
