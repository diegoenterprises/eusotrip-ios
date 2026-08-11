//
//  EusoTripAPI+Access.swift
//  EusoTrip — tRPC bindings for the STAFF ACCESS CARD (Apple Wallet) + the
//  access-controller VERIFY path. Sibling of EusoTripAPI+Wallet.swift.
//
//  GROUNDED in the REAL access subsystem — NOT a fabricated one. The access
//  credential IS the existing `staffAccessTokens` issued by the terminal
//  (server `terminals.generateAccessLink` — a 6-digit accessCode + a 24h
//  token, plus the `POST /validate/:token` verify route). This file adds the
//  THIN signing + verify seam on top of that real grant, mirroring how
//  EusoWallet wraps `createPickupCredential`. The two server procs these
//  bindings call are being BUILT on top of that existing grant (they are not
//  yet deployed); the client contract below is what they return:
//
//   • terminals.createStaffAccessCredential →
//       { pkpassUrl, accessCode, qrPayload, expiresAt, staffName?, role? }
//     Mints (or re-signs) the themed Apple Wallet access pass for the staff
//     member's existing temporary access token. `pkpassUrl` is null until the
//     PassKit signing pipeline is wired server-side → the holder UI falls back
//     to the inline QR / 6-digit code (never a fabricated pass). The pass-type
//     is REUSED: "pass.com.app.eusotrip.pickup" already carries multiple kinds
//     under one Apple type ID, so NO new vendor cert is needed.
//
//   • terminals.verifyStaffAccess({ token? , code? }) →
//       { valid, staffName?, role?, expiresAt?, reason? }
//     The access controller scans the QR (token) or types the 6-digit code;
//     the proc checks it against `staffAccessTokens` (the same grant the
//     `/validate/:token` route already validates) and answers honestly.
//     `valid=false` is the truth path (expired / revoked / unknown) and is
//     NEVER massaged into a green "valid" client-side.
//
//  DECODE DISCIPLINE: every field is decoded defensively (optional / tolerant)
//  exactly like EusoTripAPI+Wallet.swift, so a renamed or missing server field
//  can never throw a decode error and blank the surface — and, critically, a
//  malformed verify response can never DEFAULT to `valid=true`. `valid`
//  decodes to `false` when absent, so the honest-deny invariant holds even on
//  a decode miss.
//

import Foundation

extension EusoTripAPI {

    /// What `terminals.createStaffAccessCredential` returns (the proc being
    /// built on the existing `staffAccessTokens` grant). Mirrors the
    /// PickupCredential shape but for the staff access grant. `pkpassUrl` is
    /// nil until PassKit signing is configured (→ inline QR fallback).
    struct StaffAccessCredential: Decodable {
        let accessCode: String        // the real 6-digit staffAccessTokens code
        let qrPayload: String         // canonical scannable payload (token-bearing)
        let pkpassUrl: String?        // nil → caller falls back to inline QR + code
        let passkitStatus: String
        let theme: WalletThemeMetadata
        let signedTheme: WalletThemeMetadata?
        let manifestDigest: String?
        let expiresAt: String?        // ISO-8601; the real 24h token expiry
        let staffName: String?
        let role: String?

        private enum CodingKeys: String, CodingKey {
            case accessCode, qrPayload, pkpassUrl, passkitStatus, theme
            case signedTheme, manifestDigest, expiresAt, staffName, role
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessCode = try c.decode(String.self, forKey: .accessCode)
            qrPayload = try c.decode(String.self, forKey: .qrPayload)
            pkpassUrl = try c.decodeIfPresent(String.self, forKey: .pkpassUrl)
            passkitStatus = try c.decode(String.self, forKey: .passkitStatus)
            theme = try c.decode(WalletThemeMetadata.self, forKey: .theme)
            signedTheme = try c.decodeIfPresent(WalletThemeMetadata.self, forKey: .signedTheme)
            manifestDigest = try c.decodeIfPresent(String.self, forKey: .manifestDigest)
            expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
            staffName = try c.decodeIfPresent(String.self, forKey: .staffName)
            role = try c.decodeIfPresent(String.self, forKey: .role)
        }
    }

    /// What `terminals.verifyStaffAccess` returns. `valid` defaults to FALSE on
    /// any decode miss so a malformed response can NEVER read as a green pass —
    /// the honest-deny invariant. The controller UI shows `reason` verbatim.
    ///
    /// `Equatable` is required so `AccessControllerScannerView`'s
    /// `enum AccessVerifyState: Equatable` (whose `.valid`/`.denied` cases carry
    /// this value) can synthesize its own conformance, which the
    /// `state == .verifying` comparison depends on. Every stored property is a
    /// `Bool`/`String?` (already `Equatable`), so the synthesis is free.
    struct StaffAccessVerification: Decodable, Equatable {
        let valid: Bool
        let staffName: String?
        let role: String?
        let expiresAt: String?
        let reason: String?

        private enum CodingKeys: String, CodingKey {
            case valid, staffName, role, expiresAt, reason
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            valid     = (try? c?.decodeIfPresent(Bool.self, forKey: .valid)) ?? false
            staffName = (try? c?.decodeIfPresent(String.self, forKey: .staffName)) ?? nil
            role      = (try? c?.decodeIfPresent(String.self, forKey: .role)) ?? nil
            expiresAt = (try? c?.decodeIfPresent(String.self, forKey: .expiresAt)) ?? nil
            reason    = (try? c?.decodeIfPresent(String.self, forKey: .reason)) ?? nil
        }
    }

    // MARK: - Holder side — mint / re-sign the themed access pass

    /// Mints (or re-signs) the staff access .pkpass for the CURRENT staff
    /// member's existing temporary access token, stamping their chosen wallet
    /// theme. The server resolves the staff identity from the bearer token and
    /// keys on the real `staffAccessTokens` grant — the client never invents an
    /// access code. `themeId` carries the picked wallet style so the access
    /// card matches the user's chosen look.
    func createStaffAccessCredential(themeId: String? = nil,
                                     themeRevision: String? = nil,
                                     expiresInHours: Int = 24) async throws -> StaffAccessCredential {
        struct In: Encodable {
            let themeId: String?
            let themeRevision: String?
            let expiresInHours: Int
        }
        return try await mutation("terminals.createStaffAccessCredential",
                                  input: In(themeId: themeId,
                                            themeRevision: themeRevision,
                                            expiresInHours: expiresInHours))
    }

    // MARK: - Controller side — verify a scanned / typed credential

    /// The access controller verifies a scanned QR (`token`) OR a typed
    /// 6-digit `code` against the real `staffAccessTokens`. Exactly one of the
    /// two is supplied. The server is the sole arbiter of validity; the client
    /// renders the answer verbatim and never fabricates a `valid`.
    func verifyStaffAccess(token: String? = nil, code: String? = nil) async throws -> StaffAccessVerification {
        struct In: Encodable { let token: String?; let code: String? }
        return try await mutation("terminals.verifyStaffAccess",
                                  input: In(token: token, code: code))
    }
}
