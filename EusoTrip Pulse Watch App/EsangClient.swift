//
//  EsangClient.swift
//  EusoTrip Watch App
//
//  Thin client that calls the live EusoTrip backend. Two entry points:
//
//    POST /api/trpc/esang.chat                     — Gemini-backed brain
//    POST /api/trpc/voiceESANG.processVoiceCommand — legacy intent router
//
//  tRPC v10 HTTP link shape:
//    request:  { "json": <input> }
//    response: { "result": { "data": { "json": <output> } } }
//
//  PRIMARY PATH: `esang.chat` — same Gemini-backed conversational brain
//  the iOS app and web client talk to. It can answer general questions
//  (ergonomics, HOS rules, hazmat lookups, load logistics) AND return
//  structured app-control actions (navigate, accept_load, etc.) in the
//  same response. We pass `currentPage:"watch"` and the active loadId
//  in context so Esang knows the surface and the trip she's helping
//  with.
//
//  FALLBACK: on a 404 (older deploy without esang.chat) we drop down
//  to `voiceESANG.processVoiceCommand` so the wrist still gets a reply.
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
    /// L4 — AVAudioSession couldn't activate a playAndRecord route
    /// (workout session holding it, HFP negotiation failed, 0-channel
    /// input format). Throwing this lets startListening surface a
    /// hint-card error before attempting installTap, which on a
    /// 0-channel format is an ObjC exception rather than a Swift throw.
    case audioRouteUnavailable

    var errorDescription: String? {
        switch self {
        case .badResponse:             return "Couldn't reach Esang."
        case .unauthorized:            return "Sign in on your iPhone."
        case .notConnected:            return "No connection — queued for when you're back online."
        case .server(let s, _):        return "Esang error (\(s))."
        case .decoding(let msg):       return "Bad response: \(msg)"
        case .audioRouteUnavailable:   return "Microphone busy — try again in a moment."
        }
    }
}

struct EsangClient {
    let auth: AuthStore
    var baseURL: URL { URL(string: EusoTripConfig.apiBaseURL)! }

    // MARK: - High-level entry point

    /// Preferred voice path — calls the smart Gemini-backed `esang.chat`
    /// brain so the watch can answer questions about ergonomics, HOS
    /// rules, hazmat, load logistics, etc., not just dispatch app
    /// commands. The chat response includes structured `actions[]` for
    /// platform control too, so we still get "navigate", "accept_load",
    /// etc. wired through VoiceActionDispatcher. On 404 (older deploy
    /// without `esang.chat`) we fall back to the legacy command router.
    func processVoiceCommand(
        text: String,
        currentPage: String? = "watch",
        loadId: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) async throws -> VoiceResponse {
        do {
            return try await postChat(
                message: text,
                currentPage: currentPage,
                loadId: loadId,
                coordinate: coordinate
            )
        } catch EsangError.server(let status, _) where status == 404 {
            // Older deploy — drop down to the legacy intent router.
            return try await postVoiceCommand(
                text: text,
                currentPage: currentPage,
                loadId: loadId,
                coordinate: coordinate
            )
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

    // MARK: - esang.chat (PRIMARY)
    //
    // Gemini-backed conversational AI. Returns:
    //   { message: String, suggestions: [String], actions: [{type,label,data}] }
    // We map the structured `actions[]` into the watch's VoiceAction shape
    // so VoiceActionDispatcher can still execute platform commands like
    // "navigate" or "accept_load" that come back from the AI.

    private struct ChatAction: Decodable {
        let type: String
        let label: String?
        let data: AnyCodable?
    }

    private struct ChatPayload: Decodable {
        // Some server versions return `.message`, older ones `.response`
        let message: String?
        let response: String?
        let suggestions: [String]?
        let actions: [ChatAction]?

        var spokenText: String { message ?? response ?? "" }
    }

    private func postChat(
        message: String,
        currentPage: String?,
        loadId: String?,
        coordinate: CLLocationCoordinate2D?
    ) async throws -> VoiceResponse {
        let url = baseURL.appendingPathComponent("api/trpc/esang.chat")
        // Bumped from 15s — Gemini round-trip can take 6-10s on a cold call,
        // and we'd rather wait than time out and queue.
        var req = authed(URLRequest(url: url, timeoutInterval: 25))

        var context: [String: Any] = [:]
        if let currentPage { context["currentPage"] = currentPage }
        if let loadId { context["loadId"] = loadId }
        if let coordinate {
            context["latitude"] = coordinate.latitude
            context["longitude"] = coordinate.longitude
        }

        var input: [String: Any] = ["message": message]
        if !context.isEmpty { input["context"] = context }
        let body: [String: Any] = ["json": input]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try throwIfBadStatus(response, data: data)

        struct Envelope: Decodable {
            struct Result: Decodable {
                struct DataContainer: Decodable {
                    let json: ChatPayload
                }
                let data: DataContainer
            }
            let result: Result
        }

        let payload: ChatPayload
        do {
            payload = try JSONDecoder().decode(Envelope.self, from: data).result.data.json
        } catch {
            throw EsangError.decoding(error.localizedDescription)
        }

        let spoken = payload.spokenText
        return VoiceResponse(
            text: spoken,
            spokenText: spoken,
            intent: "conversational",
            confidence: 0.9,
            actions: (payload.actions ?? []).map {
                VoiceAction(type: $0.type, label: $0.label, payload: $0.data)
            },
            suggestions: payload.suggestions ?? [],
            shouldListen: false
        )
    }

    // MARK: - Low-level tool invocation

    /// Generic tRPC GET for read-only tool calls (load.getById, hos.getStatus, …).
    ///
    /// Transport ladder:
    ///   1. Direct HTTP to the live EusoTrip backend — same path the
    ///      iOS companion takes, authenticated with the wrist's Bearer.
    ///   2. On network failure (offline, dead zone, DNS unreachable),
    ///      fall back to the phone relay: WCSession hands the request
    ///      off to the paired iPhone, which runs the query on its
    ///      own authenticated session and returns the raw server
    ///      bytes. Watch decoder is identical either way — the reply
    ///      format is always the tRPC v10 envelope.
    ///   3. If both paths fail, surface the original network error
    ///      so the UI can render the "Can't reach X" banner.
    func queryJSON(_ router: String, input: [String: Any] = [:]) async throws -> Data {
        // Serialise input once — the same JSON flows down the direct
        // URL and the phone-relay message.
        let wrapped: [String: Any] = ["json": input]
        let inputJSONString: String = {
            guard let body = try? JSONSerialization.data(withJSONObject: wrapped),
                  let s = String(data: body, encoding: .utf8) else { return "{}" }
            return s
        }()

        // Path 1 — direct network.
        do {
            return try await queryJSONDirect(router: router, inputJSONString: inputJSONString)
        } catch {
            // Path 2 — phone relay. Only attempt when the phone link
            // is live; otherwise the sendMessage will bounce and we'd
            // just re-surface an EsangError.notConnected that masks
            // the more-informative original network error.
            if WatchConnectivityManager.shared.isReachable {
                do {
                    return try await WatchConnectivityManager.shared.requestTRPCRelay(
                        path: router,
                        inputJSON: inputJSONString
                    )
                } catch {
                    // Phone relay also failed — fall through with the
                    // original network error (more actionable than
                    // "phone relay failed").
                }
            }
            throw error
        }
    }

    /// Direct HTTP implementation — extracted so `queryJSON` can
    /// layer the phone-relay fallback on top.
    private func queryJSONDirect(router: String, inputJSONString: String) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/trpc/\(router)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "input", value: inputJSONString)]
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
