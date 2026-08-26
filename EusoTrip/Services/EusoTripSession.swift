//
//  EusoTripSession.swift
//  EusoTrip — Authenticated session state (observable).
//
//  Holds the current AuthUser, phase, and persists the access JWT, rotating
//  refresh cookie, and last-known profile in Keychain. The refresh secret is
//  never exposed in API JSON or promoted into an Authorization header.
//
//  Boot policy:
//    • Restore Keychain cookies before the first request.
//    • Keep the root in `.booting` while the server renews/validates so role
//      surfaces cannot stampede into 401s and paint red auth banners.
//    • A transient network/backend failure holds on a branded recovery
//      surface; it never mounts authenticated role loaders from stale cache.
//    • An authoritative UNAUTHORIZED clears local credentials immediately.
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
    @Published private(set) var isRecovering = false
    @Published private(set) var recoveryUnavailable = false

    private let api: EusoTripAPI
    private let keychain = EusoKeychain(service: "com.eusorone.EusoTrip.session")

    // Keychain keys
    /// Atomic authority bundle. Access + refresh-cookie state must advance in
    /// one Keychain write: persisting a rotated access token and crashing
    /// before the new refresh cookie is saved would replay the consumed cookie
    /// at next launch and correctly trigger server family revocation.
    private let kCredentialBundle = "credential.v2"
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
    // Removed two-strike state from earlier builds. Kept only so a successful
    // sign-in/session clear removes the obsolete Keychain entry.
    private let kLegacyUnauthStrikes = "unauthStrikes"

    private struct PersistedCredential: Codable {
        let accessToken: String?
        let cookieJSON: String?
        /// Display context only until `auth.me` validates it. Keeping the
        /// profile in the same Keychain value prevents a process kill from
        /// pairing a newly rotated credential with another account's legacy
        /// cached profile. Optional preserves decoding of pre-v2 bundles.
        let cachedUser: AuthUser?

        init(
            accessToken: String?,
            cookieJSON: String?,
            cachedUser: AuthUser? = nil
        ) {
            self.accessToken = accessToken
            self.cookieJSON = cookieJSON
            self.cachedUser = cachedUser
        }
    }

    /// Invalidates results from auth work that began before a logout or a
    /// different sign-in. This makes local logout win renewal races.
    private var authGeneration = 0
    private var recoveryDepth = 0
    /// Serializes server-side family revocation with a subsequent account
    /// sign-in. Local UI/Keychain teardown is immediate, but a new login must
    /// not race the old logout response's Set-Cookie clears.
    private var logoutTask: Task<Void, Never>?

    init(api: EusoTripAPI = .shared) {
        self.api = api
        // Install the single-flight 401 recovery hook. `EusoTripAPI` coalesces
        // callers; this object restores/rotates Keychain credentials and
        // validates the new access token before the original request replays.
        //
        // [weak self]: the API singleton outlives any one session object;
        // a strong capture would leak the session. A nil self (session torn
        // down) reports "not refreshed" so the API falls through to its
        // authoritative `.unauthenticated`.
        api.sessionRefreshHandler = { [weak self] in
            guard let self else { return false }
            return try await self.refreshSession()
        }
    }

    private enum ValidationOutcome {
        case live(AuthUser)
        case unauthorized
        case superseded
    }

    private enum RenewalOutcome {
        case renewed
        case unavailable(Error)
        case unauthorized
        case superseded
    }

    /// Rotating refresh credentials are single-use. This gate covers every
    /// renewal origin (cold boot, foreground return, and reactive 401), not
    /// only the API replay gate, so overlapping lifecycle work cannot submit
    /// the same cookie twice and trigger replay-family revocation.
    private var inFlightRenewal: (
        generation: Int,
        task: Task<RenewalOutcome, Never>
    )?

    // MARK: - Auto re-auth (the coalesced 401 path)

    /// Restores the rotating refresh cookie, invokes the unauthenticated
    /// renewal grant, persists both rotated cookies + the fresh access JWT,
    /// and proves the result with `auth.me` before request replay.
    func refreshSession() async throws -> Bool {
        guard phase != .signedOut,
              api.authToken != nil
                || loadPersistedCredential()?.cookieJSON != nil
                || keychain.load(key: kAuthCookies) != nil
        else { return false }

        let generation = authGeneration
        beginRecovery()
        defer { endRecovery() }

        switch try await validateCredential(
            renew: true,
            expectedGeneration: generation
        ) {
        case .live(let me):
            applyValidatedUser(me)
            pushWatchCredential(for: me)
            return true
        case .unauthorized:
            clearLocalSession(ifCurrent: generation)
            return false
        case .superseded:
            return false
        }
    }

    // MARK: Boot — call once from the app root

    func boot() async {
        recoveryUnavailable = false
        let persisted = loadPersistedCredential()
        let token = persisted?.accessToken ?? keychain.load(key: kAuthToken)
        let hasPersistedCookies = persisted?.cookieJSON != nil
            || keychain.load(key: kAuthCookies) != nil
        guard token != nil || hasPersistedCookies else {
            phase = .signedOut
            return
        }

        let generation = authGeneration
        api.authToken = token
        restorePersistedCookies()

        // Hydrate profile data for an honest offline fallback, but keep the
        // role shell behind BootSplash until renewal/validation settles. This
        // prevents every home widget/store from launching with stale auth.
        let cached = loadCachedUser()
        user = cached

        beginRecovery()
        defer { endRecovery() }
        do {
            // Always enter the refresh grant on a cold process launch. Besides
            // renewing aging access, this gives pre-deploy sessions their
            // one-time server migration bootstrap while the old access JWT is
            // still valid; waiting for its final day would strand users who do
            // not reopen before expiry. A refresh cookie alone is sufficient
            // authority and receives a new access JWT before `auth.me`.
            switch try await validateCredential(
                renew: true,
                expectedGeneration: generation
            ) {
            case .live(let me):
                applyValidatedUser(me)
                phase = .signedIn
                pushWatchCredential(for: me)
            case .unauthorized:
                clearLocalSession(ifCurrent: generation)
            case .superseded:
                break
            }
        } catch {
            // Offline/backend/decode failures do not revoke a credential.
            // Cached identity is display context only; role stores remain
            // unmounted behind the recovery surface until server authority
            // can be proven.
            // Do not mount role surfaces from cache: their `.task` loaders
            // would fan a transient auth/network outage into red banners
            // across the home. Do not show Sign In either: no authentication
            // authority rejected the saved credential. Hold on the branded
            // recovery surface with an explicit retry.
            recoveryUnavailable = true
            phase = .booting
        }
    }

    /// Server-authoritative validation shared by boot, foreground return,
    /// and 401 recovery. Renewal failures still get one `auth.me` probe so a
    /// temporarily unavailable rollout of the refresh route does not destroy
    /// an otherwise-live access session. If both fail, the original renewal
    /// error is propagated instead of being mislabeled as authentication.
    private func validateCredential(
        renew: Bool,
        expectedGeneration: Int
    ) async throws -> ValidationOutcome {
        restorePersistedCookies()
        var renewalError: Error?

        if renew {
            switch await renewCredentialOnce(expectedGeneration: expectedGeneration) {
            case .renewed:
                break
            case .unavailable(let error):
                renewalError = error
            case .unauthorized:
                return .unauthorized
            case .superseded:
                return .superseded
            }
        }

        do {
            let me = try await api.auth.me()
            guard expectedGeneration == authGeneration else {
                if phase == .signedOut {
                    api.authToken = nil
                    api.clearCookies()
                }
                return .superseded
            }
            persistRotatedCredential()
            return .live(me)
        } catch EusoTripAPIError.unauthenticated {
            // A transient refresh failure followed by an expired-access 401
            // is not proof that the durable refresh family is dead. Preserve
            // it for retry; only refreshSession's own UNAUTHORIZED above is
            // authoritative on a refresh-capable server.
            if let renewalError { throw renewalError }
            return .unauthorized
        } catch {
            throw renewalError ?? error
        }
    }

    private func renewCredentialOnce(expectedGeneration: Int) async -> RenewalOutcome {
        if let existing = inFlightRenewal {
            let outcome = await existing.task.value
            guard expectedGeneration == authGeneration else { return .superseded }
            if existing.generation == expectedGeneration { return outcome }
            // The shared task belonged to a superseded account. Once it has
            // settled, the current generation gets its own rotation.
            if inFlightRenewal?.generation == existing.generation {
                inFlightRenewal = nil
            }
            return await renewCredentialOnce(expectedGeneration: expectedGeneration)
        }

        let task = Task<RenewalOutcome, Never> { @MainActor [weak self] in
            guard let self else { return .superseded }
            return await self.performCredentialRenewal(
                expectedGeneration: expectedGeneration
            )
        }
        inFlightRenewal = (expectedGeneration, task)
        let outcome = await task.value
        if inFlightRenewal?.generation == expectedGeneration {
            inFlightRenewal = nil
        }
        return outcome
    }

    private func performCredentialRenewal(
        expectedGeneration: Int
    ) async -> RenewalOutcome {
        do {
            _ = try await api.auth.renewSession()
            guard expectedGeneration == authGeneration else {
                if phase == .signedOut {
                    api.authToken = nil
                    api.clearCookies()
                }
                return .superseded
            }
            persistRotatedCredential()
            return .renewed
        } catch EusoTripAPIError.unauthenticated {
            return .unauthorized
        } catch {
            // Rolling deployment: preserve a still-valid access session when
            // iOS reaches a server revision without the durable route. An
            // UNAUTHORIZED above never falls back: invalid/replayed refresh
            // authority must not be bypassed by the legacy access grant.
            guard shouldTryLegacyRenewal(after: error) else {
                return .unavailable(error)
            }
            do {
                _ = try await api.auth.renewLegacyAccessSession()
                guard expectedGeneration == authGeneration else {
                    return .superseded
                }
                persistRotatedCredential()
                return .renewed
            } catch EusoTripAPIError.unauthenticated {
                // On a pre-refresh server this protected grant is the only
                // renewal authority. Its 401 means the old access is over.
                return .unauthorized
            } catch {
                // `auth.me` remains the final authority and lets a live token
                // survive a partial backend rollout.
                return .unavailable(error)
            }
        }
    }

    private func shouldTryLegacyRenewal(after error: Error) -> Bool {
        switch error {
        case EusoTripAPIError.httpStatus(let code, _):
            return code == 404
        case EusoTripAPIError.trpcError(let message):
            let normalized = message.lowercased()
            return normalized.contains("no procedure")
                || normalized.contains("not found")
        default:
            return false
        }
    }

    private func restorePersistedCookies() {
        let cookieJSON = loadPersistedCredential()?.cookieJSON
            ?? keychain.load(key: kAuthCookies)
        if let cookieJSON {
            api.restoreAuthCookiesFromJSON(cookieJSON)
        }
    }

    private func persistRotatedCredential() {
        let previous = loadPersistedCredential()
        let token = api.authToken.flatMap { $0.isEmpty ? nil : $0 }
            ?? previous?.accessToken
            ?? keychain.load(key: kAuthToken)
        let snapshot = api.authCookieSnapshotJSON()
            ?? previous?.cookieJSON
            ?? keychain.load(key: kAuthCookies)
        let cached = user
            ?? previous?.cachedUser
            ?? loadLegacyCachedUser()
        guard token != nil || snapshot != nil,
              let data = try? JSONEncoder().encode(
                PersistedCredential(
                    accessToken: token,
                    cookieJSON: snapshot,
                    cachedUser: cached
                )
              ),
              let json = String(data: data, encoding: .utf8),
              keychain.save(key: kCredentialBundle, value: json)
        else { return }

        // Compatibility mirrors are written only AFTER the atomic bundle.
        // Boot authority prefers the bundle, so a process kill between these
        // best-effort copies cannot tear the rotation. WatchCommandHandler in
        // older builds can still read the legacy access-token key.
        if let token {
            keychain.save(key: kAuthToken, value: token)
        }
        if let snapshot {
            keychain.save(key: kAuthCookies, value: snapshot)
        }
        if let cached {
            saveCachedUser(cached)
        }
        keychain.delete(key: kLegacyUnauthStrikes)
    }

    private func loadPersistedCredential() -> PersistedCredential? {
        guard let json = keychain.load(key: kCredentialBundle),
              let data = json.data(using: .utf8),
              let credential = try? JSONDecoder().decode(PersistedCredential.self, from: data)
        else { return nil }
        return credential
    }

    private func applyValidatedUser(_ validated: AuthUser) {
        user = validated
        persistRotatedCredential()
    }

    private func pushWatchCredential(for validated: AuthUser) {
        guard let token = api.authToken, !token.isEmpty else { return }
        WatchAuthBridge.shared.push(
            token: token,
            userId: validated.id,
            userName: validated.name,
            role: validated.role
        )
    }

    private func beginRecovery() {
        recoveryDepth += 1
        isRecovering = true
    }

    private func endRecovery() {
        recoveryDepth = max(0, recoveryDepth - 1)
        isRecovering = recoveryDepth > 0
    }

    // MARK: Sign-in flow (credentials)

    /// Performs auth.login; returns the LoginResponse so the caller can
    /// branch on `requiresTwoFactor`.  On full success, stores session.
    func signIn(email: String, password: String, twoFactorCode: String? = nil) async throws -> LoginResponse {
        await waitForLogoutCompletion()
        let resp = try await api.auth.login(
            email: email,
            password: password,
            twoFactorCode: twoFactorCode
        )
        if resp.success, let user = resp.user {
            await applySignIn(user: user)
        }
        return resp
    }

    // MARK: Sign in with Apple

    /// Drives the full Sign in with Apple flow end-to-end:
    /// presents the system sheet, ships the identity token to the
    /// server, persists the session in keychain + cached profile.
    /// Returns the same `LoginResponse` shape as `signIn(email:…)`.
    func signInWithApple() async throws -> LoginResponse {
        await waitForLogoutCompletion()
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
        await waitForLogoutCompletion()
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
    /// branch — token / rotating-cookie / cached-user persistence and watch
    /// bridge. Incrementing the generation makes an older renewal result
    /// unable to overwrite this newly authenticated account.
    private func applySignIn(user: AuthUser) async {
        authGeneration += 1
        recoveryUnavailable = false
        applyValidatedUser(user)
        phase = .signedIn
        pushWatchCredential(for: user)
    }

    // MARK: Sign-out

    func signOut() async {
        if let existing = logoutTask {
            await existing.value
            return
        }

        // UI and Keychain logout are authoritative immediately; waiting for
        // the network used to leave role screens alive and erroring for up to
        // the global request timeout. Keep the in-memory cookie just long
        // enough for the server to revoke the rotating refresh family.
        authGeneration += 1
        let logoutGeneration = authGeneration
        user = nil
        phase = .signedOut
        recoveryUnavailable = false
        keychain.delete(key: kAuthToken)
        keychain.delete(key: kCachedUser)
        keychain.delete(key: kAuthCookies)
        keychain.delete(key: kCredentialBundle)
        keychain.delete(key: kLegacyUnauthStrikes)
        WatchAuthBridge.shared.clear()

        // Preserve the old cookie in memory only inside this bounded task so
        // the public logout route can revoke its refresh family even when the
        // access JWT has expired. Every real sign-in awaits this task, which
        // prevents the old response from clearing a newly issued account.
        let api = self.api
        let task = Task<Void, Never> { @MainActor [weak self] in
            _ = try? await api.auth.logout()
            guard let self else {
                api.authToken = nil
                api.clearCookies()
                return
            }
            if logoutGeneration == self.authGeneration {
                api.authToken = nil
                api.clearCookies()
            }
            self.logoutTask = nil
        }
        logoutTask = task
        await task.value
    }

    private func waitForLogoutCompletion() async {
        if let logoutTask {
            await logoutTask.value
        }
    }

    // MARK: Foreground self-heal — the fix for "I have to log out to fix it"
    //
    // EusoTripApp calls this after any real return from background. It renews
    // an aging credential before broadcasting the data-refresh fan-out.
    // False means callers must keep last-known data and MUST NOT make every
    // store refetch; transient recovery failure is not a logout.
    @discardableResult
    func revalidate() async -> Bool {
        guard case .signedIn = phase,
              let token = api.authToken
        else { return false }

        let generation = authGeneration
        beginRecovery()
        defer { endRecovery() }
        do {
            switch try await validateCredential(
                renew: EusoSessionTokenPolicy.shouldRenew(token),
                expectedGeneration: generation
            ) {
            case .live(let me):
                applyValidatedUser(me)
                pushWatchCredential(for: me)
                return true
            case .unauthorized:
                clearLocalSession(ifCurrent: generation)
                return false
            case .superseded:
                return false
            }
        } catch {
            return false
        }
    }

    /// Clears every local authority source iff no newer sign-in/logout has
    /// superseded the work that requested the clear.
    private func clearLocalSession(ifCurrent expectedGeneration: Int) {
        guard expectedGeneration == authGeneration else { return }
        authGeneration += 1
        api.authToken = nil
        api.clearCookies()
        keychain.delete(key: kAuthToken)
        keychain.delete(key: kCachedUser)
        keychain.delete(key: kAuthCookies)
        keychain.delete(key: kCredentialBundle)
        keychain.delete(key: kLegacyUnauthStrikes)
        user = nil
        phase = .signedOut
        recoveryUnavailable = false
        WatchAuthBridge.shared.clear()
    }

    // MARK: Cached profile helpers

    private func saveCachedUser(_ user: AuthUser) {
        guard let data = try? JSONEncoder().encode(user),
              let json = String(data: data, encoding: .utf8) else { return }
        keychain.save(key: kCachedUser, value: json)
    }

    private func loadCachedUser() -> AuthUser? {
        loadPersistedCredential()?.cachedUser ?? loadLegacyCachedUser()
    }

    /// Compatibility reader for sessions written before cached identity was
    /// folded into `credential.v2`. It is never treated as auth authority.
    private func loadLegacyCachedUser() -> AuthUser? {
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

    #if DEBUG
    // MARK: Offline demo sign-in (developer simulator only)
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
        // Preview mode is process-local and must never compete with a real
        // logout or masquerade as durable authentication on the next launch.
        guard logoutTask == nil else { return }
        authGeneration += 1
        recoveryUnavailable = false
        let demoUser = AuthUser(
            id: "demo-driver-1",
            email: email,
            role: role.rawValue,
            name: name,
            companyId: "demo-fleet-1"
        )
        self.user = demoUser
        self.phase = .signedIn
        // Never persist a fabricated credential as a user session. It cannot
        // be renewed or validated and was one source of cold-launch auth
        // noise in preview builds.
        let demoToken = "demo-" + demoUser.id
        api.authToken = demoToken
        api.clearCookies()
        keychain.delete(key: kAuthToken)
        keychain.delete(key: kCachedUser)
        keychain.delete(key: kAuthCookies)
        keychain.delete(key: kCredentialBundle)
        keychain.delete(key: kLegacyUnauthStrikes)
        // Do NOT mirror the synthetic demo token to the paired Apple
        // Watch. The wrist gates on `token != nil` and then attaches
        // `Bearer demo-…` to REAL production HTTPS calls — every query
        // 401s while the orb claims signed-in, which reads as "the
        // watch is broken." A demo phone session sends an explicit
        // clear so the wrist stays honestly on its pairing state.
        WatchAuthBridge.shared.clear()
    }
    #endif
}

// MARK: - Keychain shim (minimal)

struct EusoKeychain {
    let service: String

    /// Atomic update-or-insert. The old delete-then-add sequence created a
    /// crash window where a valid session disappeared between Security calls,
    /// and it ignored every OSStatus. Returning success lets focused callers
    /// and diagnostics verify persistence without exposing secret bytes.
    @discardableResult
    func save(key: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let changes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
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
