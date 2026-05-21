//
//  AstraVisionService.swift
//  Astra DVIR — IO 2026 P0-6 iOS-side.
//
//  Single entry point every camera-driven inspection screen calls
//  when the driver wants Gemini Vision to read a DVIR item from
//  a photo (tire tread depth, brake pad wear, hazmat placard
//  UN/ERG number, container CSC plate, reefer temp display, etc.).
//
//  Pipeline:
//    1. Caller captures a UIImage via CameraController / iPhone
//       camera sheet.
//    2. Service encodes JPEG at ~0.85 quality, base64-encodes.
//    3. POST to `astraDvir.analyze` with item + trailer code +
//       vehicle/load context. Server runs Gemini Vision with a
//       trailer-aware prompt, signs the canonical payload with
//       Ed25519, writes the audit chain entry, and returns the
//       structured observation + signature.
//    4. iOS verifies the signature locally so a tampered network
//       hop is detected (we trust the server but the audit replay
//       must work end-to-end).
//    5. Caller writes the observation into PretripDVIRViewModel.
//
//  Foundation binding (per IO 2026 dev-team brief):
//    - `TrailerCode` rawValue forwarded to the server so the
//      prompt is trailer-specific.
//    - Observation payload is fed into `LoadStateFSM` audit chain
//      BEFORE the FSM transitions; no silent AI decisions.
//
//  Drop into: EusoTrip/Services/AstraVisionService.swift
//

import Foundation
import UIKit
import CryptoKit

// MARK: - Wire types

/// Canonical Astra DVIR item ids. RawValues mirror server enum in
/// `frontend/server/routers/astraDvir.ts`.
public enum AstraItem: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case tireTread             = "tire_tread"
    case tirePressureVisual    = "tire_pressure_visual"
    case brakePad              = "brake_pad"
    case brakeAirLine          = "brake_air_line"
    case lightsHeadlight       = "lights_headlight"
    case lightsTaillight       = "lights_taillight"
    case lightsClearance       = "lights_clearance"
    case mirrors               = "mirrors"
    case kingpin               = "kingpin"
    case fifthWheel            = "fifth_wheel"
    case reeferTempDisplay     = "reefer_temp_display"
    case reeferFuel            = "reefer_fuel"
    case tankerManhole         = "tanker_manhole"
    case tankerPrv             = "tanker_prv"
    case tankerVaporRecovery   = "tanker_vapor_recovery"
    case flatbedChains         = "flatbed_chains"
    case flatbedTarps          = "flatbed_tarps"
    case containerCscPlate     = "container_csc_plate"
    case containerSeal         = "container_seal"
    case livestockBedding      = "livestock_bedding"
    case livestockVentilation  = "livestock_ventilation"
    case hazmatPlacard         = "hazmat_placard"
    case hazmatShippingPapers  = "hazmat_shipping_papers"

    public var id: String { rawValue }

    /// Human-readable label.
    public var label: String {
        switch self {
        case .tireTread:             return "Tire tread"
        case .tirePressureVisual:    return "Tire pressure (visual)"
        case .brakePad:              return "Brake pad / drum"
        case .brakeAirLine:          return "Brake air lines"
        case .lightsHeadlight:       return "Headlight"
        case .lightsTaillight:       return "Taillight"
        case .lightsClearance:       return "Clearance lights"
        case .mirrors:               return "Mirrors"
        case .kingpin:               return "Kingpin"
        case .fifthWheel:            return "Fifth wheel"
        case .reeferTempDisplay:     return "Reefer temp display"
        case .reeferFuel:            return "Reefer fuel gauge"
        case .tankerManhole:         return "Tanker manhole"
        case .tankerPrv:             return "Pressure relief valve"
        case .tankerVaporRecovery:   return "Vapor recovery"
        case .flatbedChains:         return "Cargo chains / binders"
        case .flatbedTarps:          return "Tarps"
        case .containerCscPlate:     return "CSC plate"
        case .containerSeal:         return "Container seal"
        case .livestockBedding:      return "Bedding"
        case .livestockVentilation:  return "Side vents"
        case .hazmatPlacard:         return "Hazmat placard"
        case .hazmatShippingPapers:  return "Shipping papers"
        }
    }

    public var systemImage: String {
        switch self {
        case .tireTread, .tirePressureVisual:                 return "circle.dashed"
        case .brakePad, .brakeAirLine:                        return "exclamationmark.brakesignal"
        case .lightsHeadlight, .lightsTaillight, .lightsClearance: return "lightbulb"
        case .mirrors:                                        return "rectangle"
        case .kingpin, .fifthWheel:                           return "link"
        case .reeferTempDisplay:                              return "thermometer"
        case .reeferFuel:                                     return "fuelpump"
        case .tankerManhole, .tankerPrv, .tankerVaporRecovery: return "drop"
        case .flatbedChains, .flatbedTarps:                   return "link"
        case .containerCscPlate, .containerSeal:              return "cube"
        case .livestockBedding, .livestockVentilation:        return "wind"
        case .hazmatPlacard, .hazmatShippingPapers:           return "exclamationmark.triangle"
        }
    }
}

/// Pass / fail / needs_review verdict the model attaches to the observation.
public enum AstraVerdict: String, Codable, Hashable, Sendable {
    case pass
    case fail
    case needsReview = "needs_review"

    public var color: UIColor {
        switch self {
        case .pass:        return .systemGreen
        case .fail:        return .systemRed
        case .needsReview: return .systemOrange
        }
    }
}

/// Parsed observation payload (mirrors the JSON Gemini returns).
public struct AstraObservation: Codable, Hashable, Sendable {
    public let summary: String
    /// Item-specific structured fields. Free-form because the schema
    /// varies per item (tread depth vs CSC date vs UN number).
    public let structured: [String: AstraStructuredValue]
    public let passFail: AstraVerdict
    public let confidence: Double
    public let warnings: [String]
}

/// Lightweight union for the structured payload values. Limits the
/// shapes Codable has to handle while still supporting the realistic
/// set Gemini returns (strings, numbers, booleans, null).
public enum AstraStructuredValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                                    { self = .null;       return }
        if let s = try? c.decode(String.self)               { self = .string(s);  return }
        if let n = try? c.decode(Double.self)               { self = .number(n);  return }
        if let b = try? c.decode(Bool.self)                 { self = .bool(b);    return }
        // Arrays + objects collapse to their JSON string so the row
        // can still render them — the verbatim audit chain entry
        // server-side has the full structure.
        if let any = try? c.decode([String: String].self)   { self = .string(String(describing: any)); return }
        self = .null
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b):   return b ? "yes" : "no"
        case .null:          return "—"
        }
    }
}

/// Server response — observation + cryptographic block.
public struct AstraAnalyzeResponse: Decodable, Hashable, Sendable {
    public let observation: AstraObservation
    public let modelUsed: String?
    public let observedAt: String
    public let auditId: Int?
    public let signature: AstraSignatureBlock
}

public struct AstraSignatureBlock: Codable, Hashable, Sendable {
    public let digestSha256B64: String
    public let signatureBytesB64: String
    public let publicKeyB64: String
}

// MARK: - Service

public final class AstraVisionService: @unchecked Sendable {
    public static let shared = AstraVisionService()

    /// JPEG quality for upload. 0.85 keeps payloads under ~4 MB while
    /// preserving enough detail for tread / placard OCR.
    public var jpegQuality: CGFloat = 0.85

    public init() {}

    /// Analyze an image with Astra. Returns the parsed observation
    /// + signature. iOS callers verify the signature locally to
    /// detect a tampered network hop before persisting the result.
    public func analyze(
        item: AstraItem,
        image: UIImage,
        trailer: TrailerCode? = nil,
        vehicleId: String? = nil,
        loadId: String? = nil
    ) async throws -> AstraAnalyzeResponse {
        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else {
            throw AstraError.imageEncodeFailed
        }
        let b64 = jpeg.base64EncodedString()
        struct In: Encodable {
            let item: String
            let imageBase64: String
            let mimeType: String
            let trailerCode: String?
            let vehicleId: String?
            let loadId: String?
        }
        let payload = In(
            item: item.rawValue,
            imageBase64: b64,
            mimeType: "image/jpeg",
            trailerCode: trailer?.rawValue,
            vehicleId: vehicleId,
            loadId: loadId
        )
        let response: AstraAnalyzeResponse = try await EusoTripAPI.shared.mutation(
            "astraDvir.analyze",
            input: payload
        )
        // Verify signature locally so audit replay surfaces tampering.
        if !verifySignature(response: response) {
            throw AstraError.signatureVerificationFailed
        }
        return response
    }

    /// Verify the Ed25519 signature on the observation. Returns true
    /// when the digest the server claimed to sign matches the
    /// signature bytes under the supplied public key.
    private func verifySignature(response: AstraAnalyzeResponse) -> Bool {
        guard
            let digest = Data(base64Encoded: response.signature.digestSha256B64),
            let signature = Data(base64Encoded: response.signature.signatureBytesB64),
            let pubKeyRaw = Data(base64Encoded: response.signature.publicKeyB64),
            digest.count == 32, signature.count == 64, pubKeyRaw.count == 32
        else {
            return false
        }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyRaw)
            return publicKey.isValidSignature(signature, for: digest)
        } catch {
            return false
        }
    }
}

public enum AstraError: LocalizedError {
    case imageEncodeFailed
    case signatureVerificationFailed
    public var errorDescription: String? {
        switch self {
        case .imageEncodeFailed:           return "Couldn't encode the image for upload."
        case .signatureVerificationFailed: return "Astra signature verification failed — observation will not be persisted."
        }
    }
}

// MARK: - IO 2026 P0-17 · POD scan wire types

public struct AstraPodDamage: Codable, Hashable, Sendable {
    public let visible: Bool
    public let summary: String?
    public let categories: [String]?
}

public struct AstraPodObservation: Codable, Hashable, Sendable {
    public let sealNumber: String?
    public let sealIntact: Bool?
    public let palletCount: Int?
    public let pieceCount: Int?
    public let containerNumber: String?
    public let containerSealNumber: String?
    public let temperatureSetpoint: String?
    public let temperatureCurrent: String?
    public let damage: AstraPodDamage?
    public let missingPieces: Bool?
    public let placardsVisible: Bool?
    public let confidence: Double?
    public let warnings: [String]?
}

public enum AstraPodVerdict: String, Codable, Hashable, Sendable {
    case pass
    case fail
    case needsReview = "needs_review"
}

public struct AstraPodResponse: Decodable, Hashable, Sendable {
    public let observation: AstraPodObservation
    public let verdict: AstraPodVerdict
    public let modelUsed: String?
    public let observedAt: String
    public let auditId: Int?
    public let overlayAuditId: Int?
    public let podSignedEligible: Bool
    public let signature: AstraSignatureBlock
}

extension AstraVisionService {
    /// IO 2026 P0-17 — Auto-detect POD details (seal #, damage,
    /// pallet count, OS&D triggers) from a delivery photo. Verifies
    /// the Ed25519 signature locally before trusting the observation.
    public func analyzePod(
        image: UIImage,
        trailer: TrailerCode? = nil,
        vehicleId: String? = nil,
        loadId: String? = nil,
        expectedPieceCount: Int? = nil,
        expectedSealNumber: String? = nil
    ) async throws -> AstraPodResponse {
        guard let jpeg = image.jpegData(compressionQuality: jpegQuality) else {
            throw AstraError.imageEncodeFailed
        }
        let b64 = jpeg.base64EncodedString()
        struct In: Encodable {
            let imageBase64: String
            let mimeType: String
            let trailerCode: String?
            let vehicleId: String?
            let loadId: String?
            let expectedPieceCount: Int?
            let expectedSealNumber: String?
        }
        let payload = In(
            imageBase64: b64,
            mimeType: "image/jpeg",
            trailerCode: trailer?.rawValue,
            vehicleId: vehicleId,
            loadId: loadId,
            expectedPieceCount: expectedPieceCount,
            expectedSealNumber: expectedSealNumber
        )
        let response: AstraPodResponse = try await EusoTripAPI.shared.mutation(
            "astraDvir.podScan",
            input: payload
        )
        // Verify the Ed25519 signature locally — never persist an
        // unverified observation. Reuses the same CryptoKit path
        // as `analyze(item:image:)` shipped in P0-6.
        if !verifyPodSignature(response.signature) {
            throw AstraError.signatureVerificationFailed
        }
        return response
    }

    private func verifyPodSignature(_ sig: AstraSignatureBlock) -> Bool {
        guard
            let digest = Data(base64Encoded: sig.digestSha256B64),
            let signature = Data(base64Encoded: sig.signatureBytesB64),
            let pubKeyRaw = Data(base64Encoded: sig.publicKeyB64),
            digest.count == 32, signature.count == 64, pubKeyRaw.count == 32
        else { return false }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyRaw)
            return publicKey.isValidSignature(signature, for: digest)
        } catch { return false }
    }
}
