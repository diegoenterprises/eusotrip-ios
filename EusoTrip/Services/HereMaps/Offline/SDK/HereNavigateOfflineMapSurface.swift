//
//  HereNavigateOfflineMapSurface.swift
//  EusoTrip
//
//  Fail-closed native renderer boundary. It loads only an explicitly approved
//  local HERE-native JSON/ZIP style. A failed validation/load destroys the
//  candidate view; no stock HERE scheme or retained previous scene is shown.
//

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

enum HereOfflineMapSurfaceMode: String, Codable, Hashable, Sendable, CaseIterable {
    case truck
    case rail
    case vessel
}

enum HereOfflineMapSurfaceFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case operational
    case navigation
    case terrain
}

enum HereOfflineMapSurfaceTheme: String, Codable, Hashable, Sendable, CaseIterable {
    case light
    case dark
}

struct HereOfflineNativeStyleIdentity: Codable, Hashable, Sendable {
    let mode: HereOfflineMapSurfaceMode
    let family: HereOfflineMapSurfaceFamily
    let theme: HereOfflineMapSurfaceTheme

    init(
        mode: HereOfflineMapSurfaceMode,
        family: HereOfflineMapSurfaceFamily,
        theme: HereOfflineMapSurfaceTheme
    ) {
        self.mode = mode
        self.family = family
        self.theme = theme
    }
}

struct HereOfflineNativeStyleAsset: Hashable, Sendable {
    /// Binds the bytes and digest to exactly one of the approved 3 x 3 x 2
    /// EusoTrip style identities. A caller cannot reuse truck bytes for vessel.
    let identity: HereOfflineNativeStyleIdentity
    let fileURL: URL
    /// Lower/upper case is accepted; comparison is normalized to lower case.
    let expectedSHA256: String

    fileprivate init(
        identity: HereOfflineNativeStyleIdentity,
        fileURL: URL,
        expectedSHA256: String
    ) {
        self.identity = identity
        self.fileURL = fileURL
        self.expectedSHA256 = expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HereOfflineMapSurfaceConfiguration: Hashable, Sendable {
    let mode: HereOfflineMapSurfaceMode
    let family: HereOfflineMapSurfaceFamily
    let theme: HereOfflineMapSurfaceTheme
    let approvedNativeStyle: HereOfflineNativeStyleAsset

    var identity: HereOfflineNativeStyleIdentity {
        HereOfflineNativeStyleIdentity(mode: mode, family: family, theme: theme)
    }

    init(
        mode: HereOfflineMapSurfaceMode,
        family: HereOfflineMapSurfaceFamily,
        theme: HereOfflineMapSurfaceTheme,
        approvedNativeStyle: HereOfflineNativeStyleAsset
    ) {
        self.mode = mode
        self.family = family
        self.theme = theme
        self.approvedNativeStyle = approvedNativeStyle
    }
}

enum HereOfflineMapSurfaceFailureCode: String, Codable, Hashable, Sendable {
    case notPrepared
    case missingFramework
    case runtimeUnavailable
    case runtimeLeaseUnavailable
    case radioSilenceNotEnforced
    case styleIsNotLocal
    case styleMissing
    case styleFormatUnsupported
    case styleIdentityMismatch
    case styleHashInvalid
    case styleHashMismatch
    case hashingUnavailable
    case nativeStyleLoadFailed
    case styleManifestMissing
    case styleManifestInvalid
    case styleManifestUnapproved
    case styleManifestEntryUnavailable
    case styleAssetOutsideBundle
}

struct HereOfflineMapSurfaceFailure: Error, Equatable, Sendable {
    let code: HereOfflineMapSurfaceFailureCode
    let message: String
    let recovery: String?
}

enum HereOfflineMapSurfaceRenderStatus: Equatable, Sendable {
    case opaqueUnavailable(failure: HereOfflineMapSurfaceFailure)
    case validating(configuration: HereOfflineMapSurfaceConfiguration)
    case loading(configuration: HereOfflineMapSurfaceConfiguration)
    case rendered(configuration: HereOfflineMapSurfaceConfiguration)
}

struct HereOfflineMapSurfaceSnapshot: Equatable, Sendable {
    let status: HereOfflineMapSurfaceRenderStatus
    let accessibilityText: String
    let changedAt: Date
}

private struct HereOfflineNativeStyleManifest: Decodable {
    let status: String
    let entries: [HereOfflineNativeStyleManifestEntry]
}

private struct HereOfflineNativeStyleManifestEntry: Decodable {
    let mode: HereOfflineMapSurfaceMode
    let family: HereOfflineMapSurfaceFamily
    let theme: HereOfflineMapSurfaceTheme
    let relativePath: String
    let sha256: String?

    var identity: HereOfflineNativeStyleIdentity {
        .init(mode: mode, family: family, theme: theme)
    }
}

/// Production asset boundary. It accepts only the bundled 18-entry canonical
/// manifest and returns bytes bound to the requested identity and digest.
enum HereOfflineNativeStyleBundleCatalog {
    static func configuration(
        for identity: HereOfflineNativeStyleIdentity,
        bundle: Bundle = .main
    ) throws -> HereOfflineMapSurfaceConfiguration {
        let asset = try asset(for: identity, bundle: bundle)
        return HereOfflineMapSurfaceConfiguration(
            mode: identity.mode,
            family: identity.family,
            theme: identity.theme,
            approvedNativeStyle: asset
        )
    }

    static func hasCompleteValidatedCatalog(bundle: Bundle = .main) -> Bool {
        do {
            let manifest = try loadManifest(bundle: bundle)
            try validateCanonicalIdentities(manifest.entries)
            for entry in manifest.entries {
                _ = try validatedAsset(entry: entry, bundle: bundle)
            }
            return true
        } catch {
            return false
        }
    }

    private static func asset(
        for identity: HereOfflineNativeStyleIdentity,
        bundle: Bundle
    ) throws -> HereOfflineNativeStyleAsset {
        let manifest = try loadManifest(bundle: bundle)
        try validateCanonicalIdentities(manifest.entries)
        guard let entry = manifest.entries.first(where: { $0.identity == identity }) else {
            throw failure(
                .styleManifestEntryUnavailable,
                "The approved native style identity is unavailable.",
                recovery: "Export and approve the exact freight mode, family, and theme asset."
            )
        }
        return try validatedAsset(entry: entry, bundle: bundle)
    }

    private static func loadManifest(
        bundle: Bundle
    ) throws -> HereOfflineNativeStyleManifest {
        let urls = [
            bundle.url(
                forResource: "HERE_NATIVE_STYLE_SUPPLY_CHAIN",
                withExtension: "json"
            ),
            bundle.url(
                forResource: "HERE_NATIVE_STYLE_SUPPLY_CHAIN",
                withExtension: "json",
                subdirectory: "EusoTrip/Services/HereMaps/Offline"
            ),
        ].compactMap { $0 }
        guard let url = urls.first,
              let data = try? Data(contentsOf: url) else {
            throw failure(
                .styleManifestMissing,
                "The bundled HERE native style manifest is unavailable.",
                recovery: "Bundle the validated 18-entry native style supply-chain manifest."
            )
        }
        guard let manifest = try? JSONDecoder().decode(
            HereOfflineNativeStyleManifest.self,
            from: data
        ) else {
            throw failure(
                .styleManifestInvalid,
                "The bundled HERE native style manifest is invalid.",
                recovery: "Restore the release-validated native style manifest."
            )
        }
        guard manifest.status == "approved" else {
            throw failure(
                .styleManifestUnapproved,
                "The bundled HERE native style manifest has not been approved for rendering.",
                recovery: "Complete native-style provenance approval and set the release manifest status to approved."
            )
        }
        return manifest
    }

    private static func validateCanonicalIdentities(
        _ entries: [HereOfflineNativeStyleManifestEntry]
    ) throws {
        let expected = Set(
            HereOfflineMapSurfaceMode.allCases.flatMap { mode in
                HereOfflineMapSurfaceFamily.allCases.flatMap { family in
                    HereOfflineMapSurfaceTheme.allCases.map { theme in
                        HereOfflineNativeStyleIdentity(
                            mode: mode,
                            family: family,
                            theme: theme
                        )
                    }
                }
            }
        )
        let actual = Set(entries.map(\.identity))
        guard entries.count == expected.count,
              actual.count == entries.count,
              actual == expected else {
            throw failure(
                .styleManifestInvalid,
                "The native style manifest does not contain exactly the 18 canonical identities.",
                recovery: "Regenerate the manifest with truck, rail, and vessel across all families and themes."
            )
        }
    }

    private static func validatedAsset(
        entry: HereOfflineNativeStyleManifestEntry,
        bundle: Bundle
    ) throws -> HereOfflineNativeStyleAsset {
        let relativePath = entry.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathParts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !pathParts.contains(where: { $0 == ".." || $0.isEmpty }),
              let digest = entry.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
              isValidSHA256(digest) else {
            throw failure(
                .styleManifestEntryUnavailable,
                "The native style manifest entry is awaiting an approved path or SHA-256.",
                recovery: "Export the native asset and record its release SHA-256 before enabling rendering."
            )
        }

        let manifestURL = URL(fileURLWithPath: relativePath)
        let fileName = manifestURL.deletingPathExtension().lastPathComponent
        let fileExtension = manifestURL.pathExtension
        let candidates = [
            bundle.bundleURL.appendingPathComponent(relativePath),
            bundle.url(
                forResource: fileName,
                withExtension: fileExtension,
                subdirectory: "HEREStyles"
            ),
            bundle.url(forResource: fileName, withExtension: fileExtension),
        ].compactMap { $0 }
        let bundleRoot = bundle.bundleURL.standardizedFileURL
            .resolvingSymlinksInPath()
        guard let assetURL = candidates.first(where: { candidate in
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            return isDescendant(resolved, of: bundleRoot)
                && FileManager.default.fileExists(
                    atPath: resolved.path,
                    isDirectory: &isDirectory
                )
                && !isDirectory.boolValue
        })?.standardizedFileURL.resolvingSymlinksInPath() else {
            throw failure(
                .styleManifestEntryUnavailable,
                "The manifest-bound native style asset is not bundled.",
                recovery: "Add the exact release-manifest asset to the application bundle."
            )
        }
        guard isDescendant(assetURL, of: bundleRoot) else {
            throw failure(
                .styleAssetOutsideBundle,
                "The native style asset resolved outside the application bundle.",
                recovery: "Bundle the approved asset inside the signed application."
            )
        }

        #if canImport(CryptoKit)
        guard let data = try? Data(contentsOf: assetURL, options: [.mappedIfSafe]) else {
            throw failure(
                .styleManifestEntryUnavailable,
                "The manifest-bound native style asset cannot be read.",
                recovery: "Restore the signed bundle asset and retry."
            )
        }
        let actual = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == digest.lowercased() else {
            throw failure(
                .styleHashMismatch,
                "The bundled native style does not match its release SHA-256.",
                recovery: "Replace it with the exact manifest-approved asset."
            )
        }
        #else
        throw failure(
            .hashingUnavailable,
            "Native style integrity cannot be verified in this build.",
            recovery: "Enable CryptoKit before native offline rendering."
        )
        #endif

        return HereOfflineNativeStyleAsset(
            identity: entry.identity,
            fileURL: assetURL,
            expectedSHA256: digest
        )
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        return normalized.count == 64
            && normalized.unicodeScalars.allSatisfy(hexadecimal.contains)
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath)
    }

    private static func failure(
        _ code: HereOfflineMapSurfaceFailureCode,
        _ message: String,
        recovery: String
    ) -> HereOfflineMapSurfaceFailure {
        .init(code: code, message: message, recovery: recovery)
    }
}

@MainActor
final class HereNavigateOfflineMapSurface {
    private(set) var snapshot: HereOfflineMapSurfaceSnapshot {
        didSet { onSnapshotChange?(snapshot) }
    }

    var onSnapshotChange: ((HereOfflineMapSurfaceSnapshot) -> Void)? {
        didSet { onSnapshotChange?(snapshot) }
    }

    #if canImport(heresdk)
    private var nativeMapView: AnyObject?
    private var loadGeneration = UUID()
    private var runtimeRenderingLeaseID: UUID?
    #endif

    init() {
        let failure = HereOfflineMapSurfaceFailure(
            code: .notPrepared,
            message: "Offline map rendering has not been prepared.",
            recovery: "Choose an approved local map style after offline maps are ready."
        )
        snapshot = HereOfflineMapSurfaceSnapshot(
            status: .opaqueUnavailable(failure: failure),
            accessibilityText: Self.opaqueAccessibilityText(for: failure),
            changedAt: Date()
        )
    }

    /// Returns HERE's native MapView as an opaque object only when the framework
    /// is present. The view remains hidden until `snapshot.status` is rendered.
    /// Callers may cast to `heresdk.MapView` inside their own conditional branch.
    @discardableResult
    func prepare(
        identity: HereOfflineNativeStyleIdentity,
        bundle: Bundle = .main
    ) -> AnyObject? {
        do {
            return prepare(
                configuration: try HereOfflineNativeStyleBundleCatalog.configuration(
                    for: identity,
                    bundle: bundle
                )
            )
        } catch let failure as HereOfflineMapSurfaceFailure {
            replaceWithOpaqueFailure(failure)
            return nil
        } catch {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleManifestInvalid,
                    message: "The approved native style could not be resolved.",
                    recovery: "Restore the release-validated native style bundle."
                )
            )
            return nil
        }
    }

    @discardableResult
    func prepare(
        configuration: HereOfflineMapSurfaceConfiguration
    ) -> AnyObject? {
        #if canImport(heresdk)
        prepareNative(configuration: configuration)
        #else
        let failure = HereOfflineMapSurfaceFailure(
            code: .missingFramework,
            message: "The licensed HERE Navigate framework is not present in this build.",
            recovery: "Install the entitled HERE Navigate binary and rebuild the iOS app."
        )
        replaceWithOpaqueFailure(failure)
        _ = configuration
        return nil
        #endif
    }

    func clear() {
        let failure = HereOfflineMapSurfaceFailure(
            code: .notPrepared,
            message: "Offline map rendering is not active.",
            recovery: "Choose an approved local map style to render installed map data."
        )
        // `replaceWithOpaqueFailure` releases the process-wide rendering lease
        // before it hides and drops the MapView. Keep that ordering explicit so
        // a cleared app-scoped surface can never pin a later engine restart.
        replaceWithOpaqueFailure(failure)
    }

    private func replaceWithOpaqueFailure(_ failure: HereOfflineMapSurfaceFailure) {
        #if canImport(heresdk)
        releaseRuntimeRenderingLease()
        (nativeMapView as? MapView)?.isHidden = true
        nativeMapView = nil
        loadGeneration = UUID()
        #endif
        snapshot = HereOfflineMapSurfaceSnapshot(
            status: .opaqueUnavailable(failure: failure),
            accessibilityText: Self.opaqueAccessibilityText(for: failure),
            changedAt: Date()
        )
    }

    private static func opaqueAccessibilityText(
        for failure: HereOfflineMapSurfaceFailure
    ) -> String {
        "Offline map unavailable. \(failure.message)"
    }
}

#if canImport(heresdk)
@preconcurrency import heresdk

private extension HereNavigateOfflineMapSurface {
    func prepareNative(
        configuration: HereOfflineMapSurfaceConfiguration
    ) -> AnyObject? {
        // Immediately discard any previously rendered scene. A bad new style
        // can never leave an old layer visible as if it matched the new state.
        releaseRuntimeRenderingLease()
        (nativeMapView as? MapView)?.isHidden = true
        nativeMapView = nil
        loadGeneration = UUID()
        snapshot = HereOfflineMapSurfaceSnapshot(
            status: .validating(configuration: configuration),
            accessibilityText: "Validating the approved offline map style.",
            changedAt: Date()
        )

        guard let nativeEngine = SDKNativeEngine.sharedInstance else {
            replaceWithOpaqueFailure(
                .init(
                    code: .runtimeUnavailable,
                    message: "HERE native rendering is not initialized.",
                    recovery: "Prepare the offline map coordinator and retry."
                )
            )
            return nil
        }
        guard nativeEngine.isOfflineMode else {
            replaceWithOpaqueFailure(
                .init(
                    code: .radioSilenceNotEnforced,
                    message: "HERE native radio silence is not confirmed.",
                    recovery: "Switch to the radio-silent policy before offline rendering."
                )
            )
            return nil
        }
        guard configuration.approvedNativeStyle.identity == configuration.identity else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleIdentityMismatch,
                    message: "The approved native style does not match the requested freight mode, family, and theme.",
                    recovery: "Resolve the exact asset from the 18-entry native style manifest."
                )
            )
            return nil
        }
        guard let validatedPath = validateStyle(configuration.approvedNativeStyle) else {
            return nil
        }

        do {
            runtimeRenderingLeaseID = try HereNavigateRuntimeSupervisor.shared
                .acquireRenderingLease(owner: self)
        } catch {
            replaceWithOpaqueFailure(
                .init(
                    code: .runtimeLeaseUnavailable,
                    message: "HERE native rendering could not acquire the shared radio-silent runtime.",
                    recovery: "Finish connected maintenance and prepare the shared engine in radio-silent mode."
                )
            )
            return nil
        }

        let mapView = MapView()
        mapView.isHidden = true
        nativeMapView = mapView
        let generation = loadGeneration
        snapshot = HereOfflineMapSurfaceSnapshot(
            status: .loading(configuration: configuration),
            accessibilityText: "Loading installed HERE map data with the approved local style.",
            changedAt: Date()
        )

        // This is the sole map-scene load in this boundary. A stock-scheme
        // fallback is forbidden; an opaque unavailable state is intentional.
        mapView.mapScene.loadScene(fromFile: validatedPath) { [weak self, weak mapView] error in
            Task { @MainActor in
                guard let self, let mapView, self.loadGeneration == generation else { return }
                guard error == nil else {
                    self.replaceWithOpaqueFailure(
                        .init(
                            code: .nativeStyleLoadFailed,
                            message: "HERE rejected the approved local native map style.",
                            recovery: "Supply a HERE-native JSON/ZIP style built for the licensed SDK version."
                        )
                    )
                    return
                }
                mapView.isHidden = false
                self.snapshot = HereOfflineMapSurfaceSnapshot(
                    status: .rendered(configuration: configuration),
                    accessibilityText: self.renderedAccessibilityText(configuration),
                    changedAt: Date()
                )
            }
        }
        return mapView
    }

    func validateStyle(_ asset: HereOfflineNativeStyleAsset) -> String? {
        guard asset.fileURL.isFileURL else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleIsNotLocal,
                    message: "The approved map style is not a local file.",
                    recovery: "Bundle a HERE-native style on the device."
                )
            )
            return nil
        }
        let url = asset.fileURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleMissing,
                    message: "The approved local map style is missing.",
                    recovery: "Restore the bundled style asset and retry."
                )
            )
            return nil
        }
        let lowerPath = url.path.lowercased()
        guard lowerPath.hasSuffix(".json") || lowerPath.hasSuffix(".zip") else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleFormatUnsupported,
                    message: "The style is not a HERE-native JSON or ZIP asset.",
                    recovery: "Export a native style for this HERE SDK. HARP tar archives are not assumed compatible."
                )
            )
            return nil
        }
        let expected = asset.expectedSHA256.lowercased()
        let hexadecimalCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard expected.count == 64,
              expected.unicodeScalars.allSatisfy(hexadecimalCharacters.contains) else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleHashInvalid,
                    message: "The approved style SHA-256 is invalid.",
                    recovery: "Provide the 64-character SHA-256 from the release manifest."
                )
            )
            return nil
        }

        #if canImport(CryptoKit)
        let actual: String
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleMissing,
                    message: "The approved local map style could not be read.",
                    recovery: "Restore the style asset and verify file protection."
                )
            )
            return nil
        }
        guard actual == expected else {
            replaceWithOpaqueFailure(
                .init(
                    code: .styleHashMismatch,
                    message: "The local map style does not match its approved SHA-256.",
                    recovery: "Replace it with the release-manifest asset; do not render the changed file."
                )
            )
            return nil
        }
        #else
        replaceWithOpaqueFailure(
            .init(
                code: .hashingUnavailable,
                message: "Style integrity cannot be verified in this build.",
                recovery: "Enable CryptoKit before native offline rendering."
            )
        )
        return nil
        #endif

        return url.path
    }

    func renderedAccessibilityText(
        _ configuration: HereOfflineMapSurfaceConfiguration
    ) -> String {
        let mode: String
        switch configuration.mode {
        case .truck: mode = "truck"
        case .rail: mode = "rail"
        case .vessel: mode = "vessel"
        }
        let family: String
        switch configuration.family {
        case .operational: family = "operational"
        case .navigation: family = "navigation"
        case .terrain: family = "terrain"
        }
        let theme: String
        switch configuration.theme {
        case .light: theme = "light"
        case .dark: theme = "dark"
        }
        let routeTruth = configuration.mode == .truck
            ? "Local HERE road routing is available only when separately proven."
            : "Route geometry remains the cached server-canonical plan."
        return "Offline \(mode) \(family) map rendered with the approved \(theme) local style. \(routeTruth)"
    }

    func releaseRuntimeRenderingLease() {
        guard let runtimeRenderingLeaseID else { return }
        HereNavigateRuntimeSupervisor.shared
            .releaseRenderingLease(runtimeRenderingLeaseID)
        self.runtimeRenderingLeaseID = nil
    }
}
#endif
