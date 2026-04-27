//
//  NewsFeedStore.swift
//  EusoTrip — Backing store for the Driver Intel News surface (Me → News)
//  and the rotating headline widget on DriverHome.
//
//  Why this exists:
//  -----------------
//  The web platform's news fan-out (`frontend/server/routers/news.ts`)
//  hits ~100 tier-1 RSS feeds across 11 categories, caches the unified
//  list, and exposes it as tRPC procedures. The server also does the
//  role-based prioritisation (morning brief). On iOS we need one
//  ObservableObject that:
//
//    1. Hydrates the full feed once (via `news.getArticles`)
//    2. Polls `news.cacheStatus` every 15 s (cheap ~1 KB payload)
//       and refetches only when the `generation` counter advances
//    3. Holds the current role (driver / dispatch / broker / …) and
//       a filtered view keyed by category chip
//    4. Exposes a 15-article slice for the home carousel widget, kept
//       in sync with the current filter
//    5. Provides save / unsave bookmarks
//
//  This lets both the full Me → News screen AND the DriverHome widget
//  bind to the same store — one fetch powers both surfaces.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class NewsFeedStore: ObservableObject {

    // MARK: Published state

    /// All articles the server returned on the most recent fetch (before
    /// client-side filtering). Newest-first.
    @Published private(set) var articles: [NewsArticle] = []

    /// The current server cache generation. When `cacheStatus()` reports
    /// a higher number we refetch.
    @Published private(set) var generation: Int = 0

    /// Total articles the server claims to hold for the current filter.
    @Published private(set) var totalCount: Int = 0

    /// The role-personalised morning-brief lead copy (server-rendered).
    @Published private(set) var morningSummary: String?

    /// Current user role. Defaults to `.driver` until `setRole(...)` is
    /// called from the signed-in session.
    @Published var role: NewsFeedRole = .driver

    /// Category chip filter. `.all` = no filter.
    @Published var selectedCategory: NewsCategory = .all

    /// Free-text search query. Passed straight to the server so the
    /// full corpus is searched, not just the already-fetched window.
    @Published var searchQuery: String = ""

    /// Set of saved article IDs (bookmarks). Also drives the bookmark
    /// icon in the UI.
    @Published private(set) var savedIds: Set<String> = []

    /// When `true`, `displayArticles` narrows the feed to the server's
    /// saved-articles list (`news.getSavedArticles`). The driver tapped
    /// the "Saved" chip — that's the surface where their bookmarks
    /// live. When `false`, the feed behaves normally.
    @Published var showingSavedOnly: Bool = false

    /// Server-returned saved articles. Hydrated lazily when the
    /// "Saved" chip flips on so the `displayArticles` view has real
    /// server rows (full title + image + summary), not just bare ids.
    @Published private(set) var savedArticles: [NewsArticle] = []

    /// Loading flag for the first-run hydration + pull-to-refresh.
    @Published private(set) var isLoading: Bool = false

    /// Last non-fatal error — cleared on the next successful fetch.
    @Published var lastError: String?

    // MARK: Private

    private let api: EusoTripAPI
    private var pollTask: Task<Void, Never>?
    private var bag = Set<AnyCancellable>()

    /// Refetch debouncer so filter chip flicks don't flood the backend.
    private var refetchTask: Task<Void, Never>?

    // MARK: Init

    init(api: EusoTripAPI = .shared) {
        self.api = api

        // Refetch when the filter changes (debounced).
        $selectedCategory
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.scheduleRefetch() }
            .store(in: &bag)

        $searchQuery
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRefetch() }
            .store(in: &bag)
    }

    // MARK: Role wiring

    /// Map the backend role string (from the signed-in `AuthUser`) to the
    /// NewsFeedRole enum and refetch the role-weighted feed.
    func setRole(fromAuth raw: String?) {
        let key = (raw ?? "DRIVER").uppercased()
        let mapped = NewsFeedRole(rawValue: key) ?? .driver
        guard mapped != self.role else { return }
        self.role = mapped
        scheduleRefetch()
    }

    // MARK: Derived surfaces

    /// First N articles post-filter, for the home-dashboard carousel
    /// widget. The widget rotates through this slice every 10 seconds.
    /// Only articles with a real image URL are surfaced so the
    /// carousel never shows a placeholder card on the home screen.
    func carouselSlice(_ n: Int = 15) -> [NewsArticle] {
        let withImage = articles.filter { ($0.imageUrl ?? "").isEmpty == false }
        return Array(withImage.prefix(n))
    }

    /// Articles the full Me → News screen renders (already server-filtered,
    /// so no additional client filtering is needed here — the list is
    /// returned as-is for the View to chunk into hero + tiles).
    var displayArticles: [NewsArticle] {
        showingSavedOnly ? savedArticles : articles
    }

    /// Toggle the saved-only view. When flipping ON we hydrate the
    /// server's canonical saved list (so the feed shows the exact
    /// articles the driver bookmarked, with their server metadata —
    /// not just the ids that happen to be cached locally).
    func setShowingSavedOnly(_ on: Bool) {
        showingSavedOnly = on
        if on {
            Task {
                if let saved = try? await api.news.getSavedArticles() {
                    self.savedArticles = saved
                    // Keep savedIds in sync — hydrateSaved wires the
                    // bookmark icons while this view is active.
                    self.savedIds = Set(saved.map(\.id))
                }
            }
        }
    }

    // MARK: Lifecycle

    /// Fetch the initial page + start the 15 s cacheStatus poll. Safe to
    /// call more than once — the poll task is idempotent.
    func bootstrap() async {
        await refresh()
        startPollIfNeeded()
    }

    /// Cancel the poll task. Call from `onDisappear` of the containing
    /// screen if you don't want the background chatter.
    func teardown() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Fetching

    /// Full refresh — fetches the filtered page + role-weighted morning
    /// brief. Updates generation / totalCount.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Kick both requests in parallel. Morning brief is tolerant
            // of failure — if it 404s on an older deploy we still show
            // the article list.
            async let articlesTask = api.news.getArticles(
                category: categoryQueryValue,
                search: searchQuery.isEmpty ? nil : searchQuery,
                limit: 80,
                offset: 0
            )
            async let briefTask = fetchMorningBriefSafely()

            let page = try await articlesTask
            let brief = await briefTask

            self.articles = page.articles
            self.totalCount = page.total
            self.generation = page.generation ?? self.generation
            self.morningSummary = brief?.summary
            self.lastError = nil
        } catch {
            self.lastError = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Cheap status poll — if the server's generation counter is higher
    /// than ours, refetch. Server guarantees generation monotonicity.
    private func pollCacheStatus() async {
        do {
            let status = try await api.news.cacheStatus()
            if status.generation > self.generation {
                await refresh()
            }
        } catch {
            // Silent — polling is best-effort.
        }
    }

    private func fetchMorningBriefSafely() async -> NewsMorningBrief? {
        do {
            return try await api.news.getMorningBrief(role: role.rawValue)
        } catch {
            return nil
        }
    }

    // MARK: Bookmarks

    func toggleSaved(_ article: NewsArticle) {
        let wasSaved = savedIds.contains(article.id)
        // Optimistic — flip the local state first so the icon responds
        // immediately. Reconcile against the server response.
        if wasSaved {
            savedIds.remove(article.id)
        } else {
            savedIds.insert(article.id)
        }
        Task { [wasSaved] in
            do {
                if wasSaved {
                    _ = try await api.news.unsaveArticle(id: article.id)
                } else {
                    _ = try await api.news.saveArticle(id: article.id)
                }
            } catch {
                // Rollback on failure.
                if wasSaved {
                    self.savedIds.insert(article.id)
                } else {
                    self.savedIds.remove(article.id)
                }
                self.lastError = (error as? EusoTripAPIError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// Pull the saved article list so the heart icons reflect the truth
    /// on screen first-load. Best-effort.
    func hydrateSaved() {
        Task {
            if let saved = try? await api.news.getSavedArticles() {
                self.savedIds = Set(saved.map(\.id))
            }
        }
    }

    // MARK: Helpers

    /// Server expects the category value as the raw enum string except
    /// `.all`, which it treats as "no filter" (omit the field).
    private var categoryQueryValue: String? {
        switch selectedCategory {
        case .all:
            // When the user hasn't picked a category, fall back to the
            // role's preferred buckets as a server-side hint via search
            // wildcard — we still send `nil` here so the server's own
            // role-weighted ranking takes over, mirroring the web.
            return nil
        default:
            return selectedCategory.rawValue
        }
    }

    private func scheduleRefetch() {
        refetchTask?.cancel()
        refetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000) // 120 ms coalesce
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func startPollIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // 15 s — cheap payload, matches web's SWR cadence.
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.pollCacheStatus()
            }
        }
    }
}
