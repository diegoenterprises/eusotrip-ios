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
import SwiftUI

// MARK: - App-wide refresh and freshness contract

/// Why a visible surface is being refreshed. The distinction matters in
/// production: repeated native refresh-control callbacks are de-duplicated,
/// while foreground refreshes are driven by an inactivity age rather than
/// every transient Control Center / notification interruption.
enum EusoRefreshReason: String, Sendable {
    case userPull
    case staleForeground
    case domainInvalidation
}

/// Typed invalidation prevents broad events (wallet, ESANG, weather, etc.)
/// from waking every initialized store in the process. A domain event may
/// only invoke matching handlers on the currently visible surface.
enum EusoRefreshDomain: String, Hashable, Sendable {
    case general
    case loads
    case messages
    case weather
    case wallet
    case esang
}

/// Immutable, MainActor-isolated callback that can be safely snapshotted into
/// a task group. Captured SwiftUI state is never read off the main actor.
struct EusoRefreshOperation: @unchecked Sendable {
    private let handler: @MainActor () async -> Void

    init(_ handler: @escaping @MainActor () async -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction() async {
        await handler()
    }
}

/// The coordinator retains this box instead of a one-time closure snapshot.
/// SwiftUI updates the operation as immutable route inputs change, so a later
/// pull cannot call a loader with an old load/company/role identifier.
@MainActor
private final class EusoRefreshHandlerBox {
    var operation: EusoRefreshOperation

    init(operation: EusoRefreshOperation) {
        self.operation = operation
    }

    func update(operation: EusoRefreshOperation) {
        self.operation = operation
    }
}

/// Session-wide freshness coordinator shared by all 24 authenticated roles.
/// It does not fetch domain data itself; visible surfaces and their real
/// DynamicStore / `.task` loaders own that work. The coordinator supplies
/// targeting, inactivity policy, and duplicate suppression.
@MainActor
final class EusoRefreshCoordinator {
    static let shared = EusoRefreshCoordinator()

    private struct InFlightRefresh {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct HandlerEntry {
        let box: EusoRefreshHandlerBox
        let domains: Set<EusoRefreshDomain>
    }

    /// A short app switch should not churn every live API. Once the app has
    /// been away for one minute, operational state is old enough that the
    /// currently visible screen must self-heal immediately on return.
    static let foregroundStaleAfter: TimeInterval = 60

    private var inactiveSince: Date?
    private var lastPullBySurface: [String: Date] = [:]
    private var visibleSurfaces: [(token: UUID, surfaceID: String)] = []
    private var handlersBySurface: [String: [UUID: HandlerEntry]] = [:]
    private var inFlightBySurface: [String: InFlightRefresh] = [:]

    private init() {}

    func appBecameInactive(at date: Date = Date()) {
        if inactiveSince == nil { inactiveSince = date }
    }

    /// Returns true exactly once for a stale inactive interval. Keeping this
    /// calculation here makes scene-lifecycle behavior deterministic and easy
    /// to exercise without coupling domain stores to `ScenePhase`.
    func consumeStaleActivation(at date: Date = Date()) -> Bool {
        guard let inactiveSince else { return false }
        self.inactiveSince = nil
        return date.timeIntervalSince(inactiveSince) >= Self.foregroundStaleAfter
    }

    func surfaceDidAppear(token: UUID, surfaceID: String) {
        visibleSurfaces.removeAll { $0.token == token }
        visibleSurfaces.append((token, surfaceID))
    }

    func surfaceDidChange(token: UUID, surfaceID: String) {
        surfaceDidAppear(token: token, surfaceID: surfaceID)
    }

    func surfaceDidDisappear(token: UUID) {
        visibleSurfaces.removeAll { $0.token == token }
    }

    /// Screen-owned callbacks register before the surface can be interacted
    /// with. A scoped pull snapshots only this surface's callbacks, avoiding
    /// unrelated initialized stores and removing any scheduler-dependent
    /// notification-registration window.
    fileprivate func registerHandler(
        token: UUID,
        surfaceID: String,
        box: EusoRefreshHandlerBox,
        domains: Set<EusoRefreshDomain> = [.general]
    ) {
        let normalizedID = surfaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return }
        handlersBySurface[normalizedID, default: [:]][token] = HandlerEntry(
            box: box,
            domains: domains
        )
    }

    func unregisterHandler(token: UUID, surfaceID: String?) {
        if let surfaceID {
            handlersBySurface[surfaceID]?[token] = nil
            if handlersBySurface[surfaceID]?.isEmpty == true {
                handlersBySurface[surfaceID] = nil
            }
            return
        }

        for key in Array(handlersBySurface.keys) {
            handlersBySurface[key]?[token] = nil
            if handlersBySurface[key]?.isEmpty == true {
                handlersBySurface[key] = nil
            }
        }
    }

    func requestRefresh(
        surfaceID: String? = nil,
        reason: EusoRefreshReason,
        at date: Date = Date()
    ) async {
        let normalizedID = surfaceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedTarget = normalizedID?.isEmpty == false ? normalizedID : nil
        let target = requestedTarget ?? visibleSurfaces.last?.surfaceID
        guard let target else { return }

        // Joining precedes gesture-window de-duplication so a second native
        // refresh control remains active until the already-running work ends.
        if let existing = inFlightBySurface[target] {
            await existing.task.value
            return
        }

        // Collapse repeated native refresh-control callbacks while leaving
        // foreground and typed-domain refreshes unthrottled.
        if reason == .userPull {
            if let last = lastPullBySurface[target], date.timeIntervalSince(last) < 0.8 {
                return
            }
            lastPullBySurface[target] = date
        }

        let entries = handlersBySurface[target].map { Array($0.values) } ?? []
        // A surface is refreshable only when a mounted data owner registered
        // its real load action. Static forms and session-only role landings do
        // not substitute auth validation or an unrelated global request.
        let operations = entries.map { $0.box.operation }
        guard !operations.isEmpty else { return }
        let refreshID = UUID()

        // Registration is complete before a user can pull or a mounted surface
        // can return from the background. Snapshotting the MainActor registry is
        // deterministic: no Task.yield window and no unrelated global stores.
        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for operation in operations {
                    group.addTask { await operation() }
                }
            }
        }
        inFlightBySurface[target] = InFlightRefresh(id: refreshID, task: task)
        defer {
            // Token-check cleanup is cancellation-safe: a caller leaving the
            // screen cannot strand an entry that blocks every future pull.
            if inFlightBySurface[target]?.id == refreshID {
                inFlightBySurface[target] = nil
            }
        }
        await task.value
    }

    /// Refresh a typed domain on the current surface only. This replaces the
    /// former BaseDynamicStore-wide broadcast for ESANG/wallet events.
    func invalidateVisibleDomain(_ domain: EusoRefreshDomain) async {
        guard let target = visibleSurfaces.last?.surfaceID else { return }
        if let existing = inFlightBySurface[target] {
            await existing.task.value
            return
        }

        let entries = handlersBySurface[target].map { Array($0.values) } ?? []
        let operations = entries
            .filter { $0.domains.contains(domain) }
            .map { $0.box.operation }
        guard !operations.isEmpty else { return }

        let refreshID = UUID()
        let task = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for operation in operations {
                    group.addTask { await operation() }
                }
            }
        }
        inFlightBySurface[target] = InFlightRefresh(id: refreshID, task: task)
        defer {
            if inFlightBySurface[target]?.id == refreshID {
                inFlightBySurface[target] = nil
            }
        }
        await task.value
    }
}

/// Environment callable used by every refresh boundary. Keeping this as an
/// environment contract (rather than reaching for the singleton from views)
/// lets previews/tests substitute a deterministic handler and lets future
/// surfaces bind an explicit store reload without changing gesture behavior.
struct EusoRefreshAction: Sendable {
    private let handler: @MainActor @Sendable (String?, EusoRefreshReason) async -> Void

    init(_ handler: @escaping @MainActor @Sendable (String?, EusoRefreshReason) async -> Void) {
        self.handler = handler
    }

    @MainActor
    func callAsFunction(_ surfaceID: String?, reason: EusoRefreshReason) async {
        await handler(surfaceID, reason)
    }
}

private struct EusoRefreshActionKey: EnvironmentKey {
    static let defaultValue = EusoRefreshAction { surfaceID, reason in
        await EusoRefreshCoordinator.shared.requestRefresh(
            surfaceID: surfaceID,
            reason: reason
        )
    }
}

extension EnvironmentValues {
    var eusoRefresh: EusoRefreshAction {
        get { self[EusoRefreshActionKey.self] }
        set { self[EusoRefreshActionKey.self] = newValue }
    }
}

private struct EusoRefreshSurfaceIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    fileprivate var eusoRefreshSurfaceID: String? {
        get { self[EusoRefreshSurfaceIDKey.self] }
        set { self[EusoRefreshSurfaceIDKey.self] = newValue }
    }
}

/// Marks one routed subtree as the visible refresh target. This boundary never
/// invents work: a scrollable child opts in with `eusoRefreshable`, while
/// non-scroll data owners register with `eusoRefreshHandler` or
/// `eusoRefreshTask` for stale-foreground/domain refreshes.
private struct EusoRefreshSurfaceModifier: ViewModifier {
    let surfaceID: String

    @State private var surfaceToken = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.eusoRefreshSurfaceID, surfaceID)
            .onAppear {
                EusoRefreshCoordinator.shared.surfaceDidAppear(
                    token: surfaceToken,
                    surfaceID: surfaceID
                )
            }
            .onChange(of: surfaceID) { _, newSurfaceID in
                EusoRefreshCoordinator.shared.surfaceDidChange(
                    token: surfaceToken,
                    surfaceID: newSurfaceID
                )
            }
            .onDisappear {
                EusoRefreshCoordinator.shared.surfaceDidDisappear(token: surfaceToken)
            }
    }
}

/// Explicit hook for screen-owned loaders that predate DynamicStore. The
/// mounted view instance remains untouched; only the screen's own async reload
/// closure runs when its enclosing surface is the refresh target.
private struct EusoRefreshHandlerModifier: ViewModifier {
    @Environment(\.eusoRefreshSurfaceID) private var surfaceID
    @State private var registrationToken = UUID()
    @State private var box: EusoRefreshHandlerBox
    let handler: EusoRefreshOperation
    let domains: Set<EusoRefreshDomain>

    init(handler: EusoRefreshOperation, domains: Set<EusoRefreshDomain>) {
        self.handler = handler
        self.domains = domains
        _box = State(initialValue: EusoRefreshHandlerBox(operation: handler))
    }

    func body(content: Content) -> some View {
        // The box is intentionally non-observable: updating the callable does
        // not redraw or remount anything, it only prevents stale input capture.
        box.update(operation: handler)

        return content
            .onAppear { register(on: surfaceID) }
            .onChange(of: surfaceID) { oldSurfaceID, newSurfaceID in
                EusoRefreshCoordinator.shared.unregisterHandler(
                    token: registrationToken,
                    surfaceID: oldSurfaceID
                )
                register(on: newSurfaceID)
            }
            .onDisappear {
                EusoRefreshCoordinator.shared.unregisterHandler(
                    token: registrationToken,
                    surfaceID: surfaceID
                )
            }
    }

    private func register(on surfaceID: String?) {
        guard let surfaceID else { return }
        EusoRefreshCoordinator.shared.registerHandler(
            token: registrationToken,
            surfaceID: surfaceID,
            box: box,
            domains: domains
        )
    }
}

/// Composes an existing screen loader with the surface coordinator. The inner
/// native refresh control must enter the coordinator instead of invoking only
/// its own action, otherwise sibling owners such as weather would remain stale.
private struct EusoRefreshableModifier: ViewModifier {
    @Environment(\.eusoRefresh) private var refresh
    @Environment(\.eusoRefreshSurfaceID) private var surfaceID
    let action: EusoRefreshOperation

    func body(content: Content) -> some View {
        content
            .modifier(EusoRefreshHandlerModifier(handler: action, domains: [.general]))
            .refreshable {
                if let surfaceID {
                    await refresh(surfaceID, reason: .userPull)
                } else {
                    await action()
                }
            }
    }
}

/// Preserves `.task` initial-load semantics and registers the exact same
/// one-shot loader for current-surface refreshes. Use only for read/hydration
/// work; long-lived loops and side-effecting mutations remain ordinary tasks.
private struct EusoRefreshTaskModifier: ViewModifier {
    let priority: TaskPriority
    let action: EusoRefreshOperation
    let domains: Set<EusoRefreshDomain>

    func body(content: Content) -> some View {
        content
            .modifier(EusoRefreshHandlerModifier(handler: action, domains: domains))
            .task(priority: priority) { await action() }
    }
}

extension View {
    /// Marks the current routed screen as the app-wide refresh target.
    func eusoRefreshSurface(
        _ surfaceID: String
    ) -> some View {
        modifier(EusoRefreshSurfaceModifier(surfaceID: surfaceID))
    }

    /// Registers a real async data-owner reload for pull and stale-foreground
    /// refreshes without recreating the view that owns form or navigation state.
    func eusoRefreshHandler(
        domains: Set<EusoRefreshDomain> = [.general],
        _ handler: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(EusoRefreshHandlerModifier(
            handler: EusoRefreshOperation(handler),
            domains: domains
        ))
    }

    /// Native pull-to-refresh plus the same callback registered for app-wide
    /// top-edge and stale-foreground requests. This is the migration path for
    /// legacy screen-owned loaders: one real closure, three refresh triggers.
    func eusoRefreshable(
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(EusoRefreshableModifier(action: EusoRefreshOperation(action)))
    }

    /// Initial one-shot read plus scoped pull/foreground refresh without a
    /// view identity change. Do not use for timers, capture sessions, or writes.
    func eusoRefreshTask(
        priority: TaskPriority = .userInitiated,
        domains: Set<EusoRefreshDomain> = [.general],
        _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(EusoRefreshTaskModifier(
            priority: priority,
            action: EusoRefreshOperation(action),
            domains: domains
        ))
    }
}

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
        // A visible surface can compose one owner callback from several
        // BaseDynamicStore children. MainActor serialization plus this guard
        // prevents concurrent owner/domain events from duplicating a store read.
        guard !isLoading else { return }
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
