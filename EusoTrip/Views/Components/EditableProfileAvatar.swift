//
//  EditableProfileAvatar.swift
//  EusoTrip
//
//  Reusable, authenticated profile-photo control. The server remains the
//  source of truth; no user-specific image or identity is embedded here.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct EditableProfileAvatar: View {
    private struct AuthoritativeProfile: Decodable {
        let name: String?
        let avatar: String?
    }
    var size: CGFloat = 72
    var showsEditBadge: Bool = true

    @Environment(\.palette) private var palette

    @State private var selectedItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var remoteAvatarURL: URL?
    @State private var initials = ""
    @State private var isLoadingProfile = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            preferredItemEncoding: .automatic,
            photoLibrary: .shared()
        ) {
            ZStack(alignment: .bottomTrailing) {
                avatarContent
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(LinearGradient.diagonal.opacity(0.9), lineWidth: 1.5)
                    )

                if isLoadingProfile || isUploading {
                    Circle()
                        .fill(palette.bgCard.opacity(0.82))
                        .frame(width: size, height: size)
                        .overlay {
                            ProgressView()
                                .tint(palette.textPrimary)
                                .accessibilityLabel(isUploading ? "Uploading profile photo" : "Loading profile photo")
                        }
                }

                if showsEditBadge && !isUploading {
                    Image(systemName: "camera.fill")
                        .font(.system(size: max(10, size * 0.17), weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: max(24, size * 0.34), height: max(24, size * 0.34))
                        .background(LinearGradient.diagonal, in: Circle())
                        .overlay(Circle().strokeBorder(palette.bgPage, lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .accessibilityLabel("Change profile photo")
        .accessibilityHint("Opens the photo library")
        .accessibilityValue(accessibilityValue)
        .task { await loadProfile() }
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await uploadSelection(item) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoProfileUpdated)) { _ in
            guard !isUploading else { return }
            Task { await loadProfile() }
        }
        .alert(
            "Profile photo",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatarImage {
            Image(uiImage: avatarImage)
                .resizable()
                .scaledToFill()
        } else if let remoteAvatarURL {
            AsyncImage(url: remoteAvatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    identityFallback
                case .empty:
                    ZStack {
                        identityFallback
                        ProgressView().tint(palette.textPrimary)
                    }
                @unknown default:
                    identityFallback
                }
            }
        } else {
            identityFallback
        }
    }

    private var identityFallback: some View {
        Circle()
            .fill(LinearGradient.diagonal)
            .overlay {
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: max(18, size * 0.34), weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                } else {
                    Text(initials)
                        .font(.system(size: max(15, size * 0.28), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityHidden(true)
                }
            }
    }

    private var accessibilityValue: String {
        if isUploading { return "Uploading" }
        if isLoadingProfile { return "Loading" }
        return avatarImage != nil || remoteAvatarURL != nil ? "Profile photo set" : "No profile photo set"
    }

    @MainActor
    private func loadProfile() async {
        guard !isUploading else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            apply(try await fetchProfile())
        } catch {
            // A profile read failure must not erase a photo already rendered
            // on screen, but it also must not disappear as a silent fallback.
            errorMessage = error.eusoUserCopy
        }
    }

    @MainActor
    private func uploadSelection(_ item: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            selectedItem = nil
        }

        do {
            guard let source = try await item.loadTransferable(type: Data.self), !source.isEmpty else {
                throw AvatarUploadError.unreadableImage
            }
            let jpeg = try Self.compressedJPEG(from: source)
            let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            _ = try await upload(dataURL: dataURL)
            let authoritative = try await fetchProfile()
            guard authoritative.avatar == dataURL else {
                throw AvatarUploadError.authoritativeReadbackMismatch
            }
            apply(authoritative)

            NotificationCenter.default.post(name: .eusoProfileUpdated, object: nil)
        } catch {
            if let local = error as? AvatarUploadError {
                errorMessage = local.errorDescription
            } else {
                errorMessage = error.eusoUserCopy
            }
        }
    }

    private func upload(dataURL: String) async throws -> String? {
        struct Input: Encodable { let avatarUrl: String }
        struct Result: Decodable {
            let success: Bool
            let avatarUrl: String?
        }

        let result: Result = try await EusoTripAPI.shared.mutation(
            "profile.updateAvatar",
            input: Input(avatarUrl: dataURL)
        )
        guard result.success else {
            throw AvatarUploadError.serverRejected
        }
        return result.avatarUrl
    }

    private func fetchProfile() async throws -> AuthoritativeProfile {
        try await EusoTripAPI.shared.queryNoInput("profile.getMyProfile")
    }

    @MainActor
    private func apply(_ profile: AuthoritativeProfile) {
        initials = Self.initials(from: profile.name)
        let resolved = Self.resolveAvatar(profile.avatar)
        avatarImage = resolved.image
        remoteAvatarURL = resolved.url
    }

    private static func initials(from name: String?) -> String {
        let parts = (name ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    private static func resolveAvatar(_ raw: String?) -> (image: UIImage?, url: URL?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        if raw.hasPrefix("data:"),
           let comma = raw.firstIndex(of: ","),
           let data = Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: .ignoreUnknownCharacters),
           let image = UIImage(data: data) {
            return (image, nil)
        }

        if let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
           let image = UIImage(data: data) {
            return (image, nil)
        }

        guard let url = URL(string: raw), url.scheme == "https" else { return (nil, nil) }
        return (nil, url)
    }

    private static func compressedJPEG(from source: Data) throws -> Data {
        guard let image = UIImage(data: source) else { throw AvatarUploadError.unreadableImage }

        // `users.profilePicture` is a 64 KB TEXT field. Keeping the binary
        // JPEG below 37 KB leaves room for base64 inflation and the data-URL
        // prefix while retaining the largest useful avatar rendition.
        let maximumBinaryBytes = 37_000
        let dimensions: [CGFloat] = [512, 384, 320, 256, 192, 128, 96]
        let qualities: [CGFloat] = [0.82, 0.70, 0.58, 0.46, 0.34, 0.24]

        for dimension in dimensions {
            let scale = min(
                dimension / max(image.size.width, 1),
                dimension / max(image.size.height, 1),
                1
            )
            let targetSize = CGSize(
                width: max(image.size.width * scale, 1),
                height: max(image.size.height * scale, 1)
            )
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = true
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let resized = renderer.image { context in
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: targetSize))
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            for quality in qualities {
                if let jpeg = resized.jpegData(compressionQuality: quality),
                   jpeg.count <= maximumBinaryBytes {
                    return jpeg
                }
            }
        }

        throw AvatarUploadError.imageTooLarge
    }
}

private enum AvatarUploadError: LocalizedError {
    case unreadableImage
    case imageTooLarge
    case serverRejected
    case authoritativeReadbackMismatch

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That photo could not be read. Choose another image and try again."
        case .imageTooLarge:
            return "That photo could not be reduced to the profile-image limit. Choose a smaller image and try again."
        case .serverRejected:
            return "Your profile photo was not saved. Nothing changed; please try again."
        case .authoritativeReadbackMismatch:
            return "Your profile photo could not be verified after saving. The previous photo remains in place; please try again."
        }
    }
}
