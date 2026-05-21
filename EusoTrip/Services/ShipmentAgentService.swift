//
//  ShipmentAgentService.swift
//  Shipment status multi-turn agent — IO 2026 P0-9.
//
//  Replaces the "search by load ID" pattern with a conversational
//  interface. The user asks anything in natural language; the
//  service routes to `shipmentAgent.query` which resolves candidate
//  loads in the caller's scope, composes a tight context block from
//  real prod data, calls Gemini with that grounding, and returns a
//  reply + thought signature for multi-turn continuity (P0-3).
//
//  Drop into: EusoTrip/Services/ShipmentAgentService.swift
//

import Foundation

// MARK: - Wire types (mirror server)

public struct RelatedLoadCard: Decodable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let loadNumber: String?
    public let status: String?
    public let cargoType: String?
    public let vertical: String?
    public let trailerCode: String?
    public let hazmatClass: String?
    public let pickupCity: String?
    public let pickupState: String?
    public let destCity: String?
    public let destState: String?
    public let pickupDate: String?
    public let deliveryDate: String?
    public let distance: Double?
    public let rate: String?
    public let ePodLockEnabled: Bool
    public let ePodLockReasons: [String]?
    public let transportMode: String?

    public var laneLabel: String {
        let from = pickupCity ?? pickupState ?? "—"
        let to   = destCity ?? destState ?? "—"
        return "\(from) → \(to)"
    }

    public var displayId: String {
        loadNumber ?? "load \(id)"
    }
}

public struct ShipmentAgentReply: Decodable, Hashable, Sendable {
    public let answer: String
    public let modelUsed: String?
    public let thoughtSignature: String?
    public let relatedLoadIds: [String]
    public let related: [RelatedLoadCard]?
}

// MARK: - Per-session thought-signature cache (P0-3)

actor ShipmentAgentSignatureCache {
    private var signature: String?
    private var lastUpdate: Date?
    private let ttl: TimeInterval = 5 * 60

    func remember(_ sig: String) { signature = sig; lastUpdate = Date() }
    func recall() -> String? {
        guard let stamp = lastUpdate else { return nil }
        if Date().timeIntervalSince(stamp) > ttl {
            signature = nil; lastUpdate = nil
            return nil
        }
        return signature
    }
    func forget() { signature = nil; lastUpdate = nil }
}

// MARK: - Service

public final class ShipmentAgentService: @unchecked Sendable {
    public static let shared = ShipmentAgentService()
    private let cache = ShipmentAgentSignatureCache()

    public init() {}

    /// One turn of the conversation. The service automatically
    /// threads the per-session thought signature through.
    @MainActor
    public func ask(_ question: String, scopeLoadIds: [String]? = nil) async throws -> ShipmentAgentReply {
        let prev = await cache.recall()
        let dialect = UserVoicePreference.shared.current.rawValue
        struct In: Encodable {
            let question: String
            let scopeLoadIds: [String]?
            let prevThoughtSignature: String?
            let dialect: String?
        }
        let payload = In(
            question: question,
            scopeLoadIds: scopeLoadIds,
            prevThoughtSignature: prev,
            dialect: dialect
        )
        let reply: ShipmentAgentReply = try await EusoTripAPI.shared.mutation(
            "shipmentAgent.query",
            input: payload
        )
        if let sig = reply.thoughtSignature {
            await cache.remember(sig)
        }
        return reply
    }

    /// Reset the conversation thread — call on screen dismiss / log-out.
    public func resetConversation() async {
        await cache.forget()
    }
}
