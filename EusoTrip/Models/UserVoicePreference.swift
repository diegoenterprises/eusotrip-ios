//
//  UserVoicePreference.swift
//  Regional dialect preference — IO 2026 P0-4.
//
//  Lets each user pin their preferred regional dialect (es-MX, fr-CA,
//  en-AU, en-US-SW, en-US-SE, pt-BR…) so ESang TTS replies + voice
//  transcription locale follow the user's home dialect instead of
//  the system default. Drives `ESangTTSPlayer` voice selection and
//  the `dialect` field propagated through `ESangContextProvider`
//  on every voice turn.
//
//  Drop into: EusoTrip/Models/UserVoicePreference.swift
//

import Foundation

/// Canonical dialect catalog. Codes are IETF BCP-47 with a regional
/// refinement suffix where the wire matters (Guadalajara vs Monterrey
/// Spanish, US-Southwest truck radio vs US-Southeast drawl). Kept in
/// lockstep with the server's `esangVoice.listDialects` catalog so the
/// iOS picker labels match the server-validated set byte-for-byte.
public enum VoiceDialect: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case system

    // English family
    case enUS       = "en-US"
    case enUSsw     = "en-US-SW"
    case enUSse     = "en-US-SE"
    case enCA       = "en-CA"
    case enAU       = "en-AU"

    // Spanish family
    case esMX       = "es-MX"
    case esMXgdl    = "es-MX-GDL"
    case esMXmty    = "es-MX-MTY"
    case esUS       = "es-US"

    // French family
    case frCA       = "fr-CA"
    case frFR       = "fr-FR"

    // Portuguese
    case ptBR       = "pt-BR"

    public var id: String { rawValue }

    /// Human-readable label rendered in the Settings picker.
    public var displayName: String {
        switch self {
        case .system:    return "System default"
        case .enUS:      return "English (United States)"
        case .enUSsw:    return "English (US — Southwest)"
        case .enUSse:    return "English (US — Southeast)"
        case .enCA:      return "English (Canada)"
        case .enAU:      return "English (Australia)"
        case .esMX:      return "Español (México — General)"
        case .esMXgdl:   return "Español (México — Guadalajara)"
        case .esMXmty:   return "Español (México — Monterrey)"
        case .esUS:      return "Español (US — Border)"
        case .frCA:      return "Français (Québec)"
        case .frFR:      return "Français (France)"
        case .ptBR:      return "Português (Brasil)"
        }
    }

    /// Short sample phrase the user hears when they tap "Preview".
    /// Each line is the canonical "what time will I get there?" so the
    /// preview is comparable across dialects.
    public var previewPhrase: String {
        switch self {
        case .system:    return "What time will I arrive at the dock?"
        case .enUS, .enUSsw, .enUSse, .enCA:
            return "What time will I arrive at the dock?"
        case .enAU:      return "What time will I arrive at the dock, mate?"
        case .esMX, .esMXgdl, .esMXmty:
            return "¿A qué hora llegaré al andén?"
        case .esUS:      return "¿A qué hora llego al dock?"
        case .frCA:      return "À quelle heure j'arrive au quai?"
        case .frFR:      return "À quelle heure vais-je arriver au quai?"
        case .ptBR:      return "Que horas eu chego na doca?"
        }
    }

    /// Apple AVSpeechSynthesisVoice language identifier used when the
    /// server-side dialect TTS isn't available and we fall back to the
    /// on-device synthesizer. Most regional refinements collapse to the
    /// closest BCP-47 root that AVSpeechSynthesisVoice supports.
    public var avSpeechLocaleIdentifier: String? {
        switch self {
        case .system:                                return nil
        case .enUS, .enUSsw, .enUSse:                return "en-US"
        case .enCA:                                  return "en-CA"
        case .enAU:                                  return "en-AU"
        case .esMX, .esMXgdl, .esMXmty, .esUS:       return "es-MX"
        case .frCA:                                  return "fr-CA"
        case .frFR:                                  return "fr-FR"
        case .ptBR:                                  return "pt-BR"
        }
    }

    /// SF Symbol shown next to the row in the picker.
    public var systemImage: String {
        switch self {
        case .system: return "globe"
        case .enUS, .enUSsw, .enUSse, .enCA, .enAU: return "speaker.wave.2"
        case .esMX, .esMXgdl, .esMXmty, .esUS: return "speaker.wave.2.bubble"
        case .frCA, .frFR: return "speaker.wave.2.circle"
        case .ptBR: return "speaker.wave.2"
        }
    }
}

/// User-scoped preference, persisted both locally (UserDefaults so the
/// app boots with the correct dialect even before the network is up)
/// and server-side (freight_ai_profiles.preferred_voice_dialect for
/// cross-device parity). Mirrored to `ESangContextProvider.voiceDialect`
/// so every ESang voice request carries the dialect automatically.
@MainActor
public final class UserVoicePreference: ObservableObject {
    public static let shared = UserVoicePreference()

    /// Storage key for the local-only cache (used at cold boot).
    private static let storageKey = "eusotrip.user_voice_dialect"

    @Published public private(set) var current: VoiceDialect

    public init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let dialect = VoiceDialect(rawValue: raw) {
            self.current = dialect
        } else {
            self.current = .system
        }
    }

    /// Set the dialect locally, push to server, and propagate to
    /// `ESangContextProvider` so every ESang voice request inherits
    /// the new value immediately (no need to wait for next launch).
    public func set(_ dialect: VoiceDialect) async throws {
        let prev = current
        current = dialect
        UserDefaults.standard.set(dialect.rawValue, forKey: Self.storageKey)
        // Mirror to ESang context.
        ESangContextProvider.shared.setVoiceDialect(dialect.rawValue)

        // Persist server-side. Failures roll back the local cache so
        // the next launch doesn't claim the dialect is set when the
        // server doesn't actually have it (we'd then sync the stale
        // local value back to the server on next launch — silent drift).
        do {
            struct In: Encodable { let dialect: String }
            struct Out: Decodable { let success: Bool; let dialect: String }
            let _: Out = try await EusoTripAPI.shared.mutation(
                "esangVoice.setDialect",
                input: In(dialect: dialect.rawValue)
            )
        } catch {
            // Roll back local cache so Settings doesn't display a fake
            // "saved" state. Caller is responsible for surfacing the
            // error to the user via toast/banner.
            current = prev
            UserDefaults.standard.set(prev.rawValue, forKey: Self.storageKey)
            ESangContextProvider.shared.setVoiceDialect(prev.rawValue)
            throw error
        }
    }

    /// Pull the server's stored dialect at app launch + cache locally
    /// so any drift between device + cloud reconciles to the server's
    /// truth. Falls back to whatever's in UserDefaults when the
    /// server is unreachable so the user keeps hearing their last
    /// picked dialect offline.
    public func reconcileFromServer() async {
        do {
            struct Out: Decodable { let dialect: String? }
            let reply: Out = try await EusoTripAPI.shared.query(
                "esangVoice.getMyDialect", input: EmptyInput()
            )
            if let raw = reply.dialect, let dialect = VoiceDialect(rawValue: raw) {
                current = dialect
                UserDefaults.standard.set(dialect.rawValue, forKey: Self.storageKey)
                ESangContextProvider.shared.setVoiceDialect(dialect.rawValue)
            }
        } catch {
            // Network failure — keep local cache. Quiet log only.
        }
    }
}

/// Convenience empty-input marker for parameterless queries. Encodes
/// to `{}` over the wire — what tRPC expects for procedures with no input.
private struct EmptyInput: Encodable, Sendable {}

extension UserVoicePreference {
    /// Effective dialect for synthesizers — resolves `.system` to
    /// the device locale's BCP-47 language tag, otherwise returns the
    /// stored rawValue. Always non-nil so callers don't have to guard.
    public var effectiveLocaleIdentifier: String {
        if let id = current.avSpeechLocaleIdentifier { return id }
        return Locale.current.identifier
    }
}
