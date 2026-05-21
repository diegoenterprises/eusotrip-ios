//
//  ERGLookupService.swift
//  Hazmat placard scan + ERG multi-turn — IO 2026 P0-7.
//
//  Wraps two server endpoints with iOS-friendly response types:
//    - `astraDvir.placardScan` — Gemini Vision OCR + ERG database
//      JOIN + Ed25519-signed audit chain entry. Returns the
//      structured material + guide + a TTS-ready spokenReply.
//    - `erg.askFollowUp` — multi-turn ERG conversation grounded
//      in the canonical guide content. Maintains a thought-signature
//      cache so a chain of follow-up questions resumes the model's
//      reasoning state cheaply (P0-3 pattern).
//
//  Foundation binding: every placard scan that resolves to a UN
//  number AND has `isReadable == true` ALSO writes a
//  `HazmatOverlay.placardsAffixed` audit entry server-side, which
//  the iOS LoadStateFSM can read back to advance the overlay set
//  to `placardsAffixed`. The audit signature anchors the overlay
//  to a verified photo — no manual override.
//
//  Drop into: EusoTrip/Services/ERGLookupService.swift
//

import Foundation
import UIKit
import CryptoKit

// MARK: - Wire types

public struct PlacardOCR: Codable, Hashable, Sendable {
    public let unNumber: String?
    public let hazardClassNumber: String?
    public let placardColor: String?
    public let mountedSide: String?
    public let isReadable: Bool
    public let warnings: [String]
}

public struct ERGMaterial: Codable, Hashable, Sendable {
    public let unNumber: String
    public let name: String
    public let hazardClass: String
    public let guideNumber: Int
    public let isTIH: Bool
    public let isWR: Bool
    public let alternateNames: [String]
}

public struct ERGGuideBundle: Codable, Hashable, Sendable {
    public let title: String?
    /// Raw structured guide blocks — `potentialHazards`,
    /// `publicSafety`, `emergencyResponse`. Surfaced as
    /// `[String: AstraStructuredValue]` so any shape (object or
    /// array-of-strings) round-trips.
    public let potentialHazards: AstraStructuredValue?
    public let publicSafety: AstraStructuredValue?
    public let emergencyResponse: AstraStructuredValue?

    enum CodingKeys: String, CodingKey {
        case title, potentialHazards, publicSafety, emergencyResponse
    }
}

public struct PlacardScanResponse: Decodable, Hashable, Sendable {
    public let ocr: PlacardOCR
    public let unNumber: String?
    public let material: ERGMaterial?
    public let guide: ERGGuideBundle?
    public let spokenReply: String
    public let modelUsed: String?
    public let observedAt: String
    public let auditId: Int?
    public let overlayAuditId: Int?
    public let placardsAffixed: Bool
    public let signature: AstraSignatureBlock
}

public struct ERGFollowUpResponse: Decodable, Hashable, Sendable {
    public let answer: String
    public let modelUsed: String?
    public let thoughtSignature: String?
    public let unNumber: String
    public let guideNumber: Int?
    public let hazardClass: String?
}

// MARK: - Multi-turn signature cache

/// Per-UN-number thought-signature cache. 5-minute TTL matches the
/// canonical ESang thought-signature cache (P0-3). Lets a driver
/// chain ERG follow-ups ("what if it spills?", "with class 3?",
/// "nearest hazmat dump?") without the model re-reasoning each turn.
public actor ERGThoughtSignatureCache {
    private var byUN: [String: String] = [:]
    private var lastUpdate: [String: Date] = [:]
    private let ttl: TimeInterval = 5 * 60

    public init() {}

    public func remember(_ signature: String, for unNumber: String) {
        byUN[unNumber] = signature
        lastUpdate[unNumber] = Date()
    }

    public func recall(for unNumber: String) -> String? {
        guard let stamp = lastUpdate[unNumber] else { return nil }
        if Date().timeIntervalSince(stamp) > ttl {
            byUN.removeValue(forKey: unNumber)
            lastUpdate.removeValue(forKey: unNumber)
            return nil
        }
        return byUN[unNumber]
    }

    public func forget(_ unNumber: String) {
        byUN.removeValue(forKey: unNumber)
        lastUpdate.removeValue(forKey: unNumber)
    }
}

// MARK: - Service

public final class ERGLookupService: @unchecked Sendable {
    public static let shared = ERGLookupService()

    private let signatureCache = ERGThoughtSignatureCache()
    private let astra = AstraVisionService.shared

    public init() {}

    /// Scan a hazmat placard. Captures the photo, ships it to the
    /// server's `astraDvir.placardScan`, verifies the Ed25519
    /// signature locally, returns the structured response.
    public func scanPlacard(
        image: UIImage,
        vehicleId: String? = nil,
        loadId: String? = nil
    ) async throws -> PlacardScanResponse {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw AstraError.imageEncodeFailed
        }
        let b64 = jpeg.base64EncodedString()
        let dialect = await MainActor.run { UserVoicePreference.shared.current.rawValue }
        struct In: Encodable {
            let imageBase64: String
            let mimeType: String
            let vehicleId: String?
            let loadId: String?
            let voiceDialect: String?
        }
        let payload = In(
            imageBase64: b64,
            mimeType: "image/jpeg",
            vehicleId: vehicleId,
            loadId: loadId,
            voiceDialect: dialect
        )
        let response: PlacardScanResponse = try await EusoTripAPI.shared.mutation(
            "astraDvir.placardScan",
            input: payload
        )
        // Verify the Ed25519 signature locally before trusting any
        // observation — a tampered network hop must fail before the
        // HazmatOverlay.placardsAffixed UI commits.
        if !verifySignature(response.signature) {
            throw AstraError.signatureVerificationFailed
        }
        return response
    }

    /// Ask a follow-up question grounded in a previously-scanned
    /// material. Uses the thought-signature cache for multi-turn
    /// continuity so chained questions are cheap.
    public func askFollowUp(
        unNumber: String,
        question: String
    ) async throws -> ERGFollowUpResponse {
        let dialect = await MainActor.run { UserVoicePreference.shared.current.rawValue }
        let prevSignature = await signatureCache.recall(for: unNumber)
        struct In: Encodable {
            let unNumber: String
            let question: String
            let prevThoughtSignature: String?
            let dialect: String?
        }
        let payload = In(
            unNumber: unNumber,
            question: question,
            prevThoughtSignature: prevSignature,
            dialect: dialect
        )
        let response: ERGFollowUpResponse = try await EusoTripAPI.shared.mutation(
            "erg.askFollowUp",
            input: payload
        )
        if let sig = response.thoughtSignature {
            await signatureCache.remember(sig, for: unNumber)
        }
        return response
    }

    public func forgetSignature(for unNumber: String) async {
        await signatureCache.forget(unNumber)
    }

    // MARK: - Signature verification

    private func verifySignature(_ sig: AstraSignatureBlock) -> Bool {
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
