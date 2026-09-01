//
//  AppRadioSilenceAsyncImage.swift
//  EusoTrip
//
//  AsyncImage-compatible remote image loader whose HTTP work is registered
//  with EusoTrip's app-wide radio-silence gate. data: and file: images remain
//  local and continue to render during a protected offline journey.
//

import SwiftUI
import UIKit

private enum AppRadioSilenceImageError: Error, LocalizedError {
    case unsupportedURL
    case invalidResponse
    case payloadTooLarge
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .unsupportedURL: return "Unsupported image URL."
        case .invalidResponse: return "The image server returned an invalid response."
        case .payloadTooLarge: return "The image is too large to display safely."
        case .invalidImage: return "The downloaded data is not a valid image."
        }
    }
}

struct AppRadioSilenceAsyncImage<Content: View>: View {
    let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty
    @State private var policyRevision = 0

    private struct RequestIdentity: Hashable {
        let url: URL?
        let policyRevision: Int
    }

    init(
        url: URL?,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: RequestIdentity(url: url, policyRevision: policyRevision)) {
                await loadImage()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .eusoAppRadioSilenceWillEngage)
            ) { _ in
                policyRevision &+= 1
                phase = .failure(AppRadioSilenceTransportError.enforced)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .eusoAppRadioSilenceDidRelease)
            ) { _ in
                policyRevision &+= 1
                phase = .empty
            }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }

        let revision = policyRevision
        phase = .empty

        do {
            let data: Data
            switch url.scheme?.lowercased() {
            case "data":
                data = try Self.decodeDataURL(url)
            case "file":
                data = try Data(contentsOf: url, options: [.mappedIfSafe])
            case "http", "https":
                var request = URLRequest(url: url)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let result = try await EusoTripAPI.shared
                    .appRadioSilenceGatedData(for: request)
                guard let response = result.1 as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw AppRadioSilenceImageError.invalidResponse
                }
                data = result.0
            default:
                throw AppRadioSilenceImageError.unsupportedURL
            }

            try Task.checkCancellation()
            guard revision == policyRevision else { return }
            guard data.count <= 20 * 1_024 * 1_024 else {
                throw AppRadioSilenceImageError.payloadTooLarge
            }
            guard let image = UIImage(data: data) else {
                throw AppRadioSilenceImageError.invalidImage
            }
            phase = .success(Image(uiImage: image))
        } catch is CancellationError {
            return
        } catch {
            guard revision == policyRevision else { return }
            phase = .failure(error)
        }
    }

    private static func decodeDataURL(_ url: URL) throws -> Data {
        let raw = url.absoluteString
        guard let comma = raw.firstIndex(of: ",") else {
            throw AppRadioSilenceImageError.unsupportedURL
        }
        let metadata = raw[..<comma]
        let payload = String(raw[raw.index(after: comma)...])
        if metadata.lowercased().contains(";base64") {
            guard let data = Data(base64Encoded: payload) else {
                throw AppRadioSilenceImageError.invalidImage
            }
            return data
        }
        guard let decoded = payload.removingPercentEncoding else {
            throw AppRadioSilenceImageError.invalidImage
        }
        return Data(decoded.utf8)
    }
}
