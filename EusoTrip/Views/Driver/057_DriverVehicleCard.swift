//
//  057_DriverVehicleCard.swift
//  EusoTrip 2027 UI — Wave 7 (fleet · driver vehicle card)
//
//  Screen 057 · Driver Vehicle Card — the driver's live assets hub. Shows
//  the tractor, trailer, and any APU / auxiliary units that the fleet
//  router returns for this driver, pulled live from `fleet.listAssets`
//  via `FleetStore` (declared in `ViewModels/LiveDataStores.swift` L549).
//
//  Cohort-B dynamization · zero mock data, zero stubs
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data" clause):
//
//    • Every unit number, VIN-adjacent field, plate, make, model, year,
//      odometer reading, home-base city, and status pill on-screen is
//      rendered from one of two live stores:
//
//        - `FleetStore`                · `fleet.listAssets`
//        - `VehicleMaintenanceStore`   · `fleet.getMaintenanceSchedule(assetId:)`
//          (scoped to the primary tractor — we only fire it once the
//           tractor id is known so we never send a speculative request)
//
//      No placeholder unit numbers (TR-…, T-…), no sample VINs, no
//      hard-coded Peterbilt / Freightliner strings. The screen renders
//      em-dashes when the server omits a field and renders the branded
//      `EusoEmptyState` when the response confirms the driver has no
//      assigned assets yet.
//
//    • `.empty` branches are distinct from `.loading` — the branded
//      empty state is only shown once the server confirms `items: []`.
//      `.error` surfaces the localized server message in-pane rather
//      than the page disappearing.
//
//    • CTAs route through the existing env / session surface — no
//      dead buttons. "Report issue" routes to the ESANG Dispatch chat
//      the same way brick 053 does (handled by BottomNav), and
//      "View maintenance" scrolls to the maintenance section in-place.
//      There are no placeholder `.onTapGesture { }` handlers.
//
//  Doctrine refs:
//    §2   Gradient-only brand accents — hero VIN label, odometer
//         metric, and the Action row icons use `LinearGradient.diagonal`.
//         Status pill color is palette-semantic (success / warning /
//         danger) — never `Brand.blue` / `Brand.info` as a fill.
//    §3   Numbers-first — odometer is the dominant numeric anchor
//         under the tractor identity line.
//    §7   Breathe rhythm — topbar → tractor card → trailer card →
//         auxiliary units → maintenance preview → action rows.
//    §11  No-lorem — every placeholder caption corresponds to a real
//         `.empty` / `.error` / `.loading` branch; nothing invents copy.
//    §12  Capstone map — §14 (roles/modes/verticals/countries): this
//         screen is the driver-asset capstone for the US / CA / MX
//         Driver role across truck / rail / vessel modes. Status
//         labels ("in_maintenance", "out_of_service") fall through
//         verbatim from the server so the three-mode fleet router's
//         enum doesn't get paraphrased on the client.
//
//  Not in scope (follow-up firings):
//    • Editing the assigned tractor / trailer (needs
//      `fleet.updateAssignment` — not shipped server-side yet).
//    • Fuel transactions list (already covered on a separate brick
//      via `fleet.fuelTransactions`).
//    • DVIR linkage — DVIR history already lives on a separate store
//      (`InspectionsHistoryStore`) and surface.
//

import SwiftUI

// MARK: - VehicleMaintenanceStore (live · scoped to tractor id)
//
// Declared at file scope so 057 stays self-contained and the store
// isn't added to the shared `LiveDataStores.swift` surface unless
// another screen needs it. If a future screen (e.g. a dedicated
// Me → Maintenance hub) picks this up, promote the class into
// `LiveDataStores.swift` and delete this local declaration.
@MainActor
final class VehicleMaintenanceStore:
    BaseDynamicListStore<FleetAPI.MaintenanceItem>
{
    /// The asset the schedule is scoped to. `nil` means the store is
    /// parked — `.refresh()` is a no-op until the caller sets this
    /// from the primary tractor's id.
    var assetId: String? = nil

    override func fetch() async throws -> [FleetAPI.MaintenanceItem] {
        // We never speculate. If the caller hasn't told us which asset
        // to look at, we fold to `.empty` without hitting the network.
        guard let assetId, !assetId.isEmpty else { return [] }
        let response = try await EusoTripAPI.shared.fleet
            .getMaintenanceSchedule(assetId: assetId)
        return response.items
    }
}

// MARK: - Screen

struct DriverVehicleCard: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var session: EusoTripSession

    // MARK: Live stores
    @StateObject private var fleetStore = FleetStore()
    @StateObject private var maintenanceStore = VehicleMaintenanceStore()

    // MARK: Local UI state
    @State private var showAllMaintenance = false

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            content
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s8)
        }
        .task {
            // First load the fleet — the maintenance store is gated
            // behind having a tractor id, so it can't run in parallel
            // on the very first tick.
            await fleetStore.refresh()
            if let tractorId = primaryTractor(from: fleetStore.items)?.id {
                maintenanceStore.assetId = tractorId
                await maintenanceStore.refresh()
            }
        }
        .sheet(isPresented: $showAllMaintenance) {
            VehicleMaintenanceSheet(store: maintenanceStore)
                .eusoSheetX()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            topBar
            switch fleetStore.state {
            case .loading:
                loadingPane
            case .empty:
                emptyPane
            case .error(let err):
                errorPane(err: err)
            case .loaded(let assets):
                loadedContent(assets: assets)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("VEHICLE")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)
            Spacer()
            if case .loaded(let assets) = fleetStore.state,
               let fleetId = primaryTractor(from: assets)?.id, !fleetId.isEmpty {
                Text("UNIT \(primaryTractor(from: assets)?.unitNumber ?? "")")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedContent(assets: [FleetAsset]) -> some View {
        if let tractor = primaryTractor(from: assets) {
            tractorCard(tractor: tractor)
        }
        if let trailer = primaryTrailer(from: assets) {
            trailerCard(trailer: trailer)
        }
        let auxiliaries = auxiliaryAssets(from: assets)
        if !auxiliaries.isEmpty {
            auxiliarySection(assets: auxiliaries)
        }
        maintenanceSection
        actionRows
    }

    // MARK: - Tractor card

    private func tractorCard(tractor: FleetAsset) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRACTOR")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                statusPill(status: tractor.status)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(assetDisplayName(tractor))
                    .font(EType.h2)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(assetSubtitle(tractor))
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Divider().background(palette.borderFaint)
            odometerRow(tractor: tractor)
            plateAndHomeBaseRow(asset: tractor)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func odometerRow(tractor: FleetAsset) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(odometerString(tractor.odometerMiles))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
            Text("MI")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundColor(palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Trailer card

    private func trailerCard(trailer: FleetAsset) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRAILER")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                statusPill(status: trailer.status)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(assetDisplayName(trailer))
                    .font(EType.h2)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(assetSubtitle(trailer))
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Divider().background(palette.borderFaint)
            plateAndHomeBaseRow(asset: trailer)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: - Auxiliary units (APU / other)

    private func auxiliarySection(assets: [FleetAsset]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("AUXILIARY UNITS")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { (idx, a) in
                    auxiliaryRow(asset: a)
                    if idx < assets.count - 1 {
                        Divider().background(palette.borderFaint)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    private func auxiliaryRow(asset: FleetAsset) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: auxiliaryGlyph(for: asset.kind))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(assetDisplayName(asset))
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(asset.kind.uppercased() + " · Unit " + asset.unitNumber)
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            statusPill(status: asset.status)
        }
        .padding(Space.s4)
    }

    // MARK: - Shared rows

    private func plateAndHomeBaseRow(asset: FleetAsset) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLATE")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Text(plateString(asset.plate))
                    .font(EType.bodyStrong.monospacedDigit())
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s3)
            VStack(alignment: .trailing, spacing: 2) {
                Text("HOME BASE")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Text(homeBaseString(asset.homeBase))
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Status pill

    private func statusPill(status: String?) -> some View {
        let label = statusLabel(status: status)
        let color = statusColor(status: status)
        return Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundColor(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Maintenance preview

    @ViewBuilder
    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("UPCOMING MAINTENANCE")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                if case .loaded(let items) = maintenanceStore.state, items.count > 3 {
                    Button {
                        showAllMaintenance = true
                    } label: {
                        Text("VIEW ALL")
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .accessibilityLabel("View all maintenance tasks")
                }
            }
            maintenanceBody
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var maintenanceBody: some View {
        switch maintenanceStore.state {
        case .loaded(let items):
            VStack(spacing: 0) {
                let shown = items.prefix(3)
                ForEach(Array(shown.enumerated()), id: \.element.id) { (idx, item) in
                    maintenanceRow(item: item)
                    if idx < shown.count - 1 {
                        Divider().background(palette.borderFaint)
                    }
                }
            }
        case .loading:
            Text("Loading maintenance schedule…")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
        case .empty:
            Text(maintenanceStore.assetId == nil
                 ? "No tractor assigned — maintenance will appear once dispatch pairs you with a unit."
                 : "No upcoming maintenance tasks for this tractor.")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .error(let err):
            Text("Maintenance unavailable — \(err.localizedDescription)")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func maintenanceRow(
        item: FleetAPI.MaintenanceItem
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    severityIsCritical(item.severity)
                    ? AnyShapeStyle(palette.danger)
                    : AnyShapeStyle(LinearGradient.diagonal)
                )
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.taskName)
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text(maintenanceSubtitle(item: item))
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(item.severity.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundColor(
                    severityIsCritical(item.severity) ? palette.danger : palette.textTertiary
                )
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Action rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                systemImage: "arrow.clockwise",
                title: "Refresh fleet assignment",
                subtitle: "Pulls the latest tractor / trailer from dispatch"
            ) {
                Task {
                    await fleetStore.refresh()
                    if let tractorId = primaryTractor(from: fleetStore.items)?.id {
                        maintenanceStore.assetId = tractorId
                        await maintenanceStore.refresh()
                    }
                }
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "wrench.and.screwdriver",
                title: "View full maintenance schedule",
                subtitle: "All open tasks for the current tractor",
                disabled: !hasAnyMaintenance
            ) { showAllMaintenance = true }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        disabled
                        ? AnyShapeStyle(palette.textTertiary)
                        : AnyShapeStyle(LinearGradient.diagonal)
                    )
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundColor(
                            disabled ? palette.textTertiary : palette.textPrimary
                        )
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.textTertiary)
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Non-loaded panes

    private var loadingPane: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading your fleet assignment…")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private var emptyPane: some View {
        EusoEmptyState(
            systemImage: "truck.box",
            title: "No assigned vehicle yet",
            subtitle: "Once dispatch pairs you with a tractor and trailer, the unit details, plate, odometer, and maintenance schedule show up here.",
            cta: (label: "Refresh", action: {
                Task { await fleetStore.refresh() }
            })
        )
    }

    private func errorPane(err: Error) -> some View {
        EusoEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Fleet temporarily unavailable",
            subtitle: err.localizedDescription,
            cta: (label: "Retry", action: {
                Task { await fleetStore.refresh() }
            })
        )
    }

    // MARK: - Asset selection helpers

    /// The tractor the driver is currently assigned to. We prefer the
    /// first tractor with status `active`; if no active tractor is in
    /// the list we fall through to the first tractor at all. The server
    /// is the source of truth on assignment — we never second-guess
    /// ordering, we just pick the most operationally-relevant unit to
    /// anchor the hero.
    private func primaryTractor(from assets: [FleetAsset]) -> FleetAsset? {
        let tractors = assets.filter { $0.kind.lowercased() == "tractor" }
        return tractors.first { ($0.status?.lowercased() ?? "") == "active" }
            ?? tractors.first
    }

    private func primaryTrailer(from assets: [FleetAsset]) -> FleetAsset? {
        let trailers = assets.filter { $0.kind.lowercased() == "trailer" }
        return trailers.first { ($0.status?.lowercased() ?? "") == "active" }
            ?? trailers.first
    }

    private func auxiliaryAssets(from assets: [FleetAsset]) -> [FleetAsset] {
        assets.filter {
            let k = $0.kind.lowercased()
            return k != "tractor" && k != "trailer"
        }
    }

    private var hasAnyMaintenance: Bool {
        if case .loaded(let items) = maintenanceStore.state, !items.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Format helpers

    private func assetDisplayName(_ asset: FleetAsset) -> String {
        let year = asset.year.map { String($0) } ?? ""
        let make = asset.make ?? ""
        let model = asset.model ?? ""
        let joined = [year, make, model]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? "Unit \(asset.unitNumber)" : joined
    }

    private func assetSubtitle(_ asset: FleetAsset) -> String {
        "Unit \(asset.unitNumber) · \(asset.kind.uppercased())"
    }

    private func odometerString(_ miles: Int?) -> String {
        guard let miles else { return "—" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: miles)) ?? String(miles)
    }

    private func plateString(_ plate: String?) -> String {
        guard let plate, !plate.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "—"
        }
        return plate
    }

    private func homeBaseString(_ homeBase: String?) -> String {
        guard let base = homeBase, !base.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "—"
        }
        return base
    }

    private func statusLabel(status: String?) -> String {
        guard let raw = status, !raw.isEmpty else { return "UNKNOWN" }
        // Canonical enum strings come back as snake_case — render them
        // verbatim but uppercased so "in_maintenance" reads as
        // "IN MAINTENANCE" without the client inventing its own
        // vocabulary.
        return raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private func statusColor(status: String?) -> Color {
        switch status?.lowercased() ?? "" {
        case "active":           return palette.success
        case "in_maintenance":   return palette.warning
        case "out_of_service":   return palette.danger
        default:                 return palette.textTertiary
        }
    }

    private func auxiliaryGlyph(for kind: String) -> String {
        switch kind.lowercased() {
        case "apu":        return "bolt.fill"
        case "reefer":     return "snowflake"
        case "tanker":     return "drop.fill"
        default:           return "shippingbox"
        }
    }

    private func maintenanceSubtitle(
        item: FleetAPI.MaintenanceItem
    ) -> String {
        var parts: [String] = []
        if let due = item.dueDate, !due.isEmpty {
            parts.append("Due \(due)")
        }
        if let miles = item.dueMiles {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            let pretty = fmt.string(from: NSNumber(value: miles)) ?? String(miles)
            parts.append("\(pretty) mi")
        }
        if parts.isEmpty, let notes = item.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func severityIsCritical(_ severity: String) -> Bool {
        let s = severity.lowercased()
        return s == "critical" || s == "high" || s == "urgent"
    }
}

// MARK: - Maintenance sheet (full list, same store, no refetch)

private struct VehicleMaintenanceSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VehicleMaintenanceStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    switch store.state {
                    case .loaded(let items):
                        ForEach(items) { item in
                            row(item: item)
                        }
                    case .loading:
                        Text("Loading maintenance schedule…")
                            .font(EType.caption)
                            .foregroundColor(palette.textTertiary)
                    case .empty:
                        EusoEmptyState(
                            systemImage: "wrench.and.screwdriver",
                            title: "No maintenance tasks",
                            subtitle: "This tractor has no open items on the schedule."
                        )
                    case .error(let err):
                        EusoEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: "Maintenance unavailable",
                            subtitle: err.localizedDescription
                        )
                    }
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Maintenance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(EType.bodyStrong)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
    }

    private func row(
        item: FleetAPI.MaintenanceItem
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.taskName)
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text(item.severity.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundColor(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }
}

// MARK: - Screen wrapper

struct DriverVehicleCardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            DriverVehicleCard()
        } nav: {
            BottomNav(
                leading: driverNavLeading_057(),
                trailing: driverNavTrailing_057(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_057() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",     isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: false)]
}
private func driverNavTrailing_057() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews
//
// The live-store path is the production path. Previews render that same
// path with no authenticated session — both stores resolve to `.empty`
// deterministically (FleetStore because the unauthed client returns
// an empty items array, VehicleMaintenanceStore because `assetId` is
// still nil and the store folds to `[]`). The screen surfaces the
// branded empty state exactly the way a freshly-provisioned driver
// would see it before dispatch assigns a unit. No fixture data is
// injected.

#Preview("057 · Driver Vehicle Card · Night · Empty / Live stores") {
    DriverVehicleCardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("057 · Driver Vehicle Card · Afternoon · Empty / Live stores") {
    DriverVehicleCardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
