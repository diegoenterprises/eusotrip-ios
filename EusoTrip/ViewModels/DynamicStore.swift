//
//  DynamicStore.swift
//  EusoTrip
//
//  Canonical store contract every live-data view-model adopts. Replaces
//  the 30+ seeded arrays across the iOS surface with a single pattern:
//
//      protocol DynamicStore: AnyObject {
//          var isLoading: Bool { get }
//          var lastError: Error? { get }
//          func refresh() async
//      }
//
//  Plus a generic `RemoteState<T>` enum that views switch over to pick
//  the right presentation branch — `.loading` → spinner,
//  `.empty` → `EusoEmptyState`, `.loaded(T)` → list, `.error` → banner.
//
//  Pattern mirrors `HOSLiveStore`, `NewsFeedStore`, and `HotZonesStore`
//  that were already built by hand; consolidating them under this
//  protocol means new surfaces (WalletStore, LoadBoardStore, etc.) get
//  the same error/empty/loading semantics for free.
//

import Foundation

// MARK: - Store contract

/// Every live-data view-model in the app conforms to this so consumers
/// have a uniform way to wire loading and error states. `@MainActor` at
/// the protocol level so conformers + consumers agree on isolation:
/// UI reads `isLoading` / `lastError` on the main actor; `refresh()`
/// awaits inside a Task scoped to the view's lifecycle.
@MainActor
protocol DynamicStore: AnyObject {
    var isLoading: Bool { get }
    var lastError: Error? { get }
    func refresh() async
}

// MARK: - RemoteState

/// Four-case state a view switches over. `.empty` is distinct from
/// `.loaded([])` so the UI can show a branded EusoEmptyState only when
/// the server confirmed an empty set, not mid-load.
enum RemoteState<Value> {
    case loading
    case loaded(Value)
    case empty
    case error(Error)

    /// True when the state has settled to a result (loaded / empty / error).
    /// Used by callers that want to wait for the first non-loading tick.
    var isSettled: Bool {
        switch self {
        case .loading:                       return false
        case .loaded, .empty, .error:        return true
        }
    }

    /// Unwrap the loaded value if present, otherwise nil.
    var value: Value? {
        if case .loaded(let v) = self { return v } else { return nil }
    }

    /// Unwrap the error if present.
    var error: Error? {
        if case .error(let e) = self { return e } else { return nil }
    }
}

// MARK: - Collection helper

extension RemoteState where Value: Collection {
    /// Convenience to fold a `[T]` fetch result directly into the right
    /// terminal state. Empty arrays become `.empty` instead of
    /// `.loaded([])` so views pick the EusoEmptyState branch without an
    /// extra `items.isEmpty` check.
    static func fromCollection(_ collection: Value) -> RemoteState<Value> {
        collection.isEmpty ? .empty : .loaded(collection)
    }
}

// MARK: - BaseDynamicStore

/// Minimal base class for stores that fetch `[T]` from a single tRPC
/// procedure. Subclasses override `fetch()` with the live API call —
/// the class handles isLoading/lastError/RemoteState transitions.
///
/// Usage:
///
///     @MainActor
///     final class LoadBoardStore: BaseDynamicStore<[LoadSummary]> {
///         override func fetch() async throws -> [LoadSummary] {
///             try await EusoTripAPI.shared.loads.search(status: "available")
///         }
///     }
///
///     struct BoardView: View {
///         @StateObject private var store = LoadBoardStore()
///         var body: some View {
///             switch store.state {
///             case .loading:    ProgressView()
///             case .empty:      EusoEmptyState(systemImage: "truck.box", title: "No loads available")
///             case .loaded(let loads): ForEach(loads) { … }
///             case .error(let e): InlineErrorBanner(error: e)
///             }
///         }
///         .task { await store.refresh() }
///     }
///
@MainActor
class BaseDynamicStore<Value>: ObservableObject, DynamicStore {
    // NOTE: These are `internal(set)` (not `private(set)`) because
    // specialised subclasses in other files (e.g. `TheHaulMissionsStore`
    // in `LiveDataStores.swift`) need to nudge `state` optimistically or
    // record a `lastError` during a side-effectful mutation (start /
    // claim a mission) without going through a full `refresh()`. The
    // module-internal setter keeps the write surface inside the iOS
    // target while unlocking the subclass-local edits.
    @Published var state: RemoteState<Value> = .loading
    @Published var isLoading: Bool = false
    @Published var lastError: Error? = nil

    /// Subclasses override this with their tRPC call. The default
    /// implementation traps — subclasses MUST override.
    func fetch() async throws -> Value {
        fatalError("BaseDynamicStore subclasses must override fetch()")
    }

    /// Fold a fetched value into the right RemoteState case. Subclasses
    /// can override for custom emptiness semantics (e.g. a balance of
    /// zero isn't "empty" — you still want to render $0.00).
    func foldState(_ value: Value) -> RemoteState<Value> {
        .loaded(value)
    }

    /// True only on the *first* fetch (state still in its `.loading`
    /// initial value). Subsequent pull-to-refresh calls don't reset
    /// `state` to `.loading` — see `refresh()` below — so this stays
    /// `false` after the first network round-trip lands. UI sites use
    /// this to hide skeleton chrome (e.g. count pills, badge dots) on
    /// the first paint and reveal the real value once the server
    /// confirms it.
    var isInitialLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    /// Canonical refresh entry point. Switches the store to `.loading`,
    /// invokes `fetch()`, then settles on `.loaded / .empty / .error`.
    func refresh() async {
        isLoading = true
        lastError = nil
        // Only reset to .loading on the first call; subsequent refreshes
        // keep the prior loaded data on-screen until the new one lands
        // (no flashing blank state on pull-to-refresh).
        if case .loading = state {
            state = .loading
        }
        do {
            let value = try await fetch()
            state = foldState(value)
        } catch {
            // SwiftUI's `.task` modifier cancels its task when view
            // identity churns (sheet present/dismiss, parent rebuild,
            // tab swap mid-fetch). URLSession surfaces that as
            // `URLError.cancelled` whose `.localizedDescription` is the
            // bare word "cancelled" — which used to leak into every
            // section banner across Wallet / Safety Coach / Morning Brief
            // as "Can't reach the server · cancelled". A cancellation is
            // by definition NOT a server failure: the wrapping view will
            // re-fire `refresh()` on its next appearance. Keep the prior
            // state (loaded data, loading, or empty) and exit quietly.
            if Self.isTransientCancellation(error) {
                isLoading = false
                return
            }
            lastError = error
            state = .error(error)
        }
        isLoading = false
    }

    /// True when an error represents a Task / URLSession cancellation
    /// rather than a real server / network failure. The store treats
    /// these as no-ops so the UI doesn't flash a misleading "cancelled"
    /// banner during normal SwiftUI view-identity churn.
    static func isTransientCancellation(_ error: Error) -> Bool {
        DynamicStoreUtil.isTransientCancellation(error)
    }
}

// MARK: - Cancellation helper (shared)

/// Free helper so the dozens of bespoke stores in `LiveDataStores.swift`
/// (and ad-hoc views like `DriverHomeGlances`, `DriverNavController`)
/// can apply the same cancellation-vs-real-error distinction without
/// inheriting from `BaseDynamicStore`. Sites that catch errors should
/// call:
///
///     } catch {
///         if DynamicStoreUtil.isTransientCancellation(error) { return }
///         lastError = error
///         …
///     }
///
/// before mutating `lastError` / `state` / a UI-visible error string.
enum DynamicStoreUtil {
    static func isTransientCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }
}

// MARK: - Collection specialization

/// Convenience specialization for the common `[T]` case where empty array
/// maps to `.empty`. Every list-style store (LoadBoard, Transactions,
/// Missions, Badges, etc.) inherits from this.
@MainActor
class BaseDynamicListStore<Element>: BaseDynamicStore<[Element]> {
    override func foldState(_ value: [Element]) -> RemoteState<[Element]> {
        value.isEmpty ? .empty : .loaded(value)
    }

    /// Convenience — unwrap the loaded array or return an empty slice so
    /// views that want to just `ForEach` over whatever the store has can
    /// do so without a switch.
    var items: [Element] {
        state.value ?? []
    }
}
