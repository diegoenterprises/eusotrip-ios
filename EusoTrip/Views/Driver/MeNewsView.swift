//
//  MeNewsView.swift
//  EusoTrip — Driver Intel News screen (Me → Driver Intel)
//  and the rotating headline widget on DriverHome.
//
//  Mirrors the web platform's `/news` surface (and the 2027 UI wireframe at
//  `EusoTrip 2027 UI Wireframes/news-feed-section.html`):
//    • Gradient hero header with back button + search field
//    • Horizontally-scrolling category chips (All, Trucking, Regulatory…)
//    • Breaking strip (clusters of 2h-old articles from 3+ sources)
//    • Role-personalised morning brief summary
//    • Hero article card + card list, each showing the scraped image
//      (fallback: gradient placeholder keyed by category) + source pill
//
//  Authority: frontend/server/routers/news.ts (RSSArticle) — see
//  NewsArticle.swift for the Codable mirror.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MeNewsView

struct MeNewsView: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = NewsFeedStore()
    /// Selected article pushed to an in-app reader sheet. Replaces the
    /// old `UIApplication.shared.open()` hand-off to Safari so drivers
    /// never leave the EusoTrip shell when they tap a headline.
    @State private var readerArticle: NewsArticle?

    /// Category chips shown in the filter row. Order mirrors the web
    /// wireframe (driver-centric).
    private let chipOrder: [NewsCategory] = [
        .all, .trucking, .regulatory, .hazmat, .safety,
        .energy, .oil_gas, .logistics, .market, .supply_chain,
        .chemical, .bulk, .refrigerated, .marine, .technology, .equipment
    ]

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {

                searchField

                if let summary = store.morningSummary, !summary.isEmpty {
                    morningBriefCard(summary)
                }

                categoryChips

                if store.isLoading && store.articles.isEmpty {
                    loadingPlaceholder
                } else if let err = store.lastError, store.articles.isEmpty {
                    errorState(err)
                } else {
                    articleList
                }

                // Reserve clearance under the floating BottomNav pill.
                Color.clear
                    .frame(height: Space.s6)
            }
            // Slimmer gutter (s4 = 16pt) so the hero image card can
            // breathe full-width — the container above renders us bare
            // with no outer padding, and the driver called out that the
            // old s5 (20pt) gutter left the screen looking thin.
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .task {
            store.setRole(fromAuth: session.user?.role)
            await store.bootstrap()
            store.hydrateSaved()
        }
        .onDisappear { store.teardown() }
        // In-app article reader — renders the story inside EusoTrip's
        // chrome (back chevron + source pill + WKWebView body) so the
        // driver never loses the nav bar to Safari. Full screen cover
        // so it reads like a native push, not a modal card.
        .fullScreenCover(item: $readerArticle) { article in
            NewsArticleReader(article: article)
                .environment(\.palette, palette)
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textTertiary)
            TextField("Search trucking news", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .foregroundStyle(palette.textPrimary)
            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: Morning brief

    private func morningBriefCard(_ summary: String) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(LinearGradient.diagonal)
                        .font(.system(size: 14, weight: .semibold))
                    Text("Morning brief · \(roleDisplay)")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(summary)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var roleDisplay: String {
        switch store.role {
        case .driver:            return "Driver"
        case .dispatcher:        return "Dispatch"
        case .broker:            return "Broker"
        case .shipper:           return "Shipper"
        case .catalyst:          return "Catalyst"
        case .terminalManager:   return "Terminal"
        case .vesselShipper:     return "Vessel Shipper"
        case .vesselOperator:    return "Vessel Ops"
        case .railShipper:       return "Rail Shipper"
        case .railCatalyst:      return "Rail Catalyst"
        case .complianceOfficer: return "Compliance"
        case .safetyManager:     return "Safety"
        case .admin:             return "Admin"
        }
    }

    // MARK: Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                // "Saved" chip lives at the head of the row so the
                // driver always knows where their bookmarks land. This
                // is the surface that answers "where does the save
                // ribbon save to" — tap here to see every article the
                // driver has saved, pulled from the server's
                // `news.getSavedArticles` list.
                savedChip
                ForEach(chipOrder, id: \.self) { cat in
                    chip(cat)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var savedChip: some View {
        let active = store.showingSavedOnly
        let chipStyle: AnyShapeStyle = active
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.bgCardSoft)
        return Button {
            store.setShowingSavedOnly(!store.showingSavedOnly)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("Saved")
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                if !store.savedIds.isEmpty {
                    Text("\(store.savedIds.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(active
                                           ? AnyShapeStyle(Color.white.opacity(0.25))
                                           : AnyShapeStyle(palette.bgPage))
                        )
                }
            }
            .foregroundStyle(active ? Color.white : palette.textPrimary)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 8)
            .background(chipStyle, in: Capsule(style: .continuous))
            .overlay(
                Capsule().strokeBorder(
                    active ? Color.clear : palette.borderFaint,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private func chip(_ cat: NewsCategory) -> some View {
        let active = store.selectedCategory == cat
        let chipStyle: AnyShapeStyle = active
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.bgCardSoft)
        return Button {
            store.selectedCategory = cat
        } label: {
            Text(cat.displayName)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.white : palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(chipStyle, in: Capsule(style: .continuous))
                .overlay(
                    Capsule().strokeBorder(
                        active ? Color.clear : palette.borderFaint,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Articles

    @ViewBuilder
    private var articleList: some View {
        let articles = store.displayArticles
        if articles.isEmpty {
            emptyState
        } else {
            if let hero = articles.first {
                NewsHeroCard(
                    article: hero,
                    isSaved: store.savedIds.contains(hero.id),
                    onTap: { openArticle(hero) },
                    onToggleSave: { store.toggleSaved(hero) }
                )
            }
            ForEach(Array(articles.dropFirst())) { article in
                NewsRowCard(
                    article: article,
                    isSaved: store.savedIds.contains(article.id),
                    onTap: { openArticle(article) },
                    onToggleSave: { store.toggleSaved(article) }
                )
            }
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private var emptyState: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("No articles")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("Nothing fresh in this category yet — try another chip or pull to refresh.")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func errorState(_ msg: String) -> some View {
        // Two distinct shapes here: a "sign in" nudge when the feed is
        // gated on authentication, and a generic retryable error for
        // everything else (transient network, tRPC validation, 5xx, …).
        // We differentiate by sniffing the message because
        // EusoTripAPIError.unauthenticated's errorDescription flattens
        // into a string before we get here.
        let isAuthGap = msg.localizedCaseInsensitiveContains("authentication")
            || msg.localizedCaseInsensitiveContains("login")
            || msg.localizedCaseInsensitiveContains("please login")
            || msg.localizedCaseInsensitiveContains("unauthorized")
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: isAuthGap
                          ? "person.crop.circle.badge.exclamationmark"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(isAuthGap ? Brand.magenta : Brand.warning)
                    Text(isAuthGap ? "Sign in to see the news feed" : "Can't reach news feed")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                Text(isAuthGap
                     ? "Your session has expired. Sign back in and we'll bring the feed back."
                     : msg)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                CTAButton(title: isAuthGap ? "Try again" : "Retry") {
                    Task { await store.refresh() }
                }
            }
        }
    }

    /// Present the article inside EusoTrip's own reader chrome so the
    /// driver never jumps out to Safari. The reader is a full-screen
    /// cover (see `.fullScreenCover` on the root) with a back chevron
    /// that dismisses straight back to the Driver Intel feed.
    private func openArticle(_ article: NewsArticle) {
        readerArticle = article
    }
}

// MARK: - NewsHeroCard

/// Lead article card — full-width hero image + overlay pill.
struct NewsHeroCard: View {
    @Environment(\.palette) var palette
    let article: NewsArticle
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                imageHeader
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: Space.s2) {
                        sourcePill
                        Text(relativeTime)
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 0)
                        bookmarkButton
                    }
                    Text(article.title)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !article.summary.isEmpty {
                        Text(article.summary)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var imageHeader: some View {
        ZStack {
            NewsImageView(url: article.imageURL, category: article.typedCategory, articleURL: article.articleURL)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 180)

            VStack {
                HStack {
                    CategoryTag(category: article.typedCategory)
                    Spacer()
                }
                Spacer()
            }
            .padding(Space.s3)
            .frame(height: 180)
        }
    }

    private var sourcePill: some View {
        Text(article.source)
            .font(EType.micro).tracking(0.4)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 4)
            .background(palette.bgCardSoft)
            .clipShape(Capsule(style: .continuous))
    }

    private var bookmarkButton: some View {
        Button(action: onToggleSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSaved
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textTertiary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Unsave article" : "Save article")
    }

    private var relativeTime: String {
        NewsTimeFormatter.shared.relative(from: article.publishDate)
    }
}

// MARK: - NewsRowCard

/// Secondary article card — 108x108 image on the left, 2-line title + meta.
struct NewsRowCard: View {
    @Environment(\.palette) var palette
    let article: NewsArticle
    let isSaved: Bool
    let onTap: () -> Void
    let onToggleSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Space.s3) {
                NewsImageView(url: article.imageURL, category: article.typedCategory, articleURL: article.articleURL)
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Space.s2) {
                        CategoryTag(category: article.typedCategory, compact: true)
                        Spacer(minLength: 0)
                        Button(action: onToggleSave) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSaved
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.textTertiary))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(article.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack(spacing: Space.s2) {
                        Text(article.source)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                        Circle().fill(palette.textTertiary).frame(width: 3, height: 3)
                        Text(NewsTimeFormatter.shared.relative(from: article.publishDate))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NewsImageView

/// AsyncImage wrapper with two-stage resolution:
///   1. Primary: the server-provided `url` (RSS scrape).
///   2. Fallback: when the primary is nil OR AsyncImage fails,
///      fetch the article's OG image via `NewsOGImageCache`. This
///      is the "click in and the image is there" case — the
///      article's `<meta property="og:image">` is always present
///      in the full HTML head even when the RSS didn't carry it.
///   3. Last resort: category-keyed gradient placeholder.
///
/// Callers should pass `articleURL` whenever available so the
/// fallback can kick in. Passing nil preserves the old behavior.
struct NewsImageView: View {
    let url: URL?
    let category: NewsCategory
    var articleURL: URL? = nil

    @StateObject private var og = NewsOGImageCache.shared

    /// The URL we'll actually ask AsyncImage to load. Prefers the
    /// server-scraped imageUrl; falls through to the cached / in-
    /// flight OG image when `articleURL` is set.
    private var effectiveURL: URL? {
        if let url { return url }
        guard let articleURL else { return nil }
        return og.image(for: articleURL)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let eff = effectiveURL {
                    AsyncImage(url: eff) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            // Primary failed — try the OG fallback
                            // before giving up. If the primary WAS
                            // the OG fallback, the gradient renders.
                            if url != nil, let articleURL,
                               let fallback = og.image(for: articleURL),
                               fallback != url {
                                AsyncImage(url: fallback) { f in
                                    if let img = f.image {
                                        img.resizable().scaledToFill()
                                            .frame(width: geo.size.width, height: geo.size.height)
                                            .clipped()
                                    } else {
                                        placeholder
                                    }
                                }
                            } else {
                                placeholder
                            }
                        case .empty:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: placeholderColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.glyph)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var placeholderColors: [Color] {
        switch category {
        case .trucking, .logistics, .supply_chain:
            return [Color(red: 0.08, green: 0.45, blue: 1.00),
                    Color(red: 0.30, green: 0.55, blue: 0.95)]
        case .hazmat, .chemical:
            return [Color(red: 1.00, green: 0.55, blue: 0.10),
                    Color(red: 1.00, green: 0.20, blue: 0.30)]
        case .oil_gas, .energy:
            return [Color(red: 0.15, green: 0.25, blue: 0.45),
                    Color(red: 0.50, green: 0.30, blue: 0.10)]
        case .government, .regulatory, .safety:
            return [Color(red: 0.13, green: 0.60, blue: 0.65),
                    Color(red: 0.35, green: 0.40, blue: 0.85)]
        case .marine, .bulk, .refrigerated, .terminal:
            return [Color(red: 0.08, green: 0.50, blue: 0.65),
                    Color(red: 0.05, green: 0.25, blue: 0.45)]
        case .technology:
            return [Color(red: 0.55, green: 0.20, blue: 0.85),
                    Color(red: 0.10, green: 0.50, blue: 0.95)]
        default:
            return [Color(red: 0.08, green: 0.45, blue: 1.00),
                    Color(red: 0.75, green: 0.00, blue: 1.00)]
        }
    }
}

// MARK: - CategoryTag

struct CategoryTag: View {
    let category: NewsCategory
    var compact: Bool = false
    @Environment(\.palette) var palette

    var body: some View {
        Text(category.displayName.uppercased())
            .font(.system(size: compact ? 9 : 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 3 : 4)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule(style: .continuous))
    }
}

// MARK: - NewsCategory · glyph

extension NewsCategory {
    var glyph: String {
        switch self {
        case .all:          return "newspaper"
        case .trucking:     return "truck.box.fill"
        case .government:   return "building.columns.fill"
        case .regulatory:   return "shield.fill"
        case .hazmat:       return "flame.fill"
        case .oil_gas:      return "drop.fill"
        case .chemical:     return "testtube.2"
        case .bulk:         return "shippingbox.fill"
        case .refrigerated: return "snowflake"
        case .logistics:    return "arrow.triangle.swap"
        case .supply_chain: return "link"
        case .marine:       return "ferry.fill"
        case .energy:       return "bolt.fill"
        case .equipment:    return "wrench.and.screwdriver.fill"
        case .safety:       return "cross.case.fill"
        case .technology:   return "cpu"
        case .market:       return "chart.line.uptrend.xyaxis"
        case .terminal:     return "dock.rectangle"
        case .other:        return "newspaper"
        }
    }
}

// MARK: - NewsTimeFormatter

/// Shared RelativeDateTimeFormatter — "2 h ago", "Yesterday", etc.
final class NewsTimeFormatter: @unchecked Sendable {
    static let shared = NewsTimeFormatter()
    private let rel: RelativeDateTimeFormatter

    private init() {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        self.rel = f
    }

    func relative(from date: Date) -> String {
        guard date > Date(timeIntervalSince1970: 1) else { return "" }
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - NewsCarouselWidget

/// Home-dashboard rotating headline widget. Cycles through up-to-15
/// articles every `intervalSeconds` seconds. Renders the scraped image
/// plus a 2-line title + source pill.
///
/// The widget is driven by its OWN `NewsFeedStore` so it stays fresh
/// even when the user hasn't opened Me → News. `.task` bootstraps the
/// feed and starts the 15 s cache poll; the Timer handles rotation.
struct NewsCarouselWidget: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = NewsFeedStore()

    /// Rotation cadence. 10 s per user request ("switches between 15 of
    /// them every 10 seconds"). The timer is suppressed while the driver
    /// is actively dragging the pager so the swipe gesture doesn't fight
    /// the auto-advance.
    var intervalSeconds: TimeInterval = 10

    @State private var index: Int = 0
    @State private var rotationTimer: Timer?
    @State private var showFullSheet: Bool = false
    /// Article pushed into the in-app reader when a carousel card is
    /// tapped. Previously the tap handed off to `UIApplication.shared.open`
    /// which kicked the driver into Safari. Per user direction
    /// (2026-04-21) the reader is now a full-screen cover rendered inside
    /// EusoTrip's shell with a back chevron.
    @State private var readerArticle: NewsArticle?
    /// Paused while the driver has their finger on the pager so the auto
    /// rotation doesn't yank the card out from under a half-finished
    /// swipe.
    @State private var userDragging: Bool = false

    private var slice: [NewsArticle] { store.carouselSlice(15) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            header
            card
        }
        .task {
            store.setRole(fromAuth: session.user?.role)
            await store.bootstrap()
        }
        .onDisappear {
            rotationTimer?.invalidate()
            rotationTimer = nil
            store.teardown()
        }
        .sheet(isPresented: $showFullSheet) {
            MeDetailContainer(route: .news)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        .fullScreenCover(item: $readerArticle) { article in
            NewsArticleReader(article: article)
                .environment(\.palette, palette)
        }
    }

    private var header: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            // Role-aware eyebrow — "DRIVER INTEL" / "SHIPPER INTEL" /
            // "BROKER INTEL" / etc. Same widget powers every role's
            // home dashboard; the server prioritizes the morning brief
            // by `store.role`, so the label matches the slice content.
            Text("\(roleDisplay) Intel".uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Button {
                showFullSheet = true
            } label: {
                Text("See all")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
        }
    }

    /// "Driver" / "Shipper" / "Broker" / etc — derived from the store's
    /// active role enum. Used to title the carousel header so the
    /// widget reads correctly when reused across roles.
    private var roleDisplay: String {
        switch store.role {
        case .driver:            return "Driver"
        case .dispatcher:        return "Dispatch"
        case .broker:            return "Broker"
        case .shipper:           return "Shipper"
        case .catalyst:          return "Catalyst"
        case .terminalManager:   return "Terminal"
        case .vesselShipper:     return "Vessel Shipper"
        case .vesselOperator:    return "Vessel Ops"
        case .railShipper:       return "Rail Shipper"
        case .railCatalyst:      return "Rail Catalyst"
        case .complianceOfficer: return "Compliance"
        case .safetyManager:     return "Safety"
        case .admin:             return "Admin"
        }
    }

    @ViewBuilder
    private var card: some View {
        if slice.isEmpty {
            placeholderCard
        } else {
            // Swipe-to-advance pager. `.tabViewStyle(.page)` turns a
            // TabView into a horizontal carousel with native UIKit-backed
            // swipe gestures and a momentum page-snap — much better than
            // trying to build drag physics from a DragGesture. The dots
            // indicator is overlaid on top of the pager (the built-in
            // dots are hidden via `.indexViewStyle(.never)`) so we can
            // position + style them ourselves.
            ZStack(alignment: .bottomTrailing) {
                TabView(selection: $index) {
                    ForEach(Array(slice.enumerated()), id: \.offset) { pair in
                        let article = pair.element
                        Button {
                            openArticle(article)
                        } label: {
                            articleCardSurface(article)
                        }
                        .buttonStyle(.plain)
                        .tag(pair.offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

                dotsIndicator
                    .padding(Space.s3)
                    .allowsHitTesting(false)
            }
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.25)
                    .allowsHitTesting(false)
            )
            .onAppear { startRotation() }
            .onChange(of: index) { _, _ in
                // When the driver manually swipes, reset the auto-rotate
                // clock so it doesn't instantly advance on top of the
                // user's gesture.
                startRotation()
            }
        }
    }

    /// Rendered inside each TabView page. Extracted out of `card` so the
    /// pager and the tap target share one consistent visual.
    private func articleCardSurface(_ article: NewsArticle) -> some View {
        ZStack(alignment: .bottomLeading) {
            NewsImageView(url: article.imageURL, category: article.typedCategory, articleURL: article.articleURL)
                .frame(height: 160)
                .frame(maxWidth: .infinity)

            LinearGradient(
                colors: [.black.opacity(0.75), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s2) {
                    CategoryTag(category: article.typedCategory, compact: true)
                    Text(article.source)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule(style: .continuous))
                }
                Text(article.title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s3)
            // Leave room at the bottom-right for the dots overlay.
            .padding(.trailing, 44)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var dotsIndicator: some View {
        let count = min(slice.count, 6)
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == (index % max(count, 1)) ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var placeholderCard: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 160)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .overlay(
                ProgressView().tint(palette.textTertiary)
            )
    }

    private func startRotation() {
        rotationTimer?.invalidate()
        guard slice.count > 1 else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { _ in
            Task { @MainActor in
                let n = slice.count
                guard n > 1 else { return }
                // Animate the page flip so the auto-advance reads like
                // the same gesture the driver can swipe manually.
                withAnimation(.easeInOut(duration: 0.35)) {
                    index = (index + 1) % n
                }
            }
        }
    }

    /// Tapping a headline pushes the in-app reader sheet. The reader
    /// loads the source URL in a contained WKWebView so the driver stays
    /// inside EusoTrip — no more Safari hand-off.
    private func openArticle(_ article: NewsArticle) {
        readerArticle = article
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
