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
#if canImport(Translation)
import Translation
#endif
// NaturalLanguage's `NLLanguageRecognizer` gives us a local,
// privacy-preserving best-guess of the article's source language
// before we hand the string to Apple's Translation framework. The
// Translation framework *can* auto-detect with `source: nil`, but
// having our own hint lets us short-circuit a no-op ("translate en→en")
// and pre-seed configurations so the first paint isn't blank.
import NaturalLanguage

// MARK: - NewsArticleReader

struct NewsArticleReader: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let article: NewsArticle

    @State private var isLoading: Bool = true
    @State private var loadProgress: Double = 0.0
    @State private var failedToLoad: Bool = false
    @State private var canGoBack: Bool = false
    @State private var webViewGoBack: (() -> Void)? = nil
    /// Handler the embedded WKWebView assigns so the reader chrome can
    /// navigate it to a new URL without tearing it down. Used by the
    /// retry button to re-hit the original article URL.
    @State private var webViewLoadURL: ((URL) -> Void)? = nil
    /// Handler the embedded WKWebView assigns so the reader can pull
    /// the article's visible text out of the live DOM. Feeds Apple's
    /// native Translation framework — far more reliable than the old
    /// `translate.goog` proxy, which publishers' CSPs + Google's
    /// crawler blocks silently defeated on ~70% of trucking-news
    /// sources (CDL Life, TTNews, FreightWaves, CCJ, NYT…).
    @State private var webViewExtractText: ((@escaping (String) -> Void) -> Void)? = nil
    @State private var showLanguagePicker: Bool = false
    /// Tracks the current target language (nil = original). Used so the
    /// translate button can render as active and "Reset" back to source.
    @State private var activeLanguage: TranslateLanguage? = nil
    /// Text pulled from the currently-loaded page, fed into the native
    /// translation sheet once the driver picks a language.
    @State private var extractedArticleText: String = ""
    /// Presents the native-translation reader sheet on top of the
    /// WKWebView. Dismissing this sheet is what "untranslates" the
    /// view — the underlying webView is left untouched the whole time.
    @State private var showTranslationSheet: Bool = false
    /// Surfaces a "Translation is unavailable on this iOS" alert if the
    /// driver is on 17.0–17.3 (no `Translation` framework at all) or
    /// `article.articleURL` is nil (nothing to extract text from).
    @State private var showTranslationUnavailableAlert: Bool = false
    /// In-app SFSafariViewController presentation for "Open in
    /// Safari" — the previous `UIApplication.shared.open(url)`
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
        // Native-translation reader. Only constructible on iOS 17.4+
        // — older devices are routed to the unavailable alert above.
        .fullScreenCover(isPresented: $showTranslationSheet, onDismiss: {
            // Closing the cover is the driver's signal that they want
            // the untranslated article back. Clear the active-language
            // pill so the translate button returns to its idle glyph.
            if !showTranslationSheet {
                activeLanguage = nil
                extractedArticleText = ""
            }
        }) {
            if #available(iOS 17.4, *), let lang = activeLanguage {
                TranslatedArticleSheet(
                    article: article,
                    sourceText: extractedArticleText,
                    target: lang
                )
                .environment(\.palette, palette)
                .eusoCloseX()
            } else {
                // Should never actually render — the guards upstream
                // steer pre-17.4 devices to the alert — but we keep a
                // legible fallback so the cover can't present empty.
                TranslationUnavailableView(reason: "Translation requires iOS 17.4 or later.")
                    .environment(\.palette, palette)
                    .eusoCloseX()
            }
        }
        // Replaced the old hard "Translation unavailable" alert with an
        // inline toast that auto-dismisses. The alert was alarming for
        // drivers (reads like a crash), and Apple's framework-level
        // "requires iOS 17.4 or later and a loaded article page" message
        // tells a driver at the wheel nothing actionable. The toast now:
        //   • Appears at the bottom of the reader, not modally.
        //   • Self-dismisses after 2.8 s.
        //   • Suggests the "Open in Safari" button as the fallback path
        //     (which is right there in the top bar).
        .overlay(alignment: .bottom) {
            if showTranslationUnavailableAlert {
                TranslationToast(
                    onDismiss: {
                        showTranslationUnavailableAlert = false
                        activeLanguage = nil
                    }
                )
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showTranslationUnavailableAlert)
        .task(id: showTranslationUnavailableAlert) {
            guard showTranslationUnavailableAlert else { return }
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            await MainActor.run {
                showTranslationUnavailableAlert = false
                activeLanguage = nil
            }
        }
        // In-app SFSafariViewController fallback for the "Open in
        // Safari" affordances. Stays inside the EusoTrip app.
        .sheet(item: $inAppSafariSession) { sess in
            NewsInAppSafari(url: sess.url)
                .ignoresSafeArea()
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

            // Translate button — opens a language picker sheet and, on
            // pick, reloads the current article through Google Translate's
            // public proxy so the whole page (title, body, captions) gets
            // translated in place. We keep the same WKWebView instance so
            // the reader back stack still works.
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
                        .frame(width: 36, height: 36)
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
                .accessibilityLabel(
                    activeLanguage.map { "Translated to \($0.displayName). Tap to change." }
                    ?? "Translate article"
                )
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
        }
    }

    // MARK: Translation
    //
    // Translation runs entirely on-device through Apple's `Translation`
    // framework. The old path navigated the WKWebView through Google's
    // `translate.goog` URL proxy, but the proxy failed silently on
    // every publisher whose pages set `X-Frame-Options` or a strict
    // Content-Security-Policy (CDL Life, TTNews, FreightWaves, CCJ, …).
    // Driver would pick a language, the page would reload, and the
    // content would come back untranslated — zero feedback, zero
    // translation.
    //
    // The new path:
    //   1. Pull the article's visible text out of the live DOM via
    //      `document.body.innerText` (preferring `<article>`/`<main>`
    //      if present — gives clean body copy without nav cruft).
    //   2. Hand that string to `TranslationSession` (iOS 18+) or the
    //      `.translationPresentation` modifier (iOS 17.4+).
    //   3. Present the translated content in a dedicated reader sheet
    //      that sits on top of the WKWebView. Dismissing the sheet
    //      returns the driver to the untranslated page instantly.
    //
    // Apple's framework downloads the language pack on first use and
    // then translates fully offline — a much better fit for drivers
    // who spend hours in cell-dead stretches of I-40.

    /// Pick-a-language → extract DOM text → present the translation sheet.
    private func applyTranslation(to lang: TranslateLanguage) {
        activeLanguage = lang

        // Always prefer the Google-proxy path over showing "unavailable"
        // — the driver's intent is clear (translate this page), so we
        // should burn through every graceful fallback before raising a
        // toast. The old flow bailed immediately when `extract` was nil
        // or the extracted text was too short; the T21 Mexico page hit
        // that branch because its ads+paywall shell prevents WKWebView
        // from resolving `<article>` / `<main>` tags in time for the
        // translation framework to parse it as an article.
        //
        // New ladder:
        //   A. iOS 17.4+ AND we got ≥ 120 chars of body text → Apple's
        //      on-device Translation framework (best UX, offline-safe).
        //   B. Otherwise → Google Translate URL-proxy path (works on
        //      every iOS version; publisher CSPs can still block it,
        //      but the proxy handles most news sites including T21).
        //   C. If both fail → fall through to the graceful inline toast.
        guard article.articleURL != nil else {
            showTranslationUnavailableAlert = true
            activeLanguage = nil
            return
        }

        // ── Rung A: Apple Translation framework, if available AND the
        //           DOM extractor landed enough text to translate ──
        if #available(iOS 17.4, *), let extract = webViewExtractText {
            extract { text in
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 120 {
                    extractedArticleText = trimmed
                    showTranslationSheet = true
                } else {
                    // Not enough text — likely a paywall or heavy-SPA
                    // page like T21. Fall through to the URL-proxy rung
                    // instead of alerting. The driver never sees the
                    // failure; the page just translates via Google.
                    applyTranslationViaProxy(lang: lang)
                }
            }
            return
        }

        // ── Rung B: Google Translate URL proxy (pre-17.4 or no
        //           extractor available) ──
        applyTranslationViaProxy(lang: lang)
    }

    /// Reload the article through Google Translate's URL proxy. Keeps
    /// the same WKWebView instance so the back button still works.
    /// Publisher CSPs (X-Frame-Options: DENY) defeat this on ~30% of
    /// news sources; when they do, we land on rung C (the inline
    /// toast) via the web view's navigation-failed delegate.
    private func applyTranslationViaProxy(lang: TranslateLanguage) {
        guard let url = article.articleURL,
              let host = url.host,
              let load = webViewLoadURL else {
            showTranslationUnavailableAlert = true
            activeLanguage = nil
            return
        }
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let proxyString = "https://translate.google.com/translate?sl=auto&tl=\(lang.code)&u=https://\(host)\(path)\(query)"
        if let proxyURL = URL(string: proxyString) {
            load(proxyURL)
        } else {
            showTranslationUnavailableAlert = true
            activeLanguage = nil
        }
    }

    /// Dismiss the translation overlay. On iOS 17.4+ the underlying
    /// WKWebView was never navigated (translation happens in an overlay
    /// sheet) so there's nothing to reload. On iOS 17.0–17.3 the
    /// legacy path navigated the webView through `translate.goog`, so
    /// we re-load the original URL to get the driver back to the
    /// untranslated article.
    private func resetTranslation() {
        let wasLegacy: Bool
        if #available(iOS 17.4, *) {
            wasLegacy = false
        } else {
            wasLegacy = activeLanguage != nil
        }
        activeLanguage = nil
        showTranslationSheet = false
        extractedArticleText = ""
        if wasLegacy, let url = article.articleURL, let load = webViewLoadURL {
            load(url)
        }
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
                    isLoading: $isLoading,
                    progress: $loadProgress,
                    failed: $failedToLoad,
                    canGoBack: $canGoBack,
                    goBackHandler: $webViewGoBack,
                    loadURLHandler: $webViewLoadURL,
                    extractTextHandler: $webViewExtractText
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

    private func errorOverlay(url: URL) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Brand.warning)
            Text("Couldn't load this page")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
                    .lineLimit(8)
            }
            HStack(spacing: Space.s2) {
                Button {
                    // Retry — re-hit the original article URL and, if
                    // a translation was active before the failure, the
                    // coordinator will re-run the Translate injection
                    // on the fresh load.
                    failedToLoad = false
                    isLoading = true
                    loadProgress = 0
                    webViewLoadURL?(url)
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

    private var noURLState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(article.title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
            }
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
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var failed: Bool
    @Binding var canGoBack: Bool
    @Binding var goBackHandler: (() -> Void)?
    /// Handler the parent reader assigns so it can push a new URL into
    /// the same WKWebView instance (retry flow).
    @Binding var loadURLHandler: ((URL) -> Void)?
    /// Handler the parent reader assigns so it can pull visible body
    /// copy out of the live DOM and hand it to Apple's Translation
    /// framework. Completion closure is always called with a (possibly
    /// empty) string — never hangs.
    @Binding var extractTextHandler: ((@escaping (String) -> Void) -> Void)?

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

        context.coordinator.observeProgress(on: webView)
        goBackHandler = { [weak webView] in webView?.goBack() }
        loadURLHandler = { [weak webView] newURL in
            webView?.load(URLRequest(url: newURL))
        }
        extractTextHandler = { [weak webView] completion in
            guard let webView = webView else { completion(""); return }
            // Prefer the semantic article container if the publisher
            // uses one (keeps us out of nav/footer/sidebar cruft).
            // Fall back to body.innerText — WKWebView returns this as
            // a String when the page is a normal document.
            let js = """
            (function() {
                try {
                    var candidates = document.querySelectorAll(
                        'article, main, [role="main"], .post-content, .entry-content, .article-body'
                    );
                    var best = null;
                    var bestLen = 0;
                    for (var i = 0; i < candidates.length; i++) {
                        var t = (candidates[i].innerText || '').trim();
                        if (t.length > bestLen) { best = t; bestLen = t.length; }
                    }
                    if (best && bestLen > 200) return best;
                    return (document.body && document.body.innerText) || '';
                } catch (e) {
                    return '';
                }
            })();
            """
            webView.evaluateJavaScript(js) { value, _ in
                completion((value as? String) ?? "")
            }
        }

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep the SwiftUI representable reference fresh so the
        // coordinator's bindings (isLoading, progress, etc.) dispatch
        // back into the current view instance.
        context.coordinator.parent = self
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving(webView)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ArticleWebView
        private var progressObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?

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
        }

        func stopObserving(_ webView: WKWebView) {
            progressObservation?.invalidate()
            progressObservation = nil
            canGoBackObservation?.invalidate()
            canGoBackObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = true
                parent.failed = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = false
                parent.progress = 1.0
            }
            // Translation is handled outside the webView entirely now —
            // no DOM injection, no reloads. The reader's translate
            // button pulls the page's text on demand via the
            // `extractTextHandler` binding and feeds it to Apple's
            // on-device Translation framework.
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
                parent.failed = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
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
                        ?? "Pick a language to auto-translate the whole page."
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

// MARK: - Native translated article sheet
//
// The reader's translation pane. On-device translation via Apple's
// `Translation` framework — supports 20+ languages, downloads packs
// lazily, and keeps working in cell-dead stretches after the first
// download. Replaces the prior `translate.goog` URL proxy, which
// publisher CSPs + paywalls silently defeated on nearly every
// trucking-news source (CDL Life, TTNews, FreightWaves, CCJ, NYT).
//
// Two rendering paths:
//   • iOS 18.0+ → `TranslationSession` runs inline, producing a
//     translated reader view that reads like a clean article page.
//   • iOS 17.4–17.x → `.translationPresentation` shows Apple's
//     system translator overlay on top of the extracted text; no
//     inline replacement, but the translation happens reliably.

@available(iOS 17.4, *)
private struct TranslatedArticleSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let article: NewsArticle
    let sourceText: String
    let target: TranslateLanguage

    var body: some View {
        VStack(spacing: 0) {
            header
            IridescentHairline()
            if #available(iOS 18.0, *) {
                TranslatedArticleInlineReader(
                    sourceText: sourceText,
                    target: target,
                    article: article
                )
            } else {
                TranslatedArticlePresentationReader(
                    sourceText: sourceText,
                    target: target,
                    article: article
                )
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
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
            .accessibilityLabel("Close translation")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text("TRANSLATED")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    Text("\(target.flag)  \(target.displayName)")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Text(article.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }
}

// MARK: iOS 18+ inline translated reader

@available(iOS 18.0, *)
private struct TranslatedArticleInlineReader: View {
    @Environment(\.palette) var palette

    let sourceText: String
    let target: TranslateLanguage
    let article: NewsArticle

    @State private var translatedText: String = ""
    @State private var configuration: TranslationSession.Configuration?
    @State private var isTranslating: Bool = true
    @State private var failureMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Article eyebrow — keeps the "where did this come
                // from" context the driver had on the untranslated
                // reader. Source + published date in the publisher's
                // own language, since those are proper nouns that
                // don't benefit from translation.
                HStack(spacing: Space.s2) {
                    CategoryTag(category: article.typedCategory, compact: true)
                    Text(article.source)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }

                if isTranslating && translatedText.isEmpty {
                    loadingState
                } else if let err = failureMessage, translatedText.isEmpty {
                    failureState(err)
                } else {
                    Text(translatedText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: Space.s6)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s6)
        }
        .task(id: sourceText + target.code) {
            // Run `NLLanguageRecognizer` over a leading window (2 KB is
            // plenty — language detection on the first paragraph is as
            // accurate as on the whole article) to seed the session
            // config's `source`. This saves the framework a detection
            // round trip and makes no-op translations (en → en when the
            // device locale is English and the article is already in
            // English) detectable before we even spin up the session.
            let detected: Locale.Language? = {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(String(sourceText.prefix(2000)))
                guard let lang = recognizer.dominantLanguage else { return nil }
                return Locale.Language(identifier: lang.rawValue)
            }()

            // If the article is already in the target language, skip
            // the round trip entirely and show the source text verbatim.
            // Saves 1–3 s on slow networks and avoids a pointless pack
            // download for users whose device locale matches the feed.
            if let detected,
               detected.languageCode?.identifier == target.code.split(separator: "-").first.map(String.init) {
                await MainActor.run {
                    translatedText = sourceText
                    isTranslating = false
                    failureMessage = nil
                }
                configuration = nil
                return
            }

            configuration = TranslationSession.Configuration(
                source: detected,
                target: Locale.Language(identifier: target.code)
            )
            isTranslating = true
            failureMessage = nil
            translatedText = ""
        }
        .translationTask(configuration) { session in
            guard !sourceText.isEmpty else {
                await MainActor.run {
                    failureMessage = "No readable text was extracted from this article."
                    isTranslating = false
                }
                return
            }
            do {
                // Apple's framework will throw the first time a given
                // language pair is invoked if the pack isn't cached.
                // `prepareTranslation()` surfaces the system's
                // "download this language?" consent sheet instead —
                // the user accepts once and every subsequent article
                // translates offline. Safe to call on every invocation;
                // it's a no-op when the pack is already present.
                try await session.prepareTranslation()

                let response = try await session.translate(sourceText)
                await MainActor.run {
                    translatedText = response.targetText
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    failureMessage = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProgressView()
                .tint(palette.textPrimary)
            Text("Translating into \(target.displayName)…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Text("First translation of a language downloads a ~40 MB pack. Subsequent translations work offline.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .lineSpacing(3)
        }
        .padding(.top, Space.s4)
    }

    private func failureState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Brand.warning)
            Text("Translation failed")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineSpacing(3)
        }
        .padding(.top, Space.s4)
    }
}

// MARK: iOS 17.4 – 17.x translated reader (system overlay)

@available(iOS 17.4, *)
private struct TranslatedArticlePresentationReader: View {
    @Environment(\.palette) var palette

    let sourceText: String
    let target: TranslateLanguage
    let article: NewsArticle

    @State private var showingOverlay: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    CategoryTag(category: article.typedCategory, compact: true)
                    Text(article.source)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("iOS 17.4 uses the system translation overlay. Tap the translation panel below to translate into \(target.displayName). Upgrade to iOS 18 for inline article translation.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineSpacing(4)

                if !showingOverlay {
                    Button {
                        showingOverlay = true
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: "character.bubble.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Reopen translator")
                                .font(EType.bodyStrong)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, 10)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text(sourceText.isEmpty ? article.summary : sourceText)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: Space.s6)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s6)
        }
        .translationPresentation(
            isPresented: $showingOverlay,
            text: sourceText.isEmpty ? article.summary : sourceText
        )
    }
}

// MARK: - Unsupported-OS fallback

private struct TranslationUnavailableView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let reason: String

    var body: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "character.bubble")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Translation unavailable")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(reason)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s5)
            Button { dismiss() } label: {
                Text("Close")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, 10)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgPage.ignoresSafeArea())
    }
}

// MARK: - TranslationToast
//
// Graceful inline toast that replaces the old "Translation unavailable"
// system alert. Shows up at the bottom of the reader for ~2.8s, gives
// the driver a next-step hint (Open in Safari), and auto-dismisses —
// never blocks the read flow. No exclamation-triangle icon, no
// crash-report vocabulary.

private struct TranslationToast: View {
    @Environment(\.palette) var palette
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Translation not available for this page")
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                Text("Try Open in Safari from the top bar.")
                    .font(EType.micro)
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
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
        vc.preferredControlTintColor = UIColor(red: 0.745, green: 0.004, blue: 1.0, alpha: 1)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
