//
//  EusoTripSession.swift
//  EusoTrip — Authenticated session state (observable).
//
//  Holds the current AuthUser, phase, and persists the Bearer token + the
//  last-known user profile in Keychain. Keychain entries survive app
//  updates (and uninstall/reinstall on iOS 10.3+) because items written
//  with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` are preserved
//  by the system, so the driver stays logged in build-over-build.
//
//  Boot policy:
//    • If we have a cached token + user, enter `.signedIn` IMMEDIATELY so
//      the UI never flashes the SignIn screen on a cold launch with a
//      valid session.
//    • THEN call `auth.me()` in the background to refresh the profile.
//      A successful response updates the cache.
//      An explicit `.unauthenticated` (401/403) — and ONLY that — clears
//      the cache and signs the user out. Any other failure (network blip,
//      backend down, decoder glitch) is treated as transient and leaves
//      the user authenticated with the cached profile.
//

import Foundation
import Security
import SwiftUI

@MainActor
final class EusoTripSession: ObservableObject {

    enum Phase: Equatable {
        case booting          // app just launched, checking token
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .booting
    @Published private(set) var user: AuthUser?

    private let api: EusoTripAPI
    private let keychain = EusoKeychain(service: "com.eusorone.EusoTrip.session")

    // Keychain keys
    private let kAuthToken = "authToken"
    private let kCachedUser = "cachedUser"   // JSON-encoded AuthUser
    // JSON-encoded snapshot of the backend auth cookies (name/value/
    // domain/path/secure/httpOnly/expires). Persisted alongside the
    // bearer string so cold launches can rehydrate the server-issued
    // session cookie into HTTPCookieStorage.shared — otherwise
    // `HTTPCookieStorage` drops session-scoped cookies on app restart
    // and the backend's auth middleware (which reads the cookie
    // first) 401s on the very first `/auth.me` call, even though the
    // Bearer header is set. That's the real reason build 48's bearer-
    // only persistence still kicked the driver to SignIn on relaunch.
    private let kAuthCookies = "authCookies"
    // Tracks how many consecutive `/auth.me` UNAUTHORIZED responses we
    // got since last successful validation. We only wipe keychain on
    // the SECOND consecutive 401 so a one-off cookie-rehydrate race or
    // brief backend middleware blip doesn't sign the driver out.
    private let kUnauthStrikes = "unauthStrikes"

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    // MARK: Boot — call once from the app root

    func boot() async {
        guard let token = keychain.load(key: kAuthToken) else {
            self.phase = .signedOut
            return
        }
        api.authToken = token

        // Restore the server-issued auth cookies BEFORE calling /auth.me.
        // The backend's tRPC auth middleware reads `req.cookies` first and
        // falls back to the Authorization header — session cookies are
        // dropped by HTTPCookieStorage.shared on app restart, so without
        // this rehydrate the very first /auth.me after a relaunch or
        // update 401s even with a valid bearer.
        if let cookieJSON = keychain.load(key: kAuthCookies) {
            api.restoreAuthCookiesFromJSON(cookieJSON)
        }

        // ---- Fast path: hydrate from cached profile so the UI never flashes
        //      the SignIn screen on a cold launch with a valid session.
        if let cached = loadCachedUser() {
            self.user = cached
            self.phase = .signedIn
            WatchAuthBridge.shared.push(
                token: token,
                userId: cached.id,
                userName: cached.name,
                role: cached.role
            )
        }

        // ---- Background validation: refresh the profile from the server.
        //      We require TWO consecutive UNAUTHORIZED responses before
        //      tearing the session down. A single 401 is absorbed as a
        //      strike — common causes are (a) the cookie jar hadn't
        //      rehydrated yet when the first /auth.me hit the wire on
        //      watchOS-companion launches, and (b) the backend's auth
        //      middleware briefly returning UNAUTHORIZED during a cold
        //      Lambda / App Service warm-up. Any non-401 error is still
        //      fully transient.
        do {
            let me = try await api.auth.me()
            self.user = me
            self.phase = .signedIn
            saveCachedUser(me)
            keychain.delete(key: kUnauthStrikes)      // reset strike counter
            // Snapshot the latest cookies after a successful /me so any
            // backend-issued rotation (sliding expiry, refreshed token)
            // is captured for the next cold boot.
            if let snapshot = api.authCookieSnapshotJSON() {
                keychain.save(key: kAuthCookies, value: snapshot)
            }
            WatchAuthBridge.shared.push(
                token: token,
                userId: me.id,
                userName: me.name,
                role: me.role
            )
        } catch EusoTripAPIError.unauthenticated {
            // First strike? Keep the cached session and let the next /me
            // (triggered on next app launch or by any authenticated call)
            // confirm. Second strike in a row = session really is dead.
            let prior = Int(keychain.load(key: kUnauthStrikes) ?? "0") ?? 0
            let strikes = prior + 1
            if strikes >= 2 {
                api.authToken = nil
                api.clearCookies()
                keychain.delete(key: kAuthToken)
                keychain.delete(key: kCachedUser)
                keychain.delete(key: kAuthCookies)
                keychain.delete(key: kUnauthStrikes)
                self.user = nil
                self.phase = .signedOut
                WatchAuthBridge.shared.clear()
            } else {
                keychain.save(key: kUnauthStrikes, value: String(strikes))
                // Stay signed in on the cached profile. If we had no
                // cached user (very first launch after install) we still
                // have to show SignIn, but the token stays in keychain
                // so the next attempt can retry.
                if self.user == nil {
                    self.phase = .signedOut
                }
            }
        } catch {
            // Network blip / backend 500 / decode issue — keep the user
            // signed in on the cached profile. If no cached profile was
            // available we still show SignIn, but we keep the token so
            // the next launch can retry.
            if self.user == nil {
                self.phase = .signedOut
            }
        }
    }

    // MARK: Sign-in flow (credentials)

    /// Performs auth.login; returns the LoginResponse so the caller can
    /// branch on `requiresTwoFactor`.  On full success, stores session.
    func signIn(email: String, password: String, twoFactorCode: String? = nil) async throws -> LoginResponse {
        let resp = try await api.auth.login(
            email: email,
            password: password,
            twoFactorCode: twoFactorCode
        )
        if resp.success, let user = resp.user {
            self.user = user
            if let token = api.authToken {
                keychain.save(key: kAuthToken, value: token)
            }
            // Persist the profile alongside the token so cold launches
            // (and launches over flaky networks) can boot straight into
            // the authed shell without a /me round-trip.
            saveCachedUser(user)
            // Snapshot the server-issued auth cookies (the real primary
            // credential on the backend — the Bearer is a secondary
            // validation path) so cold boots can rehydrate them into
            // HTTPCookieStorage before /auth.me is called. Without this,
            // the session cookie is dropped on app restart and the
            // driver gets bounced to SignIn on every relaunch even
            // though the keychain has a valid token.
            if let cookieJSON = api.authCookieSnapshotJSON() {
                keychain.save(key: kAuthCookies, value: cookieJSON)
            }
            // Fresh sign-in resets any stale 401 strike counter from
            // earlier this device-install.
            keychain.delete(key: kUnauthStrikes)
            self.phase = .signedIn
            // Mirror auth state to the paired Apple Watch (no-op if no
            // watch is paired / WCSession isn't supported).
            if let token = api.authToken {
                WatchAuthBridge.shared.push(
                    token: token,
                    userId: user.id,
                    userName: user.name,
                    role: user.role
                )
            }
        }
        return resp
    }

    // MARK: Sign-out

    func signOut() async {
        _ = try? await api.auth.logout()
        api.authToken = nil
        api.clearCookies()
        keychain.delete(key: kAuthToken)
        keychain.delete(key: kCachedUser)
        keychain.delete(key: kAuthCookies)
        keychain.delete(key: kUnauthStrikes)
        self.user = nil
        self.phase = .signedOut
        // Tell the paired Apple Watch to wipe its mirrored auth state.
        WatchAuthBridge.shared.clear()
    }

    // MARK: Cached profile helpers

    private func saveCachedUser(_ user: AuthUser) {
        guard let data = try? JSONEncoder().encode(user),
              let json = String(data: data, encoding: .utf8) else { return }
        keychain.save(key: kCachedUser, value: json)
    }

    private func loadCachedUser() -> AuthUser? {
        guard let json = keychain.load(key: kCachedUser),
              let data = json.data(using: .utf8),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data)
        else { return nil }
        return user
    }

    // MARK: After-registration — email verification is sent; UI returns here.

    func afterRegistration() {
        // Registration mutations do NOT auto-login; force the user to verify
        // email then sign in.  We just reflect signed-out state.
        self.phase = .signedOut
    }

    // MARK: Offline demo sign-in (simulator + TestFlight without backend)
    //
    // Wires AppRoot → SignInView → ContentView without requiring a live
    // `auth.login` round-trip. Uses a synthetic AuthUser so downstream
    // screens that read `session.user?.firstName` still render ("Hey,
    // Michael"). Matches the Load.demoActive + InspectionTemplate.demoPreTrip
    // pattern: the whole production flow has an offline fallback so the
    // Figma-faithful walkthrough is demonstrable end-to-end.
    //
    func signInDemo(
        name: String = "Michael Reyes",
        role: EusoRole = .driver,
        email: String = "driver.demo@eusorone.com"
    ) {
        let demoUser = AuthUser(
            id: "demo-driver-1",
            email: email,
            role: role.rawValue,
            name: name,
            companyId: "demo-fleet-1"
        )
        self.user = demoUser
        self.phase = .signedIn
        // Persist the demo session too so TestFlight / simulator demos
        // survive app updates without re-running the demo sign-in each
        // time. We store a synthetic token + the demo profile; on boot
        // the cached-profile fast path picks them up, and the /me
        // validation call will fail benignly (no server) but the transient
        // error branch keeps the user authenticated on the cached profile.
        let demoToken = "demo-" + demoUser.id
        api.authToken = demoToken
        keychain.save(key: kAuthToken, value: demoToken)
        saveCachedUser(demoUser)
        // Mirror the demo session to the paired Apple Watch with a
        // synthetic token — otherwise Pulse stays stuck on "Open EusoTrip
        // on iPhone to pair" in TestFlight / simulator demo mode. The
        // watch side only gates its UI on `token != nil`, so any
        // non-empty marker is enough to flip past the pairing orb into
        // the authed home.
        WatchAuthBridge.shared.push(
            token: demoToken,
            userId: demoUser.id,
            userName: demoUser.name,
            role: demoUser.role
        )
    }
}

// MARK: - Keychain shim (minimal)

struct EusoKeychain {
    let service: String

    func save(key: String, value: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var attrs = q
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func load(key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}
