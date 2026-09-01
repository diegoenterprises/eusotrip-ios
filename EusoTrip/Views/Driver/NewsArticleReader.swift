//
//  NewsArticleReader.swift
//  EusoTrip — In-app article viewer for the Driver Intel news feed.
//
//  Driver direction (2026-04-21):
//
//    > clicking on it should take you to the website on your browser
//    > it should give the article within our eusotrip app in our ui
//    > … make sure their are back buttons for them to go back to main
//    > driver intel screen.
//
//  So the feed no longer hands off to Safari — it presents this view as
//  a fullScreenCover that hosts the article URL inside a `WKWebView`
//  wrapped in EusoTrip chrome: a gradient top bar with a back chevron,
//  the source pill, category tag, a progress indicator, and a Safari
//  escape-hatch for drivers who DO want to open the article in their
//  browser.
//
//  We render the scraped URL directly rather than a sanitised body field
//  because `news.ts` on the server only returns `{ title, summary,
//  link, … }` — the article body isn't in the payload. Loading the
//  publisher's own page keeps fidelity (images, captions, pullquotes)
//  without a reader-mode backend dependency.
//

import SwiftUI
import SafariServices
#if canImport(UIKit)
import UIKit
import WebKit
#endif

private enum ReaderTranslationState {
    case original
    case extracting(TranslateLanguage)
    case translating(TranslateLanguage, ArticleTranslationDocument)
    case result(
        TranslateLanguage,
        ArticleTranslationDocument,
        ArticleTranslationResponse,
        appliedCount: Int,
        localCacheHit: Bool
    )
    case unavailable(TranslateLanguage, String)
    case failed(TranslateLanguage, String)

    var target: TranslateLanguage? {
        switch self {
        case .original:
            return nil
        case .extracting(let target), .translating(let target, _),
             .result(let target, _, _, _, _), .unavailable(let target, _),
             .failed(let target, _):
            return target
        }
    }
}

// MARK: - NewsArticleReader

struct NewsArticleReader: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let article: NewsArticle

    @State private var isLoading: Bool = true
    @State private var loadProgress: Double = 0.0
    @State private var failedToLoad: Bool = false
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var webViewGoBack: (() -> Void)? = nil
    /// Forward-navigation handler mirroring `webViewGoBack`. Assigned by
    /// the embedded WKWebView so the top-bar forward chevron can advance
    /// the in-page history after the driver has gone back.
    @State private var webViewGoForward: (() -> Void)? = nil
    /// Reloads the existing WKWebView instance. Pull/foreground freshness must
    /// not replace the representable because that would discard page history,
    /// scroll position, translation state, and the mounted reader itself.
    @State private var webViewReload: (() -> Void)? = nil
    /// Handler the embedded WKWebView assigns so the reader chrome can
    /// navigate it to a new URL without tearing it down. Used by the
    /// retry button to re-hit the original article URL.
    @State private var webViewLoadURL: ((URL) -> Void)? = nil
    @State private var webViewExtractArticle: ((@escaping (Result<ArticleTranslationDocument, Error>) -> Void) -> Void)? = nil
    @State private var webViewApplyTranslation: (([ArticleTranslatedSegment], @escaping (Result<Int, Error>) -> Void) -> Void)? = nil
    @State private var webViewRestoreOriginal: ((@escaping (Bool) -> Void) -> Void)? = nil
    @State private var showLanguagePicker: Bool = false
    @State private var translationState: ReaderTranslationState = .original
    @State private var translationTask: Task<Void, Never>? = nil
    @State private var translationGeneration: Int = 0
    private var activeLanguage: TranslateLanguage? {
        guard case .result(let target, _, let response, let appliedCount, _) = translationState,
              response.status != .notNeeded,
              appliedCount > 0 else { return nil }
        return target
    }

    private var translationButtonAccessibilityLabel: String {
        switch translationState {
        case .extracting(let target), .translating(let target, _):
            return "Translating article to \(target.displayName). Tap for language options."
        case .result(let target, _, let response, let appliedCount, _)
            where response.status != .notNeeded && appliedCount > 0:
            return "Machine translated to \(target.displayName). Tap for language options."
        case .failed, .unavailable:
            return "Translation unavailable. Tap for language options."
        default:
            return "Translate complete article"
        }
    }

    private var articlePageZoom: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: return 0.90
        case .small: return 0.95
        case .medium, .large: return 1.00
        case .xLarge: return 1.10
        case .xxLarge: return 1.20
        case .xxxLarge: return 1.30
        case .accessibility1: return 1.45
        case .accessibility2: return 1.60
        case .accessibility3: return 1.75
        case .accessibility4: return 1.90
        case .accessibility5: return 2.00
        @unknown default: return 1.00
        }
    }
    /// In-app SFSafariViewController presentation for "Open in
    /// Safari" — the previous raw URL hand-off
    /// kicked the driver out to the system browser. Per founder
    /// "all on the app" doctrine: stay in-app via SFSafariViewController
    /// (handles paywalls, JS, X-Frame-Options the same way Safari
    /// does, but inside an EusoTrip-chrome modal).
    private struct NewsSafariSession: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var inAppSafariSession: NewsSafariSession? = nil

    var body: some View {
        VStack(spacing: 0) {
            topBar
            IridescentHairline()
            if case .original = translationState {
                EmptyView()
            } else {
                translationProofRow
                Divider().background(palette.borderFaint)
            }
            if loadProgress > 0 && loadProgress < 1 && !failedToLoad {
                progressBar
            }
            content
        }
        .background(palette.bgPage.ignoresSafeArea())
        .interactiveDismissDisabled(false)
        // Uniform cafe-door entrance — the reader used to fade in flat
        // which broke the pattern every other sheet sets.
        .screenTileRoot()
        .eusoRefreshHandler {
            resetTranslation()
            webViewReload?()
        }
        .eusoRefreshSurface("modal:news:\(article.id)")
        .onDisappear {
            translationTask?.cancel()
        }
        // In-app SFSafariViewController fallback for the "Open in
        // Safari" affordances. Stays inside the EusoTrip app.
        .sheet(item: $inAppSafariSession) { sess in
            NewsInAppSafari(url: sess.url)
                .ignoresSafeArea()
                .eusoRefreshSurface("modal:news-safari:\(article.id)")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Button {
                // If the WKWebView can go back inside its own history
                // (driver tapped a link inside the article), pop that
                // page first. Otherwise close the reader and land back
                // on the Driver Intel feed.
                if canGoBack, let back = webViewGoBack {
                    back()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: canGoBack ? "chevron.left" : "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(canGoBack ? "Back" : "Close article")

            // Forward chevron — only surfaces once the driver has gone
            // back inside the article's in-page history, so it never
            // clutters the bar on a fresh load. Mirrors the back button's
            // chrome exactly.
            if canGoForward {
                Button {
                    webViewGoForward?()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Forward")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    CategoryTag(category: article.typedCategory, compact: true)
                    Text(article.source)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Text(article.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The publisher's readable article is translated inside this
            // same WKWebView. EusoTrip and publisher chrome remain original.
            if article.articleURL != nil {
                Button {
                    showLanguagePicker = true
                } label: {
                    Image(systemName: activeLanguage == nil
                          ? "character.bubble"
                          : "character.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            activeLanguage == nil
                            ? palette.textSecondary
                            : .white
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            ZStack {
                                palette.bgCardSoft
                                if activeLanguage != nil {
                                    LinearGradient.diagonal
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(
                                    activeLanguage == nil
                                    ? palette.borderFaint
                                    : Color.white.opacity(0.35)
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(translationButtonAccessibilityLabel)
            }

            // "Open in Safari" escape-hatch — driver asked for the
            // article to stay in-app, but some publishers block WKWebView
            // (X-Frame-Options, paywall flows), so we keep an explicit
            // button rather than silently falling back.
            if let url = article.articleURL {
                Button {
                    inAppSafariSession = NewsSafariSession(id: UUID(), url: url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open in Safari")
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                active: activeLanguage,
                // Pre-highlight the driver's device-locale language so
                // the default choice is one tap away. Matches task step
                // 4: "Default target: device locale".
                suggested: TranslateLanguage.deviceDefault,
                onPick: { lang in
                    applyTranslation(to: lang)
                    showLanguagePicker = false
                },
                onReset: {
                    resetTranslation()
                    showLanguagePicker = false
                }
            )
            .environment(\.palette, palette)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .eusoCloseX()
            .eusoRefreshSurface("modal:news-language:\(article.id)")
        }
    }

    // MARK: Translation

    private func applyTranslation(to language: TranslateLanguage, forceRefresh: Bool = false) {
        translationTask?.cancel()
        translationGeneration += 1
        let generation = translationGeneration
        translationState = .extracting(language)

        guard let extract = webViewExtractArticle else {
            translationState = .unavailable(
                language,
                "The full publisher article has not finished loading."
            )
            return
        }

        let extractOriginal = {
            extract { result in
                Task { @MainActor in
                    guard generation == translationGeneration else { return }
                    switch result {
                    case .success(let document):
                        startTranslation(
                            document: document,
                            language: language,
                            forceRefresh: forceRefresh,
                            generation: generation
                        )
                    case .failure(let error):
                        translationState = .unavailable(
                            language,
                            error.localizedDescription
                        )
                    }
                }
            }
        }

        // A second language must always start from publisher originals,
        // never from text that was already machine translated.
        if let restore = webViewRestoreOriginal {
            restore { _ in extractOriginal() }
        } else {
            extractOriginal()
        }
    }

    private func startTranslation(
        document: ArticleTranslationDocument,
        language: TranslateLanguage,
        forceRefresh: Bool,
        generation: Int
    ) {
        translationState = .translating(language, document)
        translationTask = Task {
            do {
                let delivery = try await withArticleTranslationTimeout(seconds: 45) {
                    try await ArticleTranslationClient.shared.translate(
                        document: document,
                        targetLocale: language.code,
                        forceRefresh: forceRefresh
                    )
                }
                try Task.checkCancellation()
                guard generation == translationGeneration else { return }

                let response = delivery.response
                switch response.status {
                case .complete, .partial:
                    guard let apply = webViewApplyTranslation else {
                        translationState = .failed(
                            language,
                            "The publisher page changed before translation could be applied."
                        )
                        return
                    }
                    apply(response.segments) { result in
                        Task { @MainActor in
                            guard generation == translationGeneration else { return }
                            switch result {
                            case .success(let appliedCount):
                                translationState = .result(
                                    language,
                                    document,
                                    response,
                                    appliedCount: appliedCount,
                                    localCacheHit: delivery.localCacheHit
                                )
                            case .failure(let error):
                                translationState = .failed(language, error.localizedDescription)
                            }
                        }
                    }
                case .notNeeded:
                    translationState = .result(
                        language,
                        document,
                        response,
                        appliedCount: 0,
                        localCacheHit: delivery.localCacheHit
                    )
                case .unavailable:
                    translationState = .unavailable(
                        language,
                        "The translation provider did not return any verified article passages."
                    )
                }
            } catch is CancellationError {
                // Reset/cancel already placed the reader in its truthful state.
            } catch is ArticleTranslationTimeoutError {
                guard generation == translationGeneration else { return }
                translationState = .failed(
                    language,
                    "Translation timed out. The original article remains available."
                )
            } catch {
                guard generation == translationGeneration else { return }
                translationState = .failed(language, error.localizedDescription)
            }
        }
    }

    private func resetTranslation() {
        translationTask?.cancel()
        translationTask = nil
        translationGeneration += 1
        translationState = .original
        webViewRestoreOriginal? { _ in }
    }

    private func cancelTranslation() {
        resetTranslation()
    }

    private func retryTranslation(_ language: TranslateLanguage) {
        applyTranslation(to: language, forceRefresh: true)
    }

    @ViewBuilder
    private var translationProofRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            translationProofIcon
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(translationProofTitle)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = translationProofDetail {
                    Text(detail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            translationProofActions
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(palette.bgCardSoft)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var translationProofIcon: some View {
        switch translationState {
        case .extracting, .translating:
            ProgressView().tint(palette.textPrimary)
        case .result(_, _, let response, let appliedCount, _):
            if response.status == .partial || appliedCount < response.translatedSegmentCount {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Brand.warning)
            } else if response.status == .notNeeded {
                Image(systemName: "textformat")
                    .foregroundStyle(palette.textSecondary)
            } else {
                Image(systemName: "character.bubble.fill")
                    .foregroundStyle(LinearGradient.diagonal)
            }
        case .unavailable, .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Brand.warning)
        case .original:
            EmptyView()
        }
    }

    private var translationProofTitle: String {
        switch translationState {
        case .original:
            return "Original article"
        case .extracting:
            return "Finding the complete readable article"
        case .translating(let target, let document):
            return "Machine translating \(document.segments.count) passages to \(target.displayName)"
        case .result(let target, _, let response, let appliedCount, _):
            if response.status == .notNeeded {
                return "Article is already in \(target.displayName)"
            }
            let visibleCount = min(appliedCount, response.translatedSegmentCount)
            if response.status == .partial || visibleCount < response.requestedSegmentCount {
                return "Partial machine translation: \(visibleCount) of \(response.requestedSegmentCount) passages"
            }
            return "Machine translated to \(target.displayName)"
        case .unavailable:
            return "Complete article translation unavailable"
        case .failed:
            return "Translation failed"
        }
    }

    private var translationProofDetail: String? {
        switch translationState {
        case .extracting:
            return "Publisher summaries are not used as full articles."
        case .translating:
            return "The original remains visible while ESANG processes the article."
        case .result(_, _, let response, _, let localCacheHit):
            let source = languageName(response.sourceLanguage)
            let sourceEvidence: String
            switch response.sourceLanguageEvidence {
            case "document": sourceEvidence = "publisher page language"
            case "provider": sourceEvidence = "provider detected"
            default: sourceEvidence = "source not identified"
            }
            if response.status == .notNeeded {
                return "Source language: \(source) (\(sourceEvidence)). No machine translation was applied."
            }
            let model = response.provenance.models.joined(separator: ", ")
            let provider = model.isEmpty
                ? "\(response.provenance.service) · \(response.provenance.provider)"
                : "\(response.provenance.service) · \(response.provenance.provider) · \(model)"
            let freshness = translationFreshness(response, localCacheHit: localCacheHit)
            return "From \(source) (\(sourceEvidence)) · \(provider) · \(freshness)"
        case .unavailable(_, let message), .failed(_, let message):
            return message
        case .original:
            return nil
        }
    }

    @ViewBuilder
    private var translationProofActions: some View {
        switch translationState {
        case .extracting, .translating:
            Button(action: cancelTranslation) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel translation and show original")
        case .result(let language, _, let response, let appliedCount, _):
            HStack(spacing: Space.s1) {
                if response.status == .partial || appliedCount < response.translatedSegmentCount {
                    Button { retryTranslation(language) } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry incomplete translation")
                }
                Button(action: resetTranslation) {
                    Image(systemName: "textformat")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show original article")
            }
        case .unavailable(let language, _), .failed(let language, _):
            HStack(spacing: Space.s1) {
                Button { retryTranslation(language) } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry translation")
                Button(action: resetTranslation) {
                    Image(systemName: "textformat")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show original article")
            }
        case .original:
            EmptyView()
        }
    }

    private func languageName(_ code: String) -> String {
        guard code != "und" else { return "not identified" }
        return Locale.current.localizedString(forLanguageCode: code)
            ?? Locale.current.localizedString(forLanguageCode: code.split(separator: "-").first.map(String.init) ?? code)
            ?? code
    }

    private func translationFreshness(
        _ response: ArticleTranslationResponse,
        localCacheHit: Bool
    ) -> String {
        let expiry = response.expiresAtDate?.formatted(date: .abbreviated, time: .shortened)
            ?? response.cache.expiresAt
        if localCacheHit {
            return "device cache, expires \(expiry)"
        }
        if response.cache.status == "hit" {
            return "server cache, expires \(expiry)"
        }
        let generated = response.generatedAtDate?.formatted(date: .omitted, time: .shortened)
            ?? response.cache.generatedAt
        return "generated \(generated), expires \(expiry)"
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.bgCardSoft)
                Rectangle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: geo.size.width * loadProgress)
            }
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let url = article.articleURL {
            ZStack {
                #if canImport(UIKit)
                ArticleWebView(
                    url: url,
                    pageZoom: articlePageZoom,
                    isLoading: $isLoading,
                    progress: $loadProgress,
                    failed: $failedToLoad,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    goBackHandler: $webViewGoBack,
                    goForwardHandler: $webViewGoForward,
                    reloadHandler: $webViewReload,
                    loadURLHandler: $webViewLoadURL,
                    extractArticleHandler: $webViewExtractArticle,
                    applyTranslationHandler: $webViewApplyTranslation,
                    restoreOriginalHandler: $webViewRestoreOriginal,
                    onDocumentChanged: {
                        translationTask?.cancel()
                        translationTask = nil
                        translationGeneration += 1
                        translationState = .original
                    }
                )
                #endif
                if isLoading && loadProgress < 0.2 {
                    loadingOverlay
                }
                if failedToLoad {
                    errorOverlay(url: url)
                }
            }
        } else {
            noURLState
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(palette.textPrimary)
            Text("Loading article…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage)
    }

    /// The web load failed (bad/blocked URL, ATS refusal, timeout, or a
    /// publisher CSP/X-Frame-Options block). Founder doctrine is to keep
    /// the driver in-app, so when we already hold a substantial
    /// `article.summary` from the feed payload we don't push them to
    /// Safari — we render that summary as a clean, scrollable, selectable
    /// in-app reader with the same reader chrome (source pill + category)
    /// and demote Retry / Open-in-Safari to secondary actions. Only when
    /// the summary is too thin to read on its own do we fall back to the
    /// bare Retry / Open-in-Safari card.
    @ViewBuilder
    private func errorOverlay(url: URL) -> some View {
        // ~100 chars is roughly a full sentence — below that the summary
        // is a headline fragment, not something worth reading on its own.
        if article.summary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 100 {
            summaryFallback(url: url)
        } else {
            bareRetryCard(url: url)
        }
    }

    /// In-app readable view of `article.summary` — the graceful path when
    /// the publisher's page won't load but we have real text to show.
    private func summaryFallback(url: URL) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    // Reader eyebrow — source + category, matching the
                    // top-bar and the translated-article reader.
                    HStack(spacing: Space.s2) {
                        CategoryTag(category: article.typedCategory, compact: true)
                        Text(article.source)
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }

                    Text(article.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Publisher summary")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)

                    Text(article.summary)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Honest note: this is the feed summary, not the full
                    // publisher article. Offer the full page without
                    // implying the in-app load is "coming".
                    Text("The full publisher page is currently unavailable in this reader.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineSpacing(3)

                    Spacer(minLength: Space.s6)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }

            IridescentHairline()

            // Secondary actions — try the web view again, or open the
            // publisher's page in the in-app Safari modal.
            HStack(spacing: Space.s2) {
                Button {
                    retryWebLoad(url: url)
                } label: {
                    Text("Try web view")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    inAppSafariSession = NewsSafariSession(id: UUID(), url: url)
                } label: {
                    Text("Open in Safari")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage)
    }

    /// Thin-summary path: nothing substantial to read in-app, so keep
    /// the original Retry / Open-in-Safari card.
    private func bareRetryCard(url: URL) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Brand.warning)
            Text("Couldn't load this page")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            if !article.summary.isEmpty {
                VStack(spacing: Space.s2) {
                    Text("Publisher summary")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                    Text(article.summary)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(8)
                }
                .padding(.horizontal, Space.s5)
            }
            HStack(spacing: Space.s2) {
                Button {
                    retryWebLoad(url: url)
                } label: {
                    Text("Retry")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 10)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    inAppSafariSession = NewsSafariSession(id: UUID(), url: url)
                } label: {
                    Text("Open in Safari")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 10)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Space.s2)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage)
    }

    /// Re-hit the original article URL. If a translation was active
    /// before the failure, the coordinator re-runs the Translate
    /// injection on the fresh load.
    private func retryWebLoad(url: URL) {
        resetTranslation()
        failedToLoad = false
        isLoading = true
        loadProgress = 0
        webViewLoadURL?(url)
    }

    private var noURLState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(article.title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if !article.summary.isEmpty {
                Text("Publisher summary")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Text(article.summary)
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("No valid publisher page link was provided.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - ArticleWebView (UIKit bridge)

#if canImport(UIKit)
/// WKWebView wrapped as a SwiftUI view. Exposes load progress + a back
/// handler so the reader's top bar can drive in-page navigation.
private struct ArticleWebView: UIViewRepresentable {
    let url: URL
    let pageZoom: CGFloat
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var failed: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var goBackHandler: (() -> Void)?
    /// Forward-navigation handler the parent reader's top-bar chevron
    /// drives once the driver has stepped back in the in-page history.
    @Binding var goForwardHandler: (() -> Void)?
    /// In-place page refresh used by the app-wide current-surface contract.
    @Binding var reloadHandler: (() -> Void)?
    /// Handler the parent reader assigns so it can push a new URL into
    /// the same WKWebView instance (retry flow).
    @Binding var loadURLHandler: ((URL) -> Void)?
    @Binding var extractArticleHandler: ((@escaping (Result<ArticleTranslationDocument, Error>) -> Void) -> Void)?
    @Binding var applyTranslationHandler: (([ArticleTranslatedSegment], @escaping (Result<Int, Error>) -> Void) -> Void)?
    @Binding var restoreOriginalHandler: ((@escaping (Bool) -> Void) -> Void)?
    let onDocumentChanged: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.pageZoom = pageZoom

        context.coordinator.observeProgress(on: webView)
        goBackHandler = { [weak webView] in webView?.goBack() }
        goForwardHandler = { [weak webView] in webView?.goForward() }
        reloadHandler = { [weak webView] in webView?.reload() }
        loadURLHandler = { [weak webView] newURL in
            webView?.load(URLRequest(url: newURL))
        }
        extractArticleHandler = { [weak webView] completion in
            guard let webView else {
                completion(.failure(ArticleTranslationContractError.invalidDocument))
                return
            }
            Task { @MainActor in
                do {
                    let value = try await webView.callAsyncJavaScript(
                        ArticleTranslationDOM.extractScript,
                        arguments: [:],
                        in: nil,
                        contentWorld: .defaultClient
                    )
                    guard let value else {
                        throw ArticleTranslationContractError.invalidDocument
                    }
                    completion(.success(try ArticleTranslationDocument(
                        javaScriptValue: value,
                        fallbackURL: url
                    )))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        applyTranslationHandler = { [weak webView] segments, completion in
            guard let webView else {
                completion(.failure(ArticleTranslationContractError.responseMismatch))
                return
            }
            let translations = segments.map { ["id": $0.id, "text": $0.text] }
            Task { @MainActor in
                do {
                    let value = try await webView.callAsyncJavaScript(
                        ArticleTranslationDOM.applyScript,
                        arguments: ["translations": translations],
                        in: nil,
                        contentWorld: .defaultClient
                    )
                    let dictionary = value as? [String: Any]
                    if let count = dictionary?["appliedCount"] as? NSNumber {
                        completion(.success(count.intValue))
                    } else {
                        completion(.failure(ArticleTranslationContractError.responseMismatch))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
        restoreOriginalHandler = { [weak webView] completion in
            guard let webView else {
                completion(false)
                return
            }
            Task { @MainActor in
                guard let value = try? await webView.callAsyncJavaScript(
                    ArticleTranslationDOM.restoreScript,
                    arguments: [:],
                    in: nil,
                    contentWorld: .defaultClient
                ) else {
                    completion(false)
                    return
                }
                if let restored = value as? Bool {
                    completion(restored)
                } else if let restored = value as? NSNumber {
                    completion(restored.boolValue)
                } else {
                    completion(false)
                }
            }
        }

        // URL-validity guard: WKWebView will choke on a malformed feed
        // URL (no scheme, mailto:, javascript:, a bare relative path) —
        // sometimes with a stuck spinner rather than a clean didFail.
        // We only ever want to drive the web view to real web pages.
        // Anything else short-circuits to the failed state so the
        // reader's in-app summary fallback takes over immediately,
        // keeping the driver inside EusoTrip instead of stalling.
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            Task { @MainActor in
                isLoading = false
                failed = true
            }
            return webView
        }

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep the SwiftUI representable reference fresh so the
        // coordinator's bindings (isLoading, progress, etc.) dispatch
        // back into the current view instance.
        context.coordinator.parent = self
        if abs(webView.pageZoom - pageZoom) > 0.01 {
            webView.pageZoom = pageZoom
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving(webView)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ArticleWebView
        private var progressObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        /// Wall-clock guard: if a page neither finishes nor fails within
        /// 12 s (publisher CDN black-holes the request, infinite redirect,
        /// JS-heavy SPA that never settles), surface the error overlay so
        /// the driver gets Retry / Open-in-Safari instead of a stuck
        /// spinner. Reset on every fresh navigation start.
        private var loadTimeoutTask: Task<Void, Never>?

        init(_ parent: ArticleWebView) {
            self.parent = parent
        }

        func observeProgress(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.parent.progress = wv.estimatedProgress
                }
            }
            canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.parent.canGoBack = wv.canGoBack
                }
            }
            canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.parent.canGoForward = wv.canGoForward
                }
            }
        }

        func stopObserving(_ webView: WKWebView) {
            progressObservation?.invalidate()
            progressObservation = nil
            canGoBackObservation?.invalidate()
            canGoBackObservation = nil
            canGoForwardObservation?.invalidate()
            canGoForwardObservation = nil
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
        }

        /// Arm the stall watchdog for the current navigation.
        private func armLoadTimeout() {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    // Only fire if the page never settled.
                    if self.parent.isLoading {
                        self.parent.isLoading = false
                        self.parent.failed = true
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            armLoadTimeout()
            Task { @MainActor in
                parent.onDocumentChanged()
                parent.isLoading = true
                parent.failed = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
            Task { @MainActor in
                parent.isLoading = false
                parent.progress = 1.0
                // A slow page can finish after the watchdog exposed the
                // summary fallback. The successful main-frame completion is
                // authoritative and must remove that now-stale overlay.
                parent.failed = false
            }
            // Translation remains in this mounted document. No reader
            // replacement or publisher-page navigation is involved.
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
            // -999 (NSURLErrorCancelled) fires whenever a new navigation
            // supersedes an in-flight one (redirects, user tapping a link
            // mid-load). It is NOT a real failure — treating it as one
            // paints the error overlay over a perfectly good page.
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor in
                parent.isLoading = false
                parent.failed = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor in
                parent.isLoading = false
                parent.failed = true
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadTimeoutTask?.cancel()
            loadTimeoutTask = nil
            Task { @MainActor in
                parent.onDocumentChanged()
                parent.isLoading = false
                parent.failed = true
            }
        }
    }
}
#endif

// MARK: - Translation support

/// A target language the driver can translate an article into. The
/// `code` field is the ISO-639-1 (or BCP-47) tag Google Translate's
/// URL proxy expects. The set is curated for EusoTrip's primary driver
/// population (US English base, major Latin-American + European +
/// top-five global languages). Easy to extend as we gather usage data.
struct TranslateLanguage: Hashable, Identifiable {
    let code: String
    let displayName: String
    /// Name in the language itself — shown underneath the English name
    /// so a driver who can't read English can still find their
    /// language in the picker.
    let nativeName: String
    /// Flag-style emoji used purely as a visual anchor in the picker
    /// row. Approximate (languages aren't countries) but readable.
    let flag: String

    var id: String { code }

    /// Best-effort match of the device's current locale to an entry in
    /// `TranslateLanguage.all`. Falls back to Spanish (the single
    /// most-requested target for US-based EusoTrip drivers per the
    /// onboarding survey) if the device locale isn't in our curated list.
    /// Passing `"en"` would be a no-op for the majority of articles we
    /// serve, so English is intentionally NOT the fallback.
    static var deviceDefault: TranslateLanguage {
        let raw = Locale.current.language.languageCode?.identifier ?? "en"
        // Chinese has two entries — disambiguate on the region.
        if raw == "zh" {
            let region = Locale.current.region?.identifier ?? ""
            if ["TW", "HK", "MO"].contains(region) {
                return all.first { $0.code == "zh-TW" } ?? all[0]
            }
            return all.first { $0.code == "zh-CN" } ?? all[0]
        }
        if let match = all.first(where: { $0.code.lowercased() == raw.lowercased() }) {
            return match
        }
        return all.first { $0.code == "es" } ?? all[0]
    }

    static let all: [TranslateLanguage] = [
        .init(code: "es",    displayName: "Spanish",           nativeName: "Español",             flag: "🇪🇸"),
        .init(code: "fr",    displayName: "French",            nativeName: "Français",            flag: "🇫🇷"),
        .init(code: "pt",    displayName: "Portuguese",        nativeName: "Português",           flag: "🇵🇹"),
        .init(code: "de",    displayName: "German",            nativeName: "Deutsch",             flag: "🇩🇪"),
        .init(code: "it",    displayName: "Italian",           nativeName: "Italiano",            flag: "🇮🇹"),
        .init(code: "nl",    displayName: "Dutch",             nativeName: "Nederlands",          flag: "🇳🇱"),
        .init(code: "pl",    displayName: "Polish",            nativeName: "Polski",              flag: "🇵🇱"),
        .init(code: "ru",    displayName: "Russian",           nativeName: "Русский",             flag: "🇷🇺"),
        .init(code: "uk",    displayName: "Ukrainian",         nativeName: "Українська",          flag: "🇺🇦"),
        .init(code: "ar",    displayName: "Arabic",            nativeName: "العربية",             flag: "🇸🇦"),
        .init(code: "he",    displayName: "Hebrew",            nativeName: "עברית",               flag: "🇮🇱"),
        .init(code: "tr",    displayName: "Turkish",           nativeName: "Türkçe",              flag: "🇹🇷"),
        .init(code: "hi",    displayName: "Hindi",             nativeName: "हिन्दी",                 flag: "🇮🇳"),
        .init(code: "bn",    displayName: "Bengali",           nativeName: "বাংলা",                flag: "🇧🇩"),
        .init(code: "ur",    displayName: "Urdu",              nativeName: "اردو",                flag: "🇵🇰"),
        .init(code: "pa",    displayName: "Punjabi",           nativeName: "ਪੰਜਾਬੀ",               flag: "🇮🇳"),
        .init(code: "zh-CN", displayName: "Chinese (Simplified)", nativeName: "简体中文",           flag: "🇨🇳"),
        .init(code: "zh-TW", displayName: "Chinese (Traditional)", nativeName: "繁體中文",          flag: "🇹🇼"),
        .init(code: "ja",    displayName: "Japanese",          nativeName: "日本語",               flag: "🇯🇵"),
        .init(code: "ko",    displayName: "Korean",            nativeName: "한국어",               flag: "🇰🇷"),
        .init(code: "vi",    displayName: "Vietnamese",        nativeName: "Tiếng Việt",          flag: "🇻🇳"),
        .init(code: "th",    displayName: "Thai",              nativeName: "ไทย",                 flag: "🇹🇭"),
        .init(code: "id",    displayName: "Indonesian",        nativeName: "Bahasa Indonesia",    flag: "🇮🇩"),
        .init(code: "fil",   displayName: "Filipino",          nativeName: "Filipino",            flag: "🇵🇭"),
        .init(code: "sw",    displayName: "Swahili",           nativeName: "Kiswahili",           flag: "🇰🇪"),
        .init(code: "en",    displayName: "English",           nativeName: "English",             flag: "🇺🇸"),
    ]
}

/// Sheet that presents the language list. Pure presentation — all
/// state lives in the parent `NewsArticleReader` so the picker can't
/// go out of sync with the web view's current URL.
private struct LanguagePickerSheet: View {
    @Environment(\.palette) var palette
    let active: TranslateLanguage?
    /// The driver's device-locale language, surfaced as a one-tap
    /// "Translate to X" shortcut at the top of the sheet. `nil` if the
    /// caller didn't supply one (back-compat).
    let suggested: TranslateLanguage?
    let onPick: (TranslateLanguage) -> Void
    let onReset: () -> Void

    @State private var query: String = ""

    private var filtered: [TranslateLanguage] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return TranslateLanguage.all }
        return TranslateLanguage.all.filter {
            $0.displayName.lowercased().contains(q)
            || $0.nativeName.lowercased().contains(q)
            || $0.code.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate article")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(
                        active.map { "Currently: \($0.displayName)" }
                        ?? "Pick a language for the complete readable article."
                    )
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if active != nil {
                    Button(action: onReset) {
                        Text("Reset")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .background(palette.bgCardSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(palette.borderFaint)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset to original language")
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            // Search field — keeps the list usable as we grow it.
            HStack(spacing: Space.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                TextField("Search languages", text: $query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(palette.textPrimary)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s3)

            if let suggested, active != suggested, query.isEmpty {
                Button {
                    onPick(suggested)
                } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Translate to \(suggested.displayName)")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text("Matches your device language")
                                .font(EType.micro)
                                .foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        Text(suggested.flag)
                            .font(.system(size: 20))
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Translate article to \(suggested.displayName)")
            }

            Divider().background(palette.borderFaint)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { lang in
                        Button {
                            onPick(lang)
                        } label: {
                            HStack(spacing: Space.s3) {
                                Text(lang.flag)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang.displayName)
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(lang.nativeName)
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if active == lang {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        // Doctrine §2.1 gradient-not-blue: selected-language
                                        // checkmark is a brand-accent confirmation — must render
                                        // the blue→magenta gradient, not flat Brand.blue.
                                        // 32nd firing hygiene sweep.
                                        .foregroundStyle(LinearGradient.diagonal)
                                }
                            }
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().background(palette.borderFaint)
                    }
                    if filtered.isEmpty {
                        Text("No matches")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.vertical, Space.s5)
                    }
                }
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
    }
}

// MARK: - Structured same-document translation

private enum ArticleTranslationDOM {
    static let extractScript = #"""
    const excludedSelector = [
      "nav", "header", "footer", "aside", "form", "button", "input", "select", "textarea",
      "script", "style", "noscript", "iframe", "canvas", "svg", "dialog", "[hidden]", "[inert]",
      "[aria-hidden='true']", "[role='navigation']", "[role='banner']", "[role='complementary']",
      "[role='contentinfo']", "[translate='no']", ".advertisement", ".advertising", ".ad-container",
      "[data-ad]", "[aria-label*='advertisement' i]", ".social-share", ".share-tools", ".newsletter",
      ".subscribe", ".subscription", ".related", ".recommended", ".comments", ".comment-list",
      ".author-bio", ".cookie", ".paywall", ".promo", ".toolbar", ".breadcrumbs"
    ].join(",");
    const blockSelector = "h1,h2,h3,h4,h5,h6,p,li,blockquote,figcaption,caption,th,td,dt,dd";
    const candidateSelector = [
      "[itemprop='articleBody']", "article", "[role='article']", ".article-body", ".article-content",
      ".entry-content", ".post-content", ".story-body", ".story__body", "main", "[role='main']"
    ].join(",");

    function visible(element) {
      if (!element || !element.isConnected) return false;
      const style = getComputedStyle(element);
      return style.display !== "none" && style.visibility !== "hidden" && style.opacity !== "0";
    }

    function excluded(element, root) {
      if (!element) return true;
      const blocked = element.closest(excludedSelector);
      return Boolean(blocked && (blocked === root || root.contains(blocked)));
    }

    function kindFor(element) {
      const tag = element.tagName.toLowerCase();
      if (/^h[1-6]$/.test(tag)) return "heading";
      if (tag === "li" || tag === "dt" || tag === "dd") return "listItem";
      if (tag === "blockquote") return "quote";
      if (tag === "figcaption" || tag === "caption") return "caption";
      if (tag === "th" || tag === "td") return "tableCell";
      return "paragraph";
    }

    function collect(root, keepReferences) {
      const segments = [];
      const references = [];
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
      let node = walker.currentNode;
      while (node) {
        if (node.nodeType === Node.TEXT_NODE) {
          const parent = node.parentElement;
          const block = parent && parent.closest(blockSelector);
          const code = parent && parent.closest("pre,code,kbd,samp");
          const text = (node.nodeValue || "").trim();
          if (block && (block === root || root.contains(block)) && !code && text &&
              !excluded(parent, root) && visible(block)) {
            const id = `s${segments.length}`;
            segments.push({ id, kind: kindFor(block), text });
            if (keepReferences) {
              references.push({ id, type: "text", node, original: node.nodeValue || "", source: text, applied: false });
            }
          }
        } else if (node.nodeType === Node.ELEMENT_NODE && node.tagName === "IMG") {
          const alt = (node.getAttribute("alt") || "").trim();
          if (alt && !excluded(node, root) && visible(node)) {
            const id = `s${segments.length}`;
            segments.push({ id, kind: "imageAlt", text: alt });
            if (keepReferences) {
              references.push({ id, type: "alt", node, original: node.getAttribute("alt") || "", source: alt, applied: false });
            }
          }
        }
        node = walker.nextNode();
      }
      return { segments, references };
    }

    const candidates = Array.from(new Set(document.querySelectorAll(candidateSelector)));
    let best = null;
    let bestScore = -Infinity;
    for (const candidate of candidates) {
      if (!visible(candidate) || candidate.closest(excludedSelector)) continue;
      const collected = collect(candidate, false);
      const characters = collected.segments.reduce((sum, segment) => sum + segment.text.length, 0);
      if (characters < 200 || collected.segments.length < 3) continue;
      const linkCharacters = Array.from(candidate.querySelectorAll("a"))
        .reduce((sum, link) => sum + (link.innerText || "").trim().length, 0);
      const linkPenalty = Math.min(characters, linkCharacters) * 1.5;
      let semanticBonus = 0;
      if (candidate.matches("article")) semanticBonus = 4000;
      else if (candidate.matches("[itemprop='articleBody'],[role='article']")) semanticBonus = 3500;
      else if (!candidate.matches("main,[role='main']")) semanticBonus = 1800;
      const score = characters + collected.segments.length * 35 + semanticBonus - linkPenalty;
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }

    if (!best) throw new Error("No complete readable article root was found.");
    const collected = collect(best, true);
    const canonicalElement = document.querySelector("link[rel~='canonical'][href]");
    const canonicalURL = canonicalElement ? canonicalElement.href : location.href;
    const sourceLanguage = best.getAttribute("lang") || document.documentElement.lang || null;

    function rectFor(reference) {
      if (!reference.node || !reference.node.isConnected) return null;
      if (reference.type === "alt") return reference.node.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(reference.node);
      return range.getBoundingClientRect();
    }

    function captureAnchor() {
      let chosen = null;
      for (const reference of collected.references) {
        const rect = rectFor(reference);
        if (!rect || rect.bottom < 0 || rect.top > innerHeight) continue;
        if (!chosen || Math.abs(rect.top) < Math.abs(chosen.top)) {
          chosen = { id: reference.id, top: rect.top };
        }
      }
      return chosen || { id: null, top: 0, scrollY };
    }

    function restoreAnchor(anchor) {
      if (!anchor) return;
      if (!anchor.id) {
        scrollTo({ top: anchor.scrollY || 0, left: scrollX, behavior: "instant" });
        return;
      }
      const reference = collected.references.find((item) => item.id === anchor.id);
      const rect = reference && rectFor(reference);
      if (rect) scrollBy(0, rect.top - anchor.top);
    }

    function settle() {
      return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    }

    globalThis.__eusoArticleTranslationV1 = {
      canonicalURL,
      references: collected.references,
      captureAnchor,
      restoreAnchor,
      settle
    };
    return { canonicalURL, sourceLanguage, segments: collected.segments };
    """#

    static let applyScript = #"""
    const state = globalThis.__eusoArticleTranslationV1;
    if (!state || !Array.isArray(translations)) throw new Error("Article translation state is unavailable.");
    const translatedById = new Map();
    for (const item of translations) {
      if (item && typeof item.id === "string" && typeof item.text === "string") {
        translatedById.set(item.id, item.text);
      }
    }
    const anchor = state.captureAnchor();
    let appliedCount = 0;
    for (const reference of state.references) {
      const translated = translatedById.get(reference.id);
      if (typeof translated !== "string" || !translated.trim() || !reference.node || !reference.node.isConnected) continue;
      const current = reference.type === "alt"
        ? (reference.node.getAttribute("alt") || "").trim()
        : (reference.node.nodeValue || "").trim();
      if (!reference.applied && current !== reference.source) continue;
      if (reference.type === "alt") {
        reference.node.setAttribute("alt", translated.trim());
      } else {
        const leading = (reference.original.match(/^\s*/) || [""])[0];
        const trailing = (reference.original.match(/\s*$/) || [""])[0];
        reference.node.nodeValue = leading + translated.trim() + trailing;
      }
      reference.applied = true;
      appliedCount += 1;
    }
    await state.settle();
    state.restoreAnchor(anchor);
    await state.settle();
    return { appliedCount };
    """#

    static let restoreScript = #"""
    const state = globalThis.__eusoArticleTranslationV1;
    if (!state) return false;
    const anchor = state.captureAnchor();
    for (const reference of state.references) {
      if (!reference.applied || !reference.node || !reference.node.isConnected) continue;
      if (reference.type === "alt") reference.node.setAttribute("alt", reference.original);
      else reference.node.nodeValue = reference.original;
      reference.applied = false;
    }
    await state.settle();
    state.restoreAnchor(anchor);
    await state.settle();
    return true;
    """#
}

private struct ArticleTranslationDelivery: Sendable {
    let response: ArticleTranslationResponse
    let localCacheHit: Bool
}

private actor ArticleTranslationClient {
    static let shared = ArticleTranslationClient()

    private var cache: [String: ArticleTranslationResponse] = [:]
    private var loadedCache = false
    private let cacheLimit = 40

    func translate(
        document: ArticleTranslationDocument,
        targetLocale: String,
        forceRefresh: Bool
    ) async throws -> ArticleTranslationDelivery {
        loadCacheIfNeeded()
        let key = "\(document.cacheKey)\u{0000}\(targetLocale.lowercased())"
        if !forceRefresh,
           let cached = cache[key],
           let expiresAt = cached.expiresAtDate,
           expiresAt > Date(),
           let validated = try? cached.validated(for: document, targetLocale: targetLocale) {
            return ArticleTranslationDelivery(response: validated, localCacheHit: true)
        }

        cache[key] = nil
        let request = ArticleTranslationRequest(
            document: document,
            targetLocale: targetLocale,
            forceRefresh: forceRefresh
        )
        let response: ArticleTranslationResponse = try await EusoTripAPI.shared.mutation(
            "articleTranslation.translate",
            input: request
        )
        let validated = try response.validated(for: document, targetLocale: targetLocale)
        if validated.status != .unavailable,
           let expiresAt = validated.expiresAtDate,
           expiresAt > Date() {
            cache[key] = validated
            trimCache()
            persistCache()
        }
        return ArticleTranslationDelivery(response: validated, localCacheHit: false)
    }

    private func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        guard
            let data = try? Data(contentsOf: cacheURL),
            let decoded = try? JSONDecoder().decode([String: ArticleTranslationResponse].self, from: data)
        else { return }
        let now = Date()
        cache = decoded.filter { $0.value.expiresAtDate.map { $0 > now } == true }
        trimCache()
    }

    private func trimCache() {
        guard cache.count > cacheLimit else { return }
        let orderedKeys = cache.keys.sorted {
            (cache[$0]?.generatedAtDate ?? .distantPast) < (cache[$1]?.generatedAtDate ?? .distantPast)
        }
        for key in orderedKeys.prefix(cache.count - cacheLimit) {
            cache[key] = nil
        }
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("article-translations-v1.json", isDirectory: false)
    }
}

private struct ArticleTranslationTimeoutError: Error {}

private func withArticleTranslationTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ArticleTranslationTimeoutError()
        }
        guard let first = try await group.next() else {
            throw ArticleTranslationTimeoutError()
        }
        group.cancelAll()
        return first
    }
}

// MARK: - In-app SFSafariViewController bridge for the news reader

/// Hosts the article publisher's URL in an in-app modal so the
/// "Open in Safari" affordance doesn't actually kick the driver out
/// of the EusoTrip app. SFSafariViewController preserves cookies +
/// paywall sessions exactly like Safari does — it's just chromed
/// as an EusoTrip modal.
private struct NewsInAppSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = true
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.dismissButtonStyle = .done
        vc.preferredControlTintColor = UIColor(Brand.magenta)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
