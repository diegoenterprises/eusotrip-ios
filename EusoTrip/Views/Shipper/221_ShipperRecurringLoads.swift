//
//  221_ShipperRecurringLoads.swift
//  EusoTrip 2027 UI — Shipper · Recurring Loads (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/221_ShipperRecurringLoads.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11.
//  Template IDs reuse the §11.2 LD- audit-trail convention so the
//  `loads` and `load_templates` tables join on a stable hex-tail
//  identifier even though the iOS API ships only an `Int id`.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · RECURRING LOADS / "{N} ACTIVE · {M}/WK"
//    2. Title block      Recurring loads (34pt) / "Eusorone Technologies · {N} templates · {M} loads queued this week"
//    3. IridescentHairline
//    4. Hero KPI card    gradient rim · 4-cell quartet
//                        (TEMPLATES · QUEUED loads · SAVED YTD · NEXT)
//    5. Filter chip row  All · Active · {N} · Paused · {N} · Daily · Weekly
//    6. Template rows    3pt tier rim · TPL id · status pill · lane title ·
//                        spec line · 3-stat row · next-fire countdown bar
//    7. "+ New recurring schedule" gradient pill CTA
//
//  Real wiring preserved: `loadTemplates.list(search, favoritesOnly,
//  includeArchived)` + `shippers.create(...)` via
//  `ShipperRecurringLoadsStore`. Detail sheet preserved with Post-now
//  + Schedule-on-web actions.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2129 — `loadTemplates.list` doesn't ship `cadence` (rrule),
//                `isPaused`, or `nextFireAt`. Daily / Weekly chip
//                counts paint "—". Status pill / tier rim infer from
//                `isArchived` (paused proxy) until backend adds an
//                explicit `cadence` + `nextFireAt` column. Countdown
//                bar paints empty track for active rows.
//    EUSO-2130 — No portfolio aggregates (queued-loads / saved-YTD /
//                next-fire). KPI hero `QUEUED` / `SAVED YTD` / `NEXT`
//                cells paint "—" until backend ships
//                `loadTemplates.getStats`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2
//  Diego canon + audit-trail; §11.4 / §13 carrier mix; §12.3 list-
//  first mobile, wizard-on-web (CTA hands off to web wizard via
//  MeAction); §15.2 per-row 3pt tier rim; §16 hero-rim KPI quartet;
//  §16.2 gradient pill CTA; §19.2 file-scoped `warnGrad` / `paidGrad`;
//  §20.4 no dead buttons; §22.2 counter color (textSecondary
//  informational).
//

import SwiftUI

// MARK: - Filter chips (wireframe canon labels with derived counts)

private enum TemplateFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case paused
    case daily
    case weekly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "All"
        case .active:  return "Active"
        case .paused:  return "Paused"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        }
    }
}

private enum TierRim { case gradient, warn, paid, neutral }

// MARK: - Store (preserved + extended with filter)

@MainActor
final class ShipperRecurringLoadsStore: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case loaded([LoadTemplatesAPI.Template])
        case error(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published var search: String = ""
    @Published fileprivate var filter: TemplateFilter = .all
    @Published var posting: Set<Int> = []
    @Published var lastAck: ShipperAPI.PostLoadAck? = nil
    @Published var lastError: String? = nil

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        state = .loading
        do {
            // EUSO-2129 — backend `favoritesOnly` doesn't map to wireframe
            // filters. Pull all templates and filter client-side. The
            // `includeArchived: true` flag surfaces paused-proxy rows so
            // the .paused chip can show them.
            let rows = try await api.loadTemplates.list(
                search: search.isEmpty ? nil : search,
                favoritesOnly: nil,
                includeArchived: true
            )
            state = .loaded(applyClientFilter(rows: rows, filter: filter))
        } catch {
            state = .error("Couldn't load saved lanes.")
        }
    }

    /// Public so the chip-count helper can recompute against the
    /// unfiltered list when chip counts need to render for filters
    /// other than the active one.
    fileprivate func applyClientFilter(rows: [LoadTemplatesAPI.Template],
                                       filter: TemplateFilter) -> [LoadTemplatesAPI.Template] {
        switch filter {
        case .all:
            return rows
        case .active:
            return rows.filter { $0.isArchived != true }
        case .paused:
            return rows.filter { $0.isArchived == true }
        case .daily, .weekly:
            // EUSO-2129 — cadence not on row envelope.
            return []
        }
    }

    func post(template t: LoadTemplatesAPI.Template) async {
        posting.insert(t.id)
        defer { posting.remove(t.id) }
        let originPair = Self.cityState(t.origin)
        let destPair   = Self.cityState(t.destination)
        guard !originPair.isEmpty, !destPair.isEmpty else {
            lastError = "Template missing origin or destination."
            return
        }
        let raw    = (t.cargoType ?? "general").lowercased()
        let cargo  = ShipperAPI.CargoType(rawValue: raw) ?? .general
        let rate: Double?   = t.rate.flatMap { Double($0) }
        let weight: Double? = t.weight.flatMap { Double($0) }
        do {
            let ack = try await api.shipper.create(
                origin: originPair,
                destination: destPair,
                cargoType: cargo,
                rate: rate,
                weight: weight,
                notes: t.description,
                pickupDate: nil
            )
            lastAck = ack
            lastError = nil
            await load()
        } catch {
            lastError = "Couldn't post load. Try again."
        }
    }

    private static func cityState(_ loc: LoadTemplatesAPI.Template.Location?) -> String {
        guard let loc else { return "" }
        let c = (loc.city ?? "").trimmingCharacters(in: .whitespaces)
        let s = (loc.state ?? "").trimmingCharacters(in: .whitespaces)
        if !c.isEmpty && !s.isEmpty { return "\(c), \(s)" }
        if !c.isEmpty { return c }
        if !s.isEmpty { return s }
        return ""
    }
}

// MARK: - Screen root

struct ShipperRecurringLoads: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperRecurringLoadsStore()
    @State private var detail: LoadTemplatesAPI.Template? = nil
    @State private var showAck: Bool = false
    @State private var unfiltered: [LoadTemplatesAPI.Template] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .onChange(of: store.filter) { _, _ in Task { await store.load() } }
        .onChange(of: store.lastAck?.id ?? -1) { _, v in if v != -1 { showAck = true } }
        .onChange(of: storeStateKey) { _, _ in updateUnfiltered() }
        .sheet(item: $detail) {
            ShipperRecurringLoadDetail(template: $0).environmentObject(store)
        }
        .alert("Posted", isPresented: $showAck, actions: {
            Button("OK") { store.lastAck = nil }
        }, message: {
            if let ack = store.lastAck {
                Text("Load \(ack.loadNumber) is live on the board.")
            }
        })
    }

    private var storeStateKey: String {
        switch store.state {
        case .idle:        return "idle"
        case .loading:     return "loading"
        case .error:        return "error"
        case .loaded(let r): return "loaded-\(r.count)"
        }
    }

    private func updateUnfiltered() {
        if case .loaded(let r) = store.state, store.filter == .all {
            unfiltered = r
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · RECURRING LOADS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textSecondary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        let active = unfiltered.filter { $0.isArchived != true }.count
        let totalUses = unfiltered.reduce(0) { $0 + ($1.useCount ?? 0) }
        return "\(active) ACTIVE · \(totalUses) POSTS"
    }

    private var counterAccessibility: String {
        let active = unfiltered.filter { $0.isArchived != true }.count
        return "\(active) active templates"
    }

    // MARK: Title block

    private var titleBlock: some View {
        let active = unfiltered.filter { $0.isArchived != true }.count
        let queued = unfiltered.reduce(0) { $0 + ($1.useCount ?? 0) }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Recurring loads")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · \(active) templates · \(queued) total posts")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 116)
                }
            }
            .padding(.horizontal, Space.s5)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s5)
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: 0) {
                kpiHeroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                filterRow
                    .padding(.top, Space.s5)

                if rows.isEmpty {
                    emptyOrNoMatchCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                } else {
                    VStack(spacing: Space.s4) {
                        ForEach(rows) { row in
                            templateRowView(row)
                        }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                }

                newScheduleButton
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)
            }
        }
    }

    // MARK: KPI hero card (gradient rim · 4-cell quartet)

    private var kpiHeroCard: some View {
        let templates = unfiltered.count
        let totalUses = unfiltered.reduce(0) { $0 + ($1.useCount ?? 0) }
        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("TEMPLATE PORTFOLIO · 2026")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 22)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    kpiCell(label: "TEMPLATES", value: "\(templates)", valueStyle: .gradient, trailingUnit: nil)
                    kpiDivider
                    // EUSO-2130 — queued-this-week aggregate not on API.
                    kpiCell(label: "QUEUED", value: "\(totalUses)", valueStyle: .primary, trailingUnit: "posts")
                    kpiDivider
                    // EUSO-2130 — saved-YTD aggregate not on API.
                    kpiCell(label: "SAVED YTD", value: "—", valueStyle: .primary, trailingUnit: nil)
                    kpiDivider
                    // EUSO-2129 — next-fire across portfolio not shipped.
                    kpiCell(label: "NEXT", value: "—", valueStyle: .success, trailingUnit: nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 92)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
    }

    private enum KpiValueStyle { case gradient, primary, success }

    @ViewBuilder
    private func kpiCell(label: String, value: String, valueStyle: KpiValueStyle, trailingUnit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let trailingUnit {
                    Text(trailingUnit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    // MARK: Filter row (5 chips with derived counts)

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TemplateFilter.allCases) { f in
                    filterChip(f, count: count(for: f))
                }
            }
            .padding(.horizontal, Space.s5)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for filter: TemplateFilter) -> Int? {
        switch filter {
        case .all:    return nil
        case .active: return unfiltered.filter { $0.isArchived != true }.count
        case .paused: return unfiltered.filter { $0.isArchived == true }.count
        case .daily, .weekly:
            // EUSO-2129 — cadence not on envelope.
            return nil
        }
    }

    private func filterChip(_ f: TemplateFilter, count: Int?) -> some View {
        let isActive = (store.filter == f)
        let label: String = {
            if let c = count, c > 0 { return "\(f.label) · \(c)" }
            if f == .daily || f == .weekly { return "\(f.label) · —" }
            return f.label
        }()
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: TemplateFilter) {
        store.filter = f
        NotificationCenter.default.post(
            name: .eusoShipperRecurringFilter,
            object: nil,
            userInfo: [
                "source": "221_ShipperRecurringLoads",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Template row (wireframe canon: tier rim + TPL id + status pill + lane + spec + 3-stat + countdown bar)

    @ViewBuilder
    private func templateRowView(_ t: LoadTemplatesAPI.Template) -> some View {
        let canon = canonStatus(for: t)
        Button(action: { detail = t }) {
            HStack(spacing: 0) {
                tierRimShape(canon.tier)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(rowDisplayId(t))
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(canon)
                    }
                    .padding(.top, Space.s4)

                    Text(laneTitle(t))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(specLine(t))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        statCell(value: rateValue(t), unit: "/ load")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statCell(value: t.useCount.map { "\($0)" } ?? "—", unit: "posts")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        statCell(value: t.isFavorite == true ? "★" : "—", unit: "favorite",
                                 colorOverride: t.isFavorite == true ? Brand.warning : nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Space.s2 + 2)

                    countdownBar(canon: canon)
                        .padding(.top, Space.s2 + 2)
                        .padding(.bottom, Space.s4)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(TemplateRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rowDisplayId(t)), \(canon.pillLegend), \(laneTitle(t)), \(specLine(t))")
    }

    private struct CanonStatus {
        let tier: TierRim
        let pillKind: PillKind
        let pillLegend: String
        let pillWidth: CGFloat
        enum PillKind { case active, paused, draft }
    }

    private func canonStatus(for t: LoadTemplatesAPI.Template) -> CanonStatus {
        if t.isArchived == true {
            return CanonStatus(tier: .warn, pillKind: .paused,
                               pillLegend: "PAUSED", pillWidth: 84)
        }
        return CanonStatus(tier: .gradient, pillKind: .active,
                           pillLegend: "ACTIVE", pillWidth: 84)
    }

    private func rowDisplayId(_ t: LoadTemplatesAPI.Template) -> String {
        // The iOS API ships an Int id; format as `TPL-{id}` since the
        // wireframe-canonical hex tail isn't available.
        return "TPL-\(t.id)"
    }

    private func laneTitle(_ t: LoadTemplatesAPI.Template) -> String {
        let o = locationLabel(t.origin)
        let d = locationLabel(t.destination)
        if o.isEmpty && d.isEmpty { return t.name }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    private func locationLabel(_ loc: LoadTemplatesAPI.Template.Location?) -> String {
        guard let loc else { return "" }
        let c = loc.city?.trimmingCharacters(in: .whitespaces) ?? ""
        let s = loc.state?.trimmingCharacters(in: .whitespaces) ?? ""
        if !c.isEmpty && !s.isEmpty { return "\(c), \(s)" }
        if !c.isEmpty { return c }
        if !s.isEmpty { return s }
        return ""
    }

    private func specLine(_ t: LoadTemplatesAPI.Template) -> String {
        var parts: [String] = []
        if let eq = t.equipmentType, !eq.isEmpty {
            parts.append(eq.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let cargo = t.cargoType, !cargo.isEmpty {
            parts.append(cargo.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let lu = t.lastUsedAt, !lu.isEmpty {
            parts.append("last used \(relativeShort(lu))")
        }
        // EUSO-2129 — cadence not on envelope. Note the gap inline so
        // future Diego-canon viewers see why the cadence isn't here.
        return parts.isEmpty ? "Cadence pending (EUSO-2129)" : parts.joined(separator: " · ")
    }

    private func relativeShort(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let secs = Date().timeIntervalSince(d)
        if secs < 3600 { return "\(Int(secs/60))m ago" }
        if secs < 86400 { return "\(Int(secs/3600))h ago" }
        return "\(Int(secs/86400))d ago"
    }

    private func rateValue(_ t: LoadTemplatesAPI.Template) -> String {
        guard let r = t.rate, !r.isEmpty else { return "—" }
        return "$\(r)"
    }

    @ViewBuilder
    private func statCell(value: String, unit: String, colorOverride: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(colorOverride ?? palette.textPrimary)
            Text(unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // Countdown bar — paints empty track until `nextFireAt` ships (EUSO-2129).
    @ViewBuilder
    private func countdownBar(canon: CanonStatus) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer()
                Text(canon.pillKind == .paused ? "PAUSED · NO FIRE" : "NEXT FIRE pending")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(canon.pillKind == .paused ? Brand.warning : palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private func tierRimShape(_ kind: TierRim) -> some View {
        switch kind {
        case .gradient:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .warn:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.warnGrad)
        case .paid:
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.paidGrad)
        case .neutral:
            RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func statusPillView(_ canon: CanonStatus) -> some View {
        switch canon.pillKind {
        case .active:
            Text(canon.pillLegend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: canon.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.primary))
        case .paused:
            Text(canon.pillLegend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: canon.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.warnGrad))
        case .draft:
            Text(canon.pillLegend)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textSecondary)
                .frame(width: canon.pillWidth, height: 20)
                .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        }
    }

    // MARK: New schedule CTA (§16.2 · §12.3 hand-off)

    private var newScheduleButton: some View {
        Button(action: tapNewSchedule) {
            Text("+ New recurring schedule")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a new recurring schedule")
        .accessibilityHint("Opens the recurring-schedule wizard on web via Continuity hand-off")
    }

    private func tapNewSchedule() {
        MeAction.fire("shipper.recurring.schedule")
        NotificationCenter.default.post(
            name: .eusoShipperRecurringSchedule,
            object: nil,
            userInfo: [
                "source": "221_ShipperRecurringLoads",
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Empty / error

    private var emptyOrNoMatchCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(store.filter == .all ? "No saved lanes yet" : "No matches for this filter")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(store.filter == .all
                 ? "Save a lane from PostLoad → ⋯ to repost it in one tap from here."
                 : "Try a different filter, or create a new recurring schedule below.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Press feedback

private struct TemplateRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - File-scoped paints (§19.2)

private extension LinearGradient {
    static let warnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let paidGrad = LinearGradient(
        colors: [Brand.success, Color(hex: 0x00A07B)],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Active / Paused / Daily / Weekly).
    static let eusoShipperRecurringFilter   = Notification.Name("eusoShipperRecurringFilter")
    /// "+ New recurring schedule" gradient pill tap (hands off via MeAction).
    static let eusoShipperRecurringSchedule = Notification.Name("eusoShipperRecurringSchedule")
}

// MARK: - Detail sheet (preserved)

struct ShipperRecurringLoadDetail: View {
    let template: LoadTemplatesAPI.Template
    @EnvironmentObject private var store: ShipperRecurringLoadsStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fields
                actions
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE TEMPLATE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(template.name)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                if template.isFavorite == true {
                    miniPill("FAVORITE", color: Brand.warning)
                }
                if template.isArchived == true {
                    miniPill("PAUSED", color: Brand.warning)
                }
                if let count = template.useCount, count > 0 {
                    miniPill("\(count) POSTS", color: nil)
                }
            }
            if let d = template.description, !d.isEmpty {
                Text(d).font(EType.body).foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(
            colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Origin", "\(template.origin?.city ?? "—") · \(template.origin?.state ?? "—")")
            row("Destination", "\(template.destination?.city ?? "—") · \(template.destination?.state ?? "—")")
            if let d = template.distance { row("Distance", "\(d) mi") }
            if let c = template.commodity { row("Commodity", c) }
            if let c = template.cargoType { row("Cargo type", c) }
            if let e = template.equipmentType { row("Equipment", e.replacingOccurrences(of: "_", with: " ")) }
            if let t = template.trailerType { row("Trailer", t) }
            if let w = template.weight { row("Weight", "\(w) \(template.weightUnit ?? "lb")") }
            if let q = template.quantity { row("Quantity", "\(q) \(template.quantityUnit ?? "")") }
            if let h = template.hazmatClass { row("Hazmat class", h) }
            if let u = template.unNumber { row("UN #", u) }
            if let r = template.rate { row("Saved rate", "$\(r)") }
            if let lu = template.lastUsedAt { row("Last used", relative(lu)) }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary).frame(width: 110, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await store.post(template: template)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if store.posting.contains(template.id) {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .heavy))
                    }
                    Text(store.posting.contains(template.id) ? "Posting…" : "Post this lane now")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.posting.contains(template.id))

            Button {
                MeAction.fire("shipper.recurring.schedule", userInfo: ["templateId": template.id])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 12, weight: .heavy))
                    Text("Schedule recurring on web").font(.system(size: 12, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .foregroundStyle(palette.textPrimary).background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func miniPill(_ s: String, color: Color?) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color ?? palette.textTertiary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(palette.bgCardSoft.opacity(0.6)))
            .overlay(Capsule().strokeBorder((color ?? palette.borderFaint).opacity(0.5)))
    }

    private func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let secs = Date().timeIntervalSince(d)
        if secs < 3600 { return "\(Int(secs/60)) min ago" }
        if secs < 86400 { return "\(Int(secs/3600)) h ago" }
        return "\(Int(secs/86400)) d ago"
    }
}

// MARK: - Previews

#Preview("221 · Recurring · Dark") {
    ShipperRecurringLoads()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("221 · Recurring · Light") {
    ShipperRecurringLoads()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
