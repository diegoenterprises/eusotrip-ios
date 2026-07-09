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
        // Install the auto re-auth hook used by EusoTripAPI.perform when any
        // tRPC call returns 401/403. This is the high-leverage fix for the
        // build-751 "Authentication required" feedback (075 Safety Score,
        // 082 Violations, and every sibling screen): instead of surfacing a
        // hard auth wall the moment the in-memory cookie jar drops the
        // session cookie, the API layer transparently re-hydrates the
        // persisted credential and retries the request once. `refreshSession`
        // owns the keychain + cookie-rehydrate path, so it lives here.
        //
        // [weak self]: the API singleton outlives any one session object;
        // a strong capture would leak the session. A nil self (session torn
        // down) reports "not refreshed" so the API falls through to its
        // honest `.unauthenticated`.
        api.sessionRefreshHandler = { [weak self] in
            await self?.refreshSession() ?? false
        }
    }

    // MARK: - Auto re-auth (the 401/403 refresh path)
    //
    // Called by `EusoTripAPI.perform` (single-flight, coalesced there) when a
    // request 401/403s. EusoTrip has no dedicated refresh-token grant — the
    // PRIMARY credential is the server-issued `app_session_id` cookie,
    // persisted in the Keychain. The in-memory `HTTPCookieStorage.shared`
    // jar can silently drop that cookie out from under a long-lived session
    // (iOS memory reclaim after a long background, App Service cold warm-up),
    // and that dropped cookie is exactly what makes a previously-working
    // screen start returning "Authentication required". So the refresh is:
    //
    //   1. Re-hydrate the persisted auth cookies back into the shared jar.
    //   2. Re-validate with `auth.me` (this carries the restored cookie +
    //      the in-memory bearer).
    //
    // A successful `auth.me` proves the session is alive — the credential was
    // only "lost in the jar", so the original request's retry will now carry
    // the restored cookie and succeed. We refresh the cached profile +
    // re-snapshot any rotated cookie while we're here.
    //
    // Returns true ONLY when the session is confirmed live. On a genuine
    // UNAUTHORIZED we return false (the API surfaces the honest auth error)
    // and bump the same 2-strike counter `boot()`/`revalidate()` use, so a
    // truly dead session still tears down on the second confirmed 401 rather
    // than leaving the app wedged. NEVER calls back into `perform`'s retry
    // path — `auth.me` here runs with the refresh gate already closed (the
    // API coalesces and won't re-enter while a refresh is in flight).
    func refreshSession() async -> Bool {
        // Nothing to refresh if we were never signed in / have no token.
        guard api.authToken != nil else { return false }

        // Re-hydrate the persisted auth cookie into the jar BEFORE re-validating.
        if let cookieJSON = keychain.load(key: kAuthCookies) {
            api.restoreAuthCookiesFromJSON(cookieJSON)
        }

        do {
            let me = try await api.auth.me()
            self.user = me
            saveCachedUser(me)
            keychain.delete(key: kUnauthStrikes)        // confirmed live → reset
            if let snapshot = api.authCookieSnapshotJSON() {
                keychain.save(key: kAuthCookies, value: snapshot)
            }
            return true
        } catch EusoTripAPIError.unauthenticated {
            // Genuinely unauthorized. Apply the SAME 2-strike absorption the
            // boot()/revalidate() paths use so a one-off blip doesn't sign the
            // user out, but a real dead session does on the second strike.
            let prior = Int(keychain.load(key: kUnauthStrikes) ?? "0") ?? 0
            let strikes = prior + 1
            if strikes >= 2 {
                await signOut()
            } else {
                keychain.save(key: kUnauthStrikes, value: String(strikes))
            }
            return false
        } catch {
            // Transient (offline / 5xx / decode blip) — we can't confirm the
            // session is dead, so don't retry the original (the caller surfaces
            // its own transient error) and don't tear the session down.
            return false
        }
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

    // MARK: Sign in with Apple

    /// Drives the full Sign in with Apple flow end-to-end:
    /// presents the system sheet, ships the identity token to the
    /// server, persists the session in keychain + cached profile.
    /// Returns the same `LoginResponse` shape as `signIn(email:…)`.
    func signInWithApple() async throws -> LoginResponse {
        let payload = try await AppleAuthProvider.shared.signInWithApple()
        let resp = try await api.auth.signInWithApple(
            identityToken: payload.identityToken,
            authorizationCode: payload.authorizationCode,
            givenName: payload.givenName,
            familyName: payload.familyName,
            email: payload.email,
            nonce: payload.nonce
        )
        if resp.success, let user = resp.user {
            await applySignIn(user: user)
        }
        return resp
    }

    // MARK: Passkey sign-in

    /// Drives passkey assertion end-to-end. Pass `email` to constrain
    /// the credential list to a specific account; nil = let iOS
    /// surface any platform passkey for the RP.
    func signInWithPasskey(email: String? = nil, preferImmediately: Bool = false) async throws -> LoginResponse {
        let start = try await api.auth.passkeyAuthStart(email: email)
        let result = try await AppleAuthProvider.shared.assertPasskey(
            options: AppleAuthProvider.PasskeyAssertionStartOptions(
                challengeB64URL: start.challenge,
                allowedCredentialIdsB64URL: start.allowCredentials.map { $0.credentialId }
            ),
            preferImmediately: preferImmediately
        )
        let resp = try await api.auth.passkeyAuthFinish(
            challenge: start.challenge,
            credentialId: result.credentialId,
            authenticatorData: result.authenticatorData,
            clientDataJSON: result.clientDataJSON,
            signature: result.signature,
            userHandle: result.userHandle
        )
        if resp.success, let user = resp.user {
            await applySignIn(user: user)
        }
        return resp
    }

    /// Post-sign-in passkey registration — Settings → Passkeys uses
    /// this to bind the current iPhone for future Face-ID logins.
    func registerPasskey(label: String? = nil) async throws {
        let start = try await api.auth.passkeyRegisterStart(label: label)
        let result = try await AppleAuthProvider.shared.registerPasskey(
            options: AppleAuthProvider.PasskeyRegistrationStartOptions(
                challengeB64URL: start.challenge,
                userHandleB64URL: start.userHandle,
                userName: start.userName,
                userDisplayName: start.userDisplayName
            )
        )
        _ = try await api.auth.passkeyRegisterFinish(
            challenge: start.challenge,
            credentialId: result.credentialId,
            attestationObject: result.attestationObject,
            clientDataJSON: result.clientDataJSON,
            label: label,
            transports: ["internal", "hybrid"]
        )
    }

    /// Common post-sign-in plumbing shared by Apple Sign In and
    /// passkey assertion. Mirrors the work in `signIn(...)`'s success
    /// branch — token / cookie / cached user persistence, watch
    /// bridge, strike-counter reset, phase flip.
    private func applySignIn(user: AuthUser) async {
        self.user = user
        if let token = api.authToken {
            keychain.save(key: kAuthToken, value: token)
        }
        saveCachedUser(user)
        if let cookieJSON = api.authCookieSnapshotJSON() {
            keychain.save(key: kAuthCookies, value: cookieJSON)
        }
        keychain.delete(key: kUnauthStrikes)
        self.phase = .signedIn
        if let token = api.authToken {
            WatchAuthBridge.shared.push(
                token: token,
                userId: user.id,
                userName: user.name,
                role: user.role
            )
        }
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

    // MARK: Foreground self-heal — the fix for "I have to log out to fix it"
    //
    // `boot()` (the /auth.me + 2-strike auto-recovery) runs ONLY on cold
    // launch, so a session/token that goes stale WHILE the app is
    // backgrounded was never re-checked on return — every screen would
    // 401 and the user had to sign out by hand to mint a fresh session.
    // EusoTripApp calls this on the background→active transition. Unlike
    // `boot()` it does NOT re-rehydrate keychain cookies (the live in-memory
    // session is fresher); it just confirms the session is still valid and
    // applies the SAME graceful recovery: a truly dead session signs out
    // (→ SignIn → re-login) instead of leaving the whole app stuck.
    func revalidate() async {
        guard case .signedIn = phase, api.authToken != nil else { return }
        do {
            let me = try await api.auth.me()
            self.user = me
            saveCachedUser(me)
            keychain.delete(key: kUnauthStrikes)
            if let snapshot = api.authCookieSnapshotJSON() {
                keychain.save(key: kAuthCookies, value: snapshot)
            }
        } catch EusoTripAPIError.unauthenticated {
            // Same 2-strike absorption as boot() — one 401 is tolerated
            // (warm-up / transient middleware), two in a row = dead session.
            let prior = Int(keychain.load(key: kUnauthStrikes) ?? "0") ?? 0
            let strikes = prior + 1
            if strikes >= 2 {
                await signOut()
            } else {
                keychain.save(key: kUnauthStrikes, value: String(strikes))
            }
        } catch {
            // Transient (offline / 5xx) — keep the session; next foreground
            // or an authenticated call will re-confirm.
        }
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
        // Do NOT mirror the synthetic demo token to the paired Apple
        // Watch. The wrist gates on `token != nil` and then attaches
        // `Bearer demo-…` to REAL production HTTPS calls — every query
        // 401s while the orb claims signed-in, which reads as "the
        // watch is broken." A demo phone session sends an explicit
        // clear so the wrist stays honestly on its pairing state.
        WatchAuthBridge.shared.clear()
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
