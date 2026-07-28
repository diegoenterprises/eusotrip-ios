//
//  ERGLookupService.swift
//  Hazmat placard scan + ERG multi-turn — IO 2026 P0-7.
//
//  Wraps two server endpoints with iOS-friendly response types:
//    - `astraDvir.placardScan` — Gemini Vision OCR + official ERG
//      response-reference lookup + Ed25519-signed audit chain entry.
//      ERG never supplies or attests legal dangerous-goods classification.
//    - `erg.askFollowUp` — multi-turn ERG conversation grounded
//      in the canonical guide content. Sends bounded explicit history;
//      no opaque reasoning state is fabricated or trusted.
//
//  A scan writes a signed observation only. One camera frame cannot
//  prove all required vehicle sides or establish legal dangerous-goods
//  classification, so it never advances `placardsAffixed`. That overlay
//  is completed by the dedicated compliance attestation workflow.
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
    public let hazardClass: String?
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
    public let classificationEvidence: ERGClassificationEvidence?
    public let signature: AstraSignatureBlock
}

public struct ERGClassificationEvidence: Decodable, Hashable, Sendable {
    public let eligibleAsClassificationSource: Bool
    public let source: String
    public let warning: String
}

public struct ERGFollowUpResponse: Decodable, Hashable, Sendable {
    public let answer: String
    public let modelUsed: String?
    public let thoughtSignature: String?
    public let continuityMode: String?
    public let unNumber: String
    public let guideNumber: Int?
    public let hazardClass: String?
    public let classificationEvidence: ERGClassificationEvidence?
}

public struct ERGConversationMessage: Codable, Hashable, Sendable {
    public let role: String
    public let content: String
}

// MARK: - Multi-turn conversation cache

/// Per-UN bounded conversation history. Only the latest six messages
/// are sent, and every turn is re-grounded against the official guide.
public actor ERGConversationCache {
    private var byUN: [String: [ERGConversationMessage]] = [:]
    private var lastUpdate: [String: Date] = [:]
    private let ttl: TimeInterval = 5 * 60

    public init() {}

    public func recall(for unNumber: String) -> [ERGConversationMessage] {
        guard let stamp = lastUpdate[unNumber] else { return [] }
        if Date().timeIntervalSince(stamp) > ttl {
            byUN.removeValue(forKey: unNumber)
            lastUpdate.removeValue(forKey: unNumber)
            return []
        }
        return byUN[unNumber] ?? []
    }

    public func append(
        question: String,
        answer: String,
        for unNumber: String
    ) {
        var messages = byUN[unNumber] ?? []
        messages.append(.init(role: "user", content: question))
        messages.append(.init(role: "assistant", content: answer))
        byUN[unNumber] = Array(messages.suffix(6))
        lastUpdate[unNumber] = Date()
    }

    public func forget(_ unNumber: String) {
        byUN.removeValue(forKey: unNumber)
        lastUpdate.removeValue(forKey: unNumber)
    }
}

// MARK: - Service

public final class ERGLookupService: @unchecked Sendable {
    public static let shared = ERGLookupService()

    private let conversationCache = ERGConversationCache()
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
        // Verify the Ed25519 signature locally before presenting the
        // observation. This does not convert the image into a legal
        // classification or an all-sides placarding attestation.
        if !verifySignature(response.signature) {
            throw AstraError.signatureVerificationFailed
        }
        return response
    }

    /// Ask a follow-up question grounded in a previously-scanned
    /// material. Sends bounded explicit history so chained questions
    /// have real continuity without exposing or fabricating model state.
    public func askFollowUp(
        unNumber: String,
        question: String
    ) async throws -> ERGFollowUpResponse {
        let dialect = await MainActor.run { UserVoicePreference.shared.current.rawValue }
        let conversation = await conversationCache.recall(for: unNumber)
        struct In: Encodable {
            let unNumber: String
            let question: String
            let conversation: [ERGConversationMessage]
            let dialect: String?
        }
        let payload = In(
            unNumber: unNumber,
            question: question,
            conversation: conversation,
            dialect: dialect
        )
        let response: ERGFollowUpResponse = try await EusoTripAPI.shared.mutation(
            "erg.askFollowUp",
            input: payload
        )
        await conversationCache.append(
            question: question,
            answer: response.answer,
            for: unNumber
        )
        return response
    }

    public func forgetConversation(for unNumber: String) async {
        await conversationCache.forget(unNumber)
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
