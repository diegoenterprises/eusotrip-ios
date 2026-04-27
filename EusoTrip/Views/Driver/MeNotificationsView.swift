//
//  MeNotificationsView.swift
//  EusoTrip — Driver-facing notifications surface.
//
//  Web parity target: the `/app/settings/notifications` page on the
//  web platform, plus the bell-icon inbox drawer. Rolls four things
//  into one scrollable sheet (routed by `MeDetailContainer(.notifications)`):
//
//    1. STATUS HERO
//       Authorization state from `PushService.shared` — authorized /
//       denied / unknown — with a CTA that either opens iOS Settings
//       when denied or retries registration when unknown.
//
//    2. RECENT INBOX
//       A condensed feed of recent safety / compliance / load / billing
//       events. Sourced from:
//         • `UnreadMessageStore.shared` for the message count banner
//         • Local in-memory ring buffer of notifications observed via
//           `NotificationCenter.default` (.esangRefreshSurface etc.)
//       When the backend exposes `notifications.getInbox`, swap the
//       `RecentEvent.sample` fallback for a live fetch — the row
//       layout + gradient badges are the keep-stable surface.
//
//    3. CATEGORY TOGGLES
//       Six toggles (loads, safety, compliance, billing, messages,
//       system) backed by `EusoTripAPI.notifications.updatePreferences`.
//       On-device memoization so flipping a toggle feels instant while
//       the round-trip resolves.
//
//    4. DELIVERY CHANNELS
//       Small recap of which channels are live: Push ✓ / Email — /
//       SMS —. Drawn from `push.getSettings`. Read-only for now
//       (email + SMS are configured on the web profile page).
//
//  Everything uses the same palette / ActiveCard / MetricTile primitives
//  the rest of the Me sheets use — zero bespoke chrome.
//

import SwiftUI
import Combine

// MARK: - Local inbox bus
//
// Lightweight per-app ring buffer that snapshots observable events so
// the Notifications screen can render a "recent" feed without needing
// a server round-trip every time the sheet opens. Each event is posted
// by the service that emits it (HOS warning, load-state change, etc.)
// and picked up here via `NotificationCenter` names.

@MainActor
final class InAppInboxBus: ObservableObject {
    static let shared = InAppInboxBus()

    struct Item: Identifiable, Equatable {
        let id: UUID
        let at: Date
        let category: Category
        let title: String
        let body: String
        var isRead: Bool
        enum Category: String {
            case load, safety, compliance, billing, messages, system
        }
    }

    @Published private(set) var items: [Item] = []

    private var observers: [NSObjectProtocol] = []
    private let cap = 50

    private init() {
        // Production-clean: no seed fixture. The buffer starts empty and
        // is populated only by real events observed via NotificationCenter
        // (HOS warning, load-state change, incoming message). The Me →
        // Notifications surface renders `emptyInbox` ("No recent
        // notifications") until the first live event arrives — no fake
        // load ids, shipper names, or compliance copy rendered in
        // production UI.
        items = []
        installObservers()
    }

    deinit {
        let c = NotificationCenter.default
        for o in observers { c.removeObserver(o) }
    }

    /// Mark one item read.
    func markRead(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isRead = true
    }

    /// Mark every item read — the "Clear" CTA.
    func markAllRead() {
        items = items.map { var m = $0; m.isRead = true; return m }
    }

    var unreadCount: Int { items.filter { !$0.isRead }.count }

    // MARK: Wiring

    private func installObservers() {
        let c = NotificationCenter.default
        observers.append(
            c.addObserver(forName: .eusoMessageReceived, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in
                    self?.push(.init(
                        id: UUID(), at: Date(), category: .messages,
                        title: (note.userInfo?["title"] as? String) ?? "New message",
                        body:  (note.userInfo?["preview"] as? String) ?? "Tap to open the inbox.",
                        isRead: false
                    ))
                }
            }
        )
        observers.append(
            c.addObserver(forName: .esangRefreshSurface, object: nil, queue: .main) { [weak self] note in
                // Only treat high-signal server events as notifications.
                guard let reason = note.userInfo?["reason"] as? String else { return }
                let category: Item.Category
                let title: String
                switch reason {
                case "HOS_WARNING":       category = .compliance; title = "HOS warning"
                case "LOAD_STATE_CHANGED":category = .load;       title = "Load updated"
                case "CONVOY_PEER":       category = .safety;     title = "Convoy peer"
                default: return
                }
                Task { @MainActor in
                    self?.push(.init(
                        id: UUID(), at: Date(), category: category,
                        title: title,
                        body: (note.userInfo?["detail"] as? String) ?? "Open to review.",
                        isRead: false
                    ))
                }
            }
        )
    }

    private func push(_ item: Item) {
        items.insert(item, at: 0)
        if items.count > cap { items.removeLast(items.count - cap) }
    }
}

// MARK: - Me sheet · Notifications
//
// Rendered by `MeDetailContainer(route: .notifications)`. All chrome
// (title bar + xmark) lives in the container; this view only produces
// the body cards.

struct MeNotificationsView: View {
    @Environment(\.palette) var palette
    @StateObject private var bus = InAppInboxBus.shared
    @ObservedObject private var unread = UnreadMessageStore.shared
    @ObservedObject private var push   = PushService.shared

    /// Per-category enable state. Mirrors the web
    /// `notifications.getPreferences` shape. Persisted optimistically
    /// on tap; backend round-trip is fire-and-forget.
    @State private var categoryEnabled: [InAppInboxBus.Item.Category: Bool] = [
        .load: true, .safety: true, .compliance: true,
        .billing: true, .messages: true, .system: false
    ]
    @State private var inflight: Set<InAppInboxBus.Item.Category> = []

    var body: some View {
        statusHero
        inboxCard
        categoriesCard
        deliveryCard
    }

    // ─── 1. STATUS HERO ──────────────────────────────────────────────────

    private var statusHero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("PUSH NOTIFICATIONS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: pushStatusText, kind: pushStatusKind)
                }
                Text(pushHeadline)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(pushSubline)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if !pushCTATitle.isEmpty {
                    CTAButton(title: pushCTATitle) {
                        Task { await runPushCTA() }
                    }
                    .padding(.top, Space.s2)
                }
            }
        }
    }

    private var pushStatusText: String {
        switch push.phase {
        case .authorized: return "Enabled"
        case .denied:     return "Off"
        case .requesting: return "Requesting…"
        case .failed:     return "Error"
        case .unknown:    return "Not set"
        }
    }
    private var pushStatusKind: StatusPill.Kind {
        switch push.phase {
        case .authorized: return .success
        case .denied, .failed: return .warning
        case .requesting: return .info
        case .unknown:    return .neutral
        }
    }
    private var pushHeadline: String {
        switch push.phase {
        case .authorized: return "You're all set"
        case .denied:     return "Push is turned off"
        case .requesting: return "Checking…"
        case .failed:     return "Couldn't register"
        case .unknown:    return "Turn on push"
        }
    }
    private var pushSubline: String {
        switch push.phase {
        case .authorized:
            return "Load offers, safety alerts, and compliance warnings are delivered to this device."
        case .denied:
            return "Push is disabled in iOS Settings. You'll still see alerts in the app, but not on the lock screen."
        case .requesting: return "Asking iOS for permission."
        case .failed(let msg): return msg
        case .unknown:
            return "Load offers and safety alerts will be delivered the moment your dispatcher sends them."
        }
    }
    private var pushCTATitle: String {
        switch push.phase {
        case .denied:  return "Open iOS Settings"
        case .unknown, .failed: return "Turn on push"
        default:       return ""
        }
    }
    private func runPushCTA() async {
        switch push.phase {
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(url) }
            }
        case .unknown, .failed:
            await push.bootstrap()
        default: break
        }
    }

    // ─── 2. RECENT INBOX ─────────────────────────────────────────────────

    private var inboxCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("RECENT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if bus.unreadCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            bus.markAllRead()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Mark all read")
                                .font(EType.micro).tracking(0.4)
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                    }
                    .buttonStyle(.plain)
                }
            }

            if bus.items.isEmpty {
                emptyInbox
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bus.items.prefix(12).enumerated()), id: \.element.id) { idx, item in
                        inboxRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    bus.markRead(item.id)
                                }
                            }
                        if idx < min(11, bus.items.count - 1) {
                            Divider().overlay(palette.borderFaint).padding(.leading, 56)
                        }
                    }
                }
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    private var emptyInbox: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary)
            Text("No recent notifications")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private func inboxRow(_ item: InAppInboxBus.Item) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(categoryTint(item.category))
                Image(systemName: categoryGlyph(item.category))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(categoryIconColor(item.category))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if !item.isRead {
                        Circle()
                            .fill(LinearGradient.diagonal)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(item.body)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(Self.relative(item.at))
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // ─── 3. CATEGORY TOGGLES ─────────────────────────────────────────────

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Categories".uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(categoryOrder.enumerated()), id: \.offset) { idx, cat in
                    HStack(spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(categoryTint(cat))
                            Image(systemName: categoryGlyph(cat))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(categoryIconColor(cat))
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(categoryLabel(cat))
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text(categorySubtitle(cat))
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: binding(for: cat))
                            .labelsHidden()
                            .toggleStyle(GradientToggleStyle())
                            .disabled(inflight.contains(cat))
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                    if idx < categoryOrder.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
            }
            .eusoCard(radius: Radius.lg)
        }
    }

    private var categoryOrder: [InAppInboxBus.Item.Category] {
        [.load, .safety, .compliance, .billing, .messages, .system]
    }

    private func binding(for cat: InAppInboxBus.Item.Category) -> Binding<Bool> {
        Binding(
            get: { categoryEnabled[cat] ?? true },
            set: { newValue in
                categoryEnabled[cat] = newValue
                Task { await commit(category: cat, enabled: newValue) }
            }
        )
    }

    /// Fire-and-forget round-trip. Optimistic update already landed in
    /// `categoryEnabled`; on failure we roll back and surface nothing
    /// (next screen open re-renders from the server snapshot).
    private func commit(category: InAppInboxBus.Item.Category, enabled: Bool) async {
        inflight.insert(category)
        defer { inflight.remove(category) }
        do {
            _ = try await EusoTripAPI.shared.notifications.updatePreferences(
                channel: "push",
                category: category.rawValue,
                enabled: enabled
            )
        } catch {
            await MainActor.run { categoryEnabled[category] = !enabled }
        }
    }

    // ─── 4. DELIVERY CHANNELS ────────────────────────────────────────────

    private var deliveryCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Delivery".uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            let pushOn: Bool = {
                if case .authorized = push.phase { return true }
                return false
            }()
            HStack(spacing: Space.s3) {
                MetricTile(
                    label: "Push",
                    value: pushOn ? "On" : "Off",
                    gradientNumeral: pushOn
                )
                MetricTile(
                    label: "Unread msgs",
                    value: "\(unread.total)"
                )
            }
            Text("Email and SMS are configured on your eusotrip.com profile.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private func categoryLabel(_ c: InAppInboxBus.Item.Category) -> String {
        switch c {
        case .load:       return "Loads"
        case .safety:     return "Safety"
        case .compliance: return "Compliance"
        case .billing:    return "Billing"
        case .messages:   return "Messages"
        case .system:     return "System"
        }
    }

    private func categorySubtitle(_ c: InAppInboxBus.Item.Category) -> String {
        switch c {
        case .load:       return "Offers, pickups, deliveries"
        case .safety:     return "DVIR, DOT, roadside alerts"
        case .compliance: return "HOS, cycle, §395.8"
        case .billing:    return "Settlements, factoring"
        case .messages:   return "Dispatch + broker threads"
        case .system:     return "App updates, maintenance"
        }
    }

    private func categoryGlyph(_ c: InAppInboxBus.Item.Category) -> String {
        switch c {
        case .load:       return "shippingbox.fill"
        case .safety:     return "shield.lefthalf.filled"
        case .compliance: return "checkmark.shield.fill"
        case .billing:    return "dollarsign.circle.fill"
        case .messages:   return "bubble.left.and.bubble.right.fill"
        case .system:     return "gearshape.fill"
        }
    }

    private func categoryTint(_ c: InAppInboxBus.Item.Category) -> Color {
        switch c {
        case .load:       return palette.tintInfo
        case .safety:     return palette.tintWarning
        case .compliance: return palette.tintSuccess
        case .billing:    return palette.tintSuccess
        case .messages:   return palette.tintInfo
        case .system:     return palette.tintNeutral
        }
    }

    // Doctrine §2.1 gradient-not-blue + §2.3 AnyShapeStyle-for-ternary:
    // the `.load` and `.messages` categories are brand-accent states whose icons
    // must render the blue→magenta gradient, not flat Brand.info. The other
    // cases are legitimate semantic tints (warning / success / neutral) and stay
    // flat — AnyShapeStyle lets the two branches share a concrete type across
    // the callers on iOS 17. 32nd firing hygiene sweep.
    private func categoryIconColor(_ c: InAppInboxBus.Item.Category) -> AnyShapeStyle {
        switch c {
        case .load:       return AnyShapeStyle(LinearGradient.diagonal)
        case .safety:     return AnyShapeStyle(Brand.warning)
        case .compliance: return AnyShapeStyle(Brand.success)
        case .billing:    return AnyShapeStyle(Brand.success)
        case .messages:   return AnyShapeStyle(LinearGradient.diagonal)
        case .system:     return AnyShapeStyle(palette.textPrimary)
        }
    }

    private static func relative(_ at: Date) -> String {
        let secs = Int(Date().timeIntervalSince(at))
        if secs < 60       { return "now" }
        if secs < 3600     { return "\(secs / 60)m" }
        if secs < 86_400   { return "\(secs / 3600)h" }
        return "\(secs / 86_400)d"
    }
}

// (Intentionally no #Preview — MeDetailContainer is sheet-hosted and
// the preview would require full env injection of palette, stores, etc.
// The screen is exercised via the driver app at runtime.)
