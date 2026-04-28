//
//  218_ShipperDispatchControl.swift
//  EusoTrip 2027 UI — brick 218 (shipper · dispatch control)
//
//  Real-time dispatch board for shipper-side operations. Live view of
//  every active load with its current lifecycle stage, the assigned
//  catalyst, the driver-of-record, ETA, and a tap-to-drill detail
//  sheet that re-uses `ShipperLoadCycleView` so the visualization is
//  consistent with 205 ShipperLoadDetail.
//
//  Mirrors web `/shipper/dispatch-control` (`ShipperDispatchControl.tsx`)
//  in spirit — the heavyweight edit form (multi-stop reroute, time-
//  window changes, dispatch-note rewrites) lives on web. iOS surfaces
//  the read + a "Notify carrier" affordance that fires the canonical
//  `MeAction` so the future backend adapter can intercept without a
//  per-screen refactor.
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • Active-loads list → `shippers.getActiveLoads(limit: 50)`
//    • Status auto-refresh on appear + pull-to-refresh
//    • Per-load detail shows the same `ShipperLoadCycleView`
//      lifecycle strip the 205 detail screen renders, so the
//      shipper sees the SAME stage progression on every surface.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Status filter

private enum DispatchStatusFilter: String, CaseIterable, Identifiable {
    case all
    case posted
    case assigned
    case inTransit  = "in_transit"
    case loading
    case delivery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .posted:    return "Posted"
        case .assigned:  return "Assigned"
        case .inTransit: return "In transit"
        case .loading:   return "Loading"
        case .delivery:  return "Delivery"
        }
    }

    var icon: String {
        switch self {
        case .all:       return "square.grid.2x2"
        case .posted:    return "tray.full"
        case .assigned:  return "checkmark.seal"
        case .inTransit: return "arrow.triangle.swap"
        case .loading:   return "arrow.up.bin"
        case .delivery:  return "mappin.and.ellipse"
        }
    }

    func matches(_ status: String) -> Bool {
        let s = status.lowercased()
        switch self {
        case .all:        return true
        case .posted:     return s == "posted" || s == "draft" || s == "bidding"
        case .assigned:   return s == "assigned" || s == "accepted" || s == "awarded"
        case .inTransit:  return s == "in_transit" || s == "en_route" || s.contains("en_route")
        case .loading:    return s.contains("pickup") || s == "loading" || s == "loading_in_progress"
        case .delivery:   return s.contains("delivery") || s == "unloading" || s == "at_receiver"
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperDispatchControlStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded([ShipperAPI.ActiveLoad])
    }

    @Published private(set) var state: LoadState = .loading
    @Published var filter: DispatchStatusFilter = .all
    @Published var searchTerm: String = ""

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = try await api.shipper.getActiveLoads(limit: 50)
            state = rows.isEmpty ? .empty : .loaded(rows)
        } catch {
            state = .error("Couldn't reach dispatch service.")
        }
    }

    /// Loads matching the current filter + search term. Computed
    /// here so the view body stays declarative.
    var filtered: [ShipperAPI.ActiveLoad] {
        guard case .loaded(let rows) = state else { return [] }
        let q = searchTerm.lowercased().trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            guard filter.matches(row.status) else { return false }
            guard !q.isEmpty else { return true }
            return row.loadNumber.lowercased().contains(q)
                || row.origin.lowercased().contains(q)
                || row.destination.lowercased().contains(q)
                || row.catalyst.lowercased().contains(q)
                || row.driver.lowercased().contains(q)
        }
    }
}

// MARK: - Screen root

struct ShipperDispatchControl: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = ShipperDispatchControlStore()
    @State private var selected: ShipperAPI.ActiveLoad?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                filterChipRow
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { row in
            DispatchDetailSheet(load: row, role: session.user?.role)
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · DISPATCH CONTROL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Live operations")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Every active load · who's pulling it · where it's at · ETA. Drill in to ping the carrier or trigger a re-route on web.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Load # · lane · catalyst · driver", text: $store.searchTerm)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !store.searchTerm.isEmpty {
                Button {
                    store.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Filter chips

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DispatchStatusFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: DispatchStatusFilter) -> some View {
        let active = (store.filter == f)
        return Button {
            store.filter = f
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: f.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(f.label)
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: "Nothing in flight",
                subtitle: "When a posted load gets accepted, it lights up here with the catalyst, driver, and ETA.",
                comingSoon: false
            )
        case .error(let msg):
            errorBanner(msg)
        case .loaded:
            let rows = store.filtered
            if rows.isEmpty {
                Text("No loads match this filter.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                summaryStrip(rows)
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        loadRow(row)
                    }
                }
            }
        }
    }

    // MARK: Summary strip

    private func summaryStrip(_ rows: [ShipperAPI.ActiveLoad]) -> some View {
        let inTransit = rows.filter { LoadCycleStage.resolve(from: $0.status) == .inTransit }.count
        let pickup    = rows.filter { LoadCycleStage.resolve(from: $0.status) == .pickup }.count
        let delivery  = rows.filter { LoadCycleStage.resolve(from: $0.status) == .delivery }.count
        let assigned  = rows.filter { LoadCycleStage.resolve(from: $0.status) == .awarded }.count
        return HStack(spacing: Space.s2) {
            stripTile(value: "\(rows.count)", label: "TOTAL",      tint: nil)
            stripTile(value: "\(assigned)",    label: "ASSIGNED",  tint: Brand.info)
            stripTile(value: "\(pickup)",      label: "PICKUP",    tint: Brand.warning)
            stripTile(value: "\(inTransit)",   label: "IN TRANSIT", tint: Brand.success)
            stripTile(value: "\(delivery)",    label: "DELIVERY",  tint: Brand.success)
        }
    }

    private func stripTile(value: String, label: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint ?? palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Load row

    private func loadRow(_ row: ShipperAPI.ActiveLoad) -> some View {
        let stage = LoadCycleStage.resolve(from: row.status)
        return Button {
            selected = row
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: stage.symbol)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 24)
                    Text(row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    stageBadge(stage)
                }
                HStack(spacing: 4) {
                    Text(row.origin)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.destination)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    rowMeta(icon: "person.2.fill", value: row.catalyst.isEmpty ? "—" : row.catalyst)
                    rowMeta(icon: "person.fill",    value: row.driver.isEmpty ? "—" : row.driver)
                    rowMeta(icon: "clock.fill",     value: row.eta.isEmpty ? "TBD" : row.eta)
                    Spacer(minLength: 0)
                    Text(formatRate(row.rate))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(DispatchRowStyle())
    }

    private func stageBadge(_ stage: LoadCycleStage) -> some View {
        Text(stage.label.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(stageColor(stage))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(stageColor(stage).opacity(0.15)))
            .overlay(Capsule().strokeBorder(stageColor(stage).opacity(0.4), lineWidth: 0.75))
    }

    private func stageColor(_ stage: LoadCycleStage) -> Color {
        switch stage {
        case .posted, .bidding:   return palette.textSecondary
        case .awarded:             return Brand.info
        case .pickup:              return Brand.warning
        case .inTransit:           return Brand.success
        case .delivery:            return Brand.success
        case .paperwork:           return Brand.info
        case .closed:              return palette.textTertiary
        }
    }

    private func rowMeta(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
            Text(value)
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(palette.textTertiary)
    }

    private func formatRate(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 10_000 { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n >= 1_000  { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0       { return "—" }
        return "$\(n)"
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Dispatch service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Press feedback

private struct DispatchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Detail sheet

private struct DispatchDetailSheet: View {
    let load: ShipperAPI.ActiveLoad
    let role: String?
    @Environment(\.palette) private var palette

    private var vertical: TripVertical { TripVertical(role: role) }
    /// Best-effort product resolution from the active-load envelope.
    /// `getActiveLoads` doesn't ship cargoType/hazmatClass yet — we
    /// fall through to the vertical default (`dryVan` / `railIntermodal`
    /// / `vesselContainer`) so the silhouette never shows the wrong
    /// product on a generic active-load card.
    private var product: TripProduct {
        TripProduct.resolveDirect(cargoType: nil, hazmatClass: nil, vertical: vertical)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                ShipperLoadCycleView(
                    status: load.status,
                    product: product,
                    vertical: vertical
                )
                metaCard
                actionsCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIVE LOAD")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text(load.loadNumber)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 4) {
                Text(load.origin)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(load.destination)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ASSIGNMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            kvRow("Catalyst", value: load.catalyst.isEmpty ? "—" : load.catalyst, icon: "person.2.fill")
            kvRow("Driver",    value: load.driver.isEmpty ? "—" : load.driver,    icon: "person.fill")
            kvRow("ETA",       value: load.eta.isEmpty ? "TBD" : load.eta,        icon: "clock.fill")
            kvRow("Rate",      value: formatRate(load.rate),                       icon: "dollarsign.circle.fill")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 20)
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIONS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            actionButton(
                icon: "bell.badge.fill",
                title: "Notify carrier",
                subtitle: "Ping the catalyst with a status check.",
                key: "dispatch.notify-carrier"
            )
            actionButton(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Open chat thread",
                subtitle: "Direct message the driver about this load.",
                key: "dispatch.open-thread"
            )
            actionButton(
                icon: "arrow.triangle.branch",
                title: "Reroute on web",
                subtitle: "Multi-stop edits + pickup/delivery window changes ship from eusotrip.com/shipper/dispatch-control.",
                key: "dispatch.reroute"
            )
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func actionButton(icon: String, title: String, subtitle: String, key: String) -> some View {
        Button {
            MeAction.fire(key, userInfo: ["loadId": load.id, "loadNumber": load.loadNumber])
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.micro).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .buttonStyle(DispatchRowStyle())
    }

    private func formatRate(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 10_000 { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n >= 1_000  { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0       { return "—" }
        return "$\(n)"
    }
}

// MARK: - Previews

#Preview("218 · Dispatch Control · Night") {
    ShipperDispatchControl()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("218 · Dispatch Control · Afternoon") {
    ShipperDispatchControl()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
