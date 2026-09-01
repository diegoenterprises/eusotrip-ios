//
//  HereSDKRuntime.swift
//  EusoTrip
//
//  App-lifetime HERE Navigate bootstrap. This boundary deliberately compiles
//  without the proprietary framework so ordinary builds fail visibly at
//  runtime instead of pretending that Maps JS cache is an offline map store.
//

import Foundation

public enum HereSDKLaunchConnectivity: String, Codable, Hashable, Sendable {
    /// HERE may use the network for catalog discovery, downloads, and updates.
    case connected
    /// HERE must not issue a network request, including during SDK startup.
    case radioSilent
}

public enum HereSDKRuntimeAvailability: Equatable, Sendable {
    case stopped
    case ready(connectivity: HereSDKLaunchConnectivity)
    case missingFramework
    case missingCredentials
    case missingLegalNotice
    case storageUnavailable(String)
    case initializationFailed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var operatorMessage: String {
        switch self {
        case .stopped:
            return "Offline maps are not started."
        case .ready(.connected):
            return "HERE offline maps are ready for downloads and updates."
        case .ready(.radioSilent):
            return "HERE offline maps are running in radio-silent mode."
        case .missingFramework:
            return "Offline maps require the licensed HERE Navigate framework."
        case .missingCredentials:
            return "Offline maps are not provisioned for this build."
        case .missingLegalNotice:
            return "Offline maps are blocked until the HERE legal notice is bundled."
        case .storageUnavailable:
            return "Offline map storage is unavailable on this device."
        case .initializationFailed:
            return "HERE offline maps could not start."
        }
    }
}

public struct HereSDKRuntimeCredentials: Equatable, Sendable {
    public let accessKeyID: String
    public let accessKeySecret: String

    public init?(bundle: Bundle = .main) {
        guard let accessKeyID = Self.value(
            for: "HERESDKAccessKeyID",
            bundle: bundle
        ), let accessKeySecret = Self.value(
            for: "HERESDKAccessKeySecret",
            bundle: bundle
        ) else {
            return nil
        }
        self.accessKeyID = accessKeyID
        self.accessKeySecret = accessKeySecret
    }

    private static func value(for key: String, bundle: Bundle) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.uppercased()
        guard !value.isEmpty,
              !value.hasPrefix("$("),
              !normalized.hasPrefix("REPLACE_WITH_"),
              normalized != "CHANGEME",
              normalized != "CHANGE_ME" else { return nil }
        return value
    }
}

public struct HereSDKRuntimePaths: Equatable, Sendable {
    public let root: URL
    public let cache: URL
    public let persistentMaps: URL

    public init(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = applicationSupport
            .appendingPathComponent("com.app.eusotrip", isDirectory: true)
            .appendingPathComponent("HERE", isDirectory: true)
        self.root = root
        self.cache = root.appendingPathComponent("cache", isDirectory: true)
        self.persistentMaps = root.appendingPathComponent(
            "persistent-map",
            isDirectory: true
        )
    }

    public func prepare(fileManager: FileManager = .default) throws {
        for directory in [root, cache, persistentMaps] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(resourceValues)
        }
    }
}

public enum HereSDKRuntimeContract {
    /// HERE documents a 256 MB minimum cache for Navigate. Persistent region
    /// packages are accounted separately and may require many gigabytes.
    public static let cacheSizeInBytes: Int64 = 256 * 1_024 * 1_024

    public static func hasLegalNotice(bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: "HERE_NOTICE", withExtension: nil) != nil
    }
}

#if canImport(heresdk)
import heresdk

@MainActor
public final class HereSDKRuntime {
    public static let shared = HereSDKRuntime()

    public private(set) var availability: HereSDKRuntimeAvailability = .stopped
    public private(set) var launchConnectivity: HereSDKLaunchConnectivity?

    private init() {}

    @discardableResult
    func start(
        connectivity: HereSDKLaunchConnectivity,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> HereSDKRuntimeAvailability {
        try HereNavigateRuntimeSupervisor.shared
            .validateConnectivityTransition(to: connectivity)
        if let current = launchConnectivity,
           current == connectivity,
           SDKNativeEngine.sharedInstance != nil {
            availability = .ready(connectivity: current)
            HereNavigateRuntimeSupervisor.shared.recordReady(connectivity: current)
            return availability
        }

        guard let credentials = HereSDKRuntimeCredentials(bundle: bundle) else {
            availability = .missingCredentials
            HereNavigateRuntimeSupervisor.shared.recordStopped()
            return availability
        }
        guard HereSDKRuntimeContract.hasLegalNotice(bundle: bundle) else {
            availability = .missingLegalNotice
            HereNavigateRuntimeSupervisor.shared.recordStopped()
            return availability
        }

        let paths: HereSDKRuntimePaths
        do {
            paths = try HereSDKRuntimePaths(fileManager: fileManager)
            try paths.prepare(fileManager: fileManager)
        } catch {
            availability = .storageUnavailable(Self.sanitized(error))
            HereNavigateRuntimeSupervisor.shared.recordStopped()
            return availability
        }

        // HERE supports one shared engine. A connectivity-mode change requires
        // a fresh instance so radio silence is established before startup.
        SDKNativeEngine.sharedInstance = nil

        let authentication = AuthenticationMode.withKeySecret(
            accessKeyId: credentials.accessKeyID,
            accessKeySecret: credentials.accessKeySecret
        )
        var options = SDKOptions(authenticationMode: authentication)
        options.cachePath = paths.cache.path
        options.persistentMapStoragePath = paths.persistentMaps.path
        options.cacheSizeInBytes = HereSDKRuntimeContract.cacheSizeInBytes
        options.offlineMode = connectivity == .radioSilent

        // Since HERE SDK 4.26 these capabilities must be explicit. Do not rely
        // on SDK defaults: truck restrictions, terrain, search, and routing are
        // all release-critical for EusoTrip.
        let persistentFeatures: [LayerConfiguration.Feature] = [
            .rendering,
            .detailRendering,
            .navigation,
            .offlineSearch,
            .offlineRouting,
            .truck,
            .truckServiceAttributes,
            .fuelStationAttributes,
            .terrain,
        ]
        options.layerConfiguration = LayerConfiguration(
            enabledFeatures: persistentFeatures
        )
        options.layerConfiguration.implicitlyPrefetchedFeatures =
            connectivity == .radioSilent ? [] : persistentFeatures

        do {
            try SDKNativeEngine.makeSharedInstance(options: options)
            // Keep the global switch and pass-through exception set explicit.
            // The SDKOptions flag prevents startup requests; the engine flag
            // preserves the policy if HERE changes internal initialization.
            SDKNativeEngine.sharedInstance?.passThroughFeatures = []
            SDKNativeEngine.sharedInstance?.isOfflineMode = connectivity == .radioSilent
            launchConnectivity = connectivity
            availability = .ready(connectivity: connectivity)
            HereNavigateRuntimeSupervisor.shared.recordReady(connectivity: connectivity)
        } catch {
            launchConnectivity = nil
            availability = .initializationFailed(Self.sanitized(error))
            HereNavigateRuntimeSupervisor.shared.recordStopped()
        }
        return availability
    }

    func stop() throws {
        try HereNavigateRuntimeSupervisor.shared.validateEngineRestart()
        SDKNativeEngine.sharedInstance = nil
        launchConnectivity = nil
        availability = .stopped
        HereNavigateRuntimeSupervisor.shared.recordStopped()
    }

    private static func sanitized(_ error: Error) -> String {
        String(describing: type(of: error))
    }
}

#else

@MainActor
public final class HereSDKRuntime {
    public static let shared = HereSDKRuntime()

    public private(set) var availability: HereSDKRuntimeAvailability = .stopped
    public private(set) var launchConnectivity: HereSDKLaunchConnectivity?

    private init() {}

    @discardableResult
    func start(
        connectivity: HereSDKLaunchConnectivity,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> HereSDKRuntimeAvailability {
        _ = connectivity
        _ = bundle
        _ = fileManager
        launchConnectivity = nil
        availability = .missingFramework
        return availability
    }

    func stop() {
        launchConnectivity = nil
        availability = .stopped
    }
}

#endif
