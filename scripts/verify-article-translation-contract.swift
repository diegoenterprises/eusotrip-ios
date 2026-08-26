import Foundation

private enum VerificationError: Error {
    case failed(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationError.failed(message) }
}

@main
struct VerifyArticleTranslationContract {
    static func main() throws {
        let segments = [
            ArticleTranslationSegment(id: "s0", kind: .heading, text: "Freight demand rises"),
            ArticleTranslationSegment(id: "s1", kind: .paragraph, text: "Carriers added capacity this week."),
            ArticleTranslationSegment(id: "s2", kind: .caption, text: "A loaded trailer at the terminal")
        ]
        let document = try ArticleTranslationDocument(
            canonicalURL: "https://publisher.example/news/freight-demand#reader",
            sourceLanguageHint: "en-US",
            segments: segments
        )

        try require(
            document.canonicalURL == "https://publisher.example/news/freight-demand",
            "canonical URL must discard fragments"
        )
        try require(
            document.contentFingerprint == "eb0d93bd5adecc41c2dd7b6868f957a86899522a32fa718c6ff305fe437d6522",
            "Swift fingerprint must match the server SHA-256 contract"
        )
        try require(document.cacheKey.contains(document.contentFingerprint), "cache key must include content fingerprint")

        let provenance = ArticleTranslationResponse.Provenance(
            service: "ESANG",
            provider: "Google Gemini",
            models: ["gemini-contract-test"],
            machineTranslated: true
        )
        let cache = ArticleTranslationResponse.CacheMetadata(
            status: "miss",
            generatedAt: "2026-08-23T12:00:00.000Z",
            expiresAt: "2026-08-24T12:00:00.000Z",
            freshnessSeconds: 0
        )
        let complete = ArticleTranslationResponse(
            status: .complete,
            canonicalURL: document.canonicalURL,
            contentFingerprint: document.contentFingerprint,
            sourceLanguage: "en",
            sourceLanguageEvidence: "provider",
            targetLocale: "es-MX",
            segments: segments.map { ArticleTranslatedSegment(id: $0.id, text: "ES:\($0.text)") },
            requestedSegmentCount: 3,
            translatedSegmentCount: 3,
            missingSegmentIds: [],
            provenance: provenance,
            cache: cache,
            errorCode: nil
        )
        _ = try complete.validated(for: document, targetLocale: "es-MX")

        let partial = ArticleTranslationResponse(
            status: .partial,
            canonicalURL: document.canonicalURL,
            contentFingerprint: document.contentFingerprint,
            sourceLanguage: "en",
            sourceLanguageEvidence: "document",
            targetLocale: "fr",
            segments: [
                ArticleTranslatedSegment(id: "s0", text: "FR:Freight demand rises"),
                ArticleTranslatedSegment(id: "s2", text: "FR:A loaded trailer at the terminal")
            ],
            requestedSegmentCount: 3,
            translatedSegmentCount: 2,
            missingSegmentIds: ["s1"],
            provenance: provenance,
            cache: cache,
            errorCode: "some_segments_unavailable"
        )
        _ = try partial.validated(for: document, targetLocale: "fr")

        let mismatched = ArticleTranslationResponse(
            status: .complete,
            canonicalURL: document.canonicalURL,
            contentFingerprint: String(repeating: "0", count: 64),
            sourceLanguage: "en",
            sourceLanguageEvidence: "provider",
            targetLocale: "es-MX",
            segments: complete.segments,
            requestedSegmentCount: 3,
            translatedSegmentCount: 3,
            missingSegmentIds: [],
            provenance: provenance,
            cache: cache,
            errorCode: nil
        )
        do {
            _ = try mismatched.validated(for: document, targetLocale: "es-MX")
            throw VerificationError.failed("mismatched content must be rejected")
        } catch ArticleTranslationContractError.responseMismatch {
            // Expected.
        }

        let unsafeDOM: [String: Any] = [
            "canonicalURL": "javascript:alert(1)",
            "sourceLanguage": "en",
            "segments": [["id": "s0", "kind": "paragraph", "text": "Readable article text"]]
        ]
        do {
            _ = try ArticleTranslationDocument(
                javaScriptValue: unsafeDOM,
                fallbackURL: URL(string: "https://publisher.example/article")!
            )
            throw VerificationError.failed("unsafe DOM canonical URL must be rejected")
        } catch ArticleTranslationContractError.invalidDocument {
            // Expected.
        }

        print("article translation Swift contract: PASS")
    }
}
