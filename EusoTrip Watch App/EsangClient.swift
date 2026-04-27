//
//  EsangClient.swift
//  EusoTrip Watch App
//
//  Thin client that calls the live EusoTrip backend. Two entry points:
//
//    POST /api/trpc/esang.chat                     — Gemini-backed chat
//    POST /api/trpc/voiceESANG.processVoiceCommand — intent + spoken reply
//
//  tRPC v10 HTTP link shape:
//    request:  { "json": <input> }
//    response: { "result": { "data": { "json": <output> } } }
//
//  The watch prefers `voiceESANG.processVoiceCommand` when the server
//  supports it (returns { spokenText, intent, actions[] }) and falls back
//  to `esang.chat` otherwise so the wrist still gets a reply even on
//  older deploys.
//

import Foundation
import CoreLocation

// MARK: - Voice response types

struct VoiceResponse: Decodable, Equatable {
    let text: String
    let spokenText: String
    let intent: String
    let confidence: Double
    let actions: [VoiceAction]
    let suggestions: [String]
    let shouldListen: Bool

    // Graceful init so the /esang.chat fallback still produces a usable
    // VoiceResponse with sensible defaults.
    static func fromChat(message: String, suggestions: [String]?) -> VoiceResponse {
        VoiceResponse(
            text: message,
            spokenText: message,
            intent: "conversational",
            confidence: 0.9,
            actions: [],
            suggestions: suggestions ?? [],
            shouldListen: false
        )
    }
}

struct VoiceAction: Decodable, Hashable {
    let type: String
    let label: String?
    let payload: AnyCodable?
}

enum EsangError: LocalizedError {
    case badResponse
    case unauthorized
    case notConnected
    case server(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:             return "Couldn't reach Esang."
        case .unauthorized:            return "Sign in on your iPhone."
        case .notConnected:            return "No connection — queued for when you're back online."
        case .server(let s, _):        return "Esang error (\(s))."
        case .decoding(let msg):       return "Bad response: \(msg)"
        }
    }
}

struct EsangClient {
    let auth: AuthStore
    var baseURL: URL { URL(string: EusoTripConfig.apiBaseURL)! }

    // MARK: - High-level entry point

    /// Preferred voice path — tries `voiceESANG.processVoiceCommand`
    /// first for a proper intent + spoken reply. On 404 (older deploy)
    /// falls back to `esang.chat` so text still lands on the wrist.
    func processVoiceCommand(
        text: String,
        currentPage: String? = "watch",
        loadId: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws -> VoiceResponse {
        do {
            return try await postVoiceCommand(
                text: text,
                currentPage: currentPage,
                loadId: loadId,
                coordinate: coordinate
            )
        } catch EsangError.server(let status, _) where status == 404 {
            // Fallback to the chat router
            let chat = try await postChat(message: text, currentPage: currentPage, loadId: loadId)
            return VoiceResponse.fromChat(message: chat.message, suggestions: chat.suggestions)
        }
    }

    // MARK: - voiceESANG.processVoiceCommand

    private func postVoiceCommand(
        text: String,
        currentPage: String?,
        loadId: String?,
        coordinate: CLLocationCoordinate2D?
    ) async throws -> VoiceResponse {
        let url = baseURL
            .appendingPathComponent("api/trpc/voiceESANG.processVoiceCommand")
        var req = authed(URLRequest(url: url, timeoutInterval: 15))

        var context: [String: Any] = [:]
        if let currentPage { context["currentPage"] = currentPage }
        if let loadId { context["loadId"] = loadId }
        if let coordinate {
            context["latitude"] = coordinate.latitude
            context["longitude"] = coordinate.longitude
        }
        context["surface"] = "watch"

        let body: [String: Any] = [
            "json": [
                "text": text,
                "context": context
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfBadStatus(response, data: data)

        struct Envelope: Decodable {
            struct Result: Decodable {
                struct DataContainer: Decodable {
                    let json: VoiceResponse
                }
                let data: DataContainer
            }
            let result: Result
        }

        do {
            return try JSONDecoder().decode(Envelope.self, from: data).result.data.json
        } catch {
            throw EsangError.decoding(error.localizedDescription)
        }
    }

    // MARK: - esang.chat fallback

    private struct ChatResp: Decodable {
        let message: String
        let suggestions: [String]?
    }

    private func postChat(message: String, currentPage: String?, loadId: String?) async throws -> ChatResp {
        let url = baseURL.appendingPathComponent("api/trpc/esang.chat")
        var req = authed(URLRequest(url: url, timeoutInterval: 15))

        var context: [String: Any] = [:]
        if let currentPage { context["currentPage"] = currentPage }
        if let loadId { context["loadId"] = loadId }

        var input: [String: Any] = ["message": message]
        if !context.isEmpty { input["context"] = context }
        let body: [String: Any] = ["json": input]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfBadStatus(response, data: data)

        struct Envelope: Decodable {
            struct Result: Decodable {
                struct DataContainer: Decodable {
                    let json: ChatResp
                }
                let data: DataContainer
            }
            let result: Result
        }

        do {
            return try JSONDecoder().decode(Envelope.self, from: data).result.data.json
        } catch {
            throw EsangError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Low-level tool invocation

    /// Generic tRPC GET for read-only tool calls (load.getById, hos.getStatus, …).
    func queryJSON(_ router: String, input: [String: Any] = [:]) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/trpc/\(router)"),
            resolvingAgainstBaseURL: false
        )!
        let wrapped: [String: Any] = ["json": input]
        if let body = try? JSONSerialization.data(withJSONObject: wrapped),
           let s = String(data: body, encoding: .utf8) {
            components.queryItems = [URLQueryItem(name: "input", value: s)]
        }
        var req = authed(URLRequest(url: components.url!, timeoutInterval: 12))
        req.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfBadStatus(response, data: data)
        return data
    }

    /// Generic tRPC POST for mutations (loadBidding.accept, hos.changeStatus, …).
    func mutateJSON(_ router: String, input: [String: Any] = [:]) async throws -> Data {
        let url = baseURL.appendingPathComponent("api/trpc/\(router)")
        var req = authed(URLRequest(url: url, timeoutInterval: 12))
        let body: [String: Any] = ["json": input]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfBadStatus(response, data: data)
        return data
    }

    // MARK: - Helpers

    private func authed(_ base: URLRequest) -> URLRequest {
        var req = base
        req.httpMethod = req.httpMethod ?? "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("EusoTripWatch/1.0 (watchOS)", forHTTPHeaderField: "User-Agent")
        if let token = auth.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func throwIfBadStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw EsangError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw EsangError.unauthorized }
            throw EsangError.server(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
