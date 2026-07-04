//
//  700_TerminalHome.swift
//  EusoTrip — Terminal · Home (brick 700).
//
//  First brick on the Terminal Manager role track (700s). Replaces
//  the `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.terminal`. Direct mirror of
//  `Views/Escort/600_EscortHome.swift` (103rd firing) and
//  `Views/Catalyst/500_CatalystHome.swift` (102nd) and Broker/Carrier/
//  Shipper home anchors.
//
//  Terminal Manager owns the port/yard ops surface — gate-in/gate-out
//  flow, container movements between staging/dock/rail spur, dock
//  assignment + dwell + demurrage exposure, and hazmat clearance per
//  the §16 admin-tenant-ops + intermodal-xborder + compliance-safety
//  slices. The home re-frames the four-card hierarchy around movement
//  flow + dwell rather than match flow / corridor coverage / tender
//  flow.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §4 (tokenized spacing / radius / type),
//  §5 (palette semantic only, no hard-coded `Color.white` /
//  `Color.black` / `Color.gray` fills), §3 (`AnyShapeStyle` wrapping
//  for ternary shape-styles), §10 (previews compile in isolation).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data, plugged
//  into backend"):
//
//    • KPI strip → `terminals.getDashboardStats` via
//      `TerminalHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: activeMovements,
//      completedThisWeek, avgDwellHoursThisWeek, throughputThisWeek,
//      onTimeRate, gateUtilization. Backend convention mirrors
//      `escorts.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `terminals.getMovementsRequiringAttention` via
//      `TerminalAlertsStore`. Empty until the terminal exception
//      engine flags a dwell breach, demurrage exposure, dock
//      conflict, hazmat clearance pending, BOL mismatch, ISF 10+2
//      hold, or appointment drift.
//    • "Active movements" feed → `terminals.getActiveMovements`
//      via `TerminalActiveMovementsStore`.
//    • "Recent activity" feed → `terminals.getRecentMovements` via
//      `TerminalRecentMovementsStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `terminals.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Facility-locator data model
//
// Real coordinates for the home's facility-locator map come from
// `yardManagement.getYardLocations` → `locations[].lat/lng`, which the
// server projects VERBATIM from `facilities.latitude/longitude` and
// `terminals.latitude/longitude` (yardManagement.ts:274,297,316-317,
// 328-329 — `Number(f.lat) || 0`). This is the SAME router the role
// already calls (`yardManagement.moveTrailer` fires from 702), so it is
// in-scope here. The iOS `terminals.*` envelopes carry NO lat/lng, so
// this is the only real coordinate path for the Terminal role — and it
// was not yet wired into any iOS Terminal store. Mirrors the canonical
// `YardLocation628` consumer (Rail 628_RailYardMap).

/// One terminal facility / yard from `yardManagement.getYardLocations`.
/// `lat`/`lng` are the REAL facility/terminal coordinates the server
/// projects; `0,0` is the server's missing-coordinate sentinel and is
/// null-island-gated out before any pin is drawn.
private struct TerminalYardLocation700: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let address: String?
    let type: String?
    let capacity: Int?
    let dockDoors: Int?
    let status: String?
    let lat: Double?
    let lng: Double?
}

/// `getYardLocations` envelope. Server: `{ locations, total }`.
private struct TerminalYardLocations700: Decodable {
    let locations: [TerminalYardLocation700]?
    let total: Int?
}

/// Tiny string-backed error so the facility-locator card can route a
/// fetch failure through the shared `inlineError` retry surface.
private struct TerminalYardLoadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Screen root

struct TerminalHome: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = TerminalHomeDashboardStore()
    @StateObject private var alerts    = TerminalAlertsStore()
    @StateObject private var movements = TerminalActiveMovementsStore()
    @StateObject private var recent    = TerminalRecentMovementsStore()

    /// Whether the 701_TerminalGateQueue detail sheet is currently
    /// presenting. Wired in the 150th eusotrip-killers firing alongside
    /// the 701 brick — the active-movements section header now opens
    /// the deep gate-queue surface where each row gets an inline
    /// "Assign dock" CTA. This brings Terminal to two-screen depth,
    /// parity with Escort 600 → 601.
    @State private var gateQueueOpen: Bool = false

    /// Whether the 702_TerminalYardMap detail sheet is currently
    /// presenting. Wired in the 154th eusotrip-killers firing alongside
    /// the 702 brick — the KPI strip's "View yard →" CTA opens the
    /// full yard map. This brings Terminal to three-screen depth,
    /// honoring the user's "every screen each role at a time" cadence
    /// (700 home → 701 gate-queue detail → 702 yard-map detail).
    @State private var yardMapOpen: Bool = false

    // ── Facility-locator map state ──
    //
    // The highest-value missing map in the Terminal role: a geographic
    // overview of the operator's own yards/docks pinned on the in-house
    // HERE map. Fed by `yardManagement.getYardLocations` (real
    // facility/terminal lat/lng). Honest seam: until rows carry real
    // coordinates the card renders an "awaiting yard coordinates" empty
    // state — never a fabricated pin. Tapping a pin opens the existing
    // 702 yard-map drill-in.
    @State private var yardLocations: [TerminalYardLocation700] = []
    @State private var yardLocationsLoading: Bool = true
    @State private var yardLocationsError: String? = nil
    @State private var selectedYardId: String? = nil

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "terminal.home.widgetOrder"
    private let terminalCanonicalOrder: [String] = ["activeMovements", "throughput_summary", "terminal_alerts", "recent", "news"]

    private func terminalHomeRender(_ id: String) -> AnyView {
        switch id {
        case "activeMovements":    AnyView(activeMovementsCard)
        case "throughput_summary": AnyView(throughputSummaryWidget)
        case "terminal_alerts":    AnyView(terminalAlertsWidget)
        case "recent":             AnyView(recentActivityCard)
        case "news":               AnyView(NewsCarouselWidget())
        default:                   AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // First-load unlock cascade: top-level sections spring in
            // top-to-bottom (scale 0.92 + blur 5pt + 50 ms stagger) once
            // per cold launch; settled on re-visit. Reduce-Motion → fade.
            StaggeredEntranceStack(alignment: .leading, spacing: Space.s4) {
                header
                HomeWeatherWidget()
                kpiStrip
                facilityLocatorCard
                attentionStrip
                HomeWidgetGrid(
                    canonicalOrder: terminalCanonicalOrder,
                    role: "TERMINAL_MANAGER",
                    storageKey: widgetLayoutKey,
                    render: { id in terminalHomeRender(id) }
                )
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
        // 701_TerminalGateQueue sheet — opened by tapping the
        // "View queue →" CTA on the active-movements section header.
        // Detents `[.large]` + drag indicator mirrors the established
        // Driver-Me sub-route + Escort 601 sheet doctrine.
        .sheet(isPresented: $gateQueueOpen) {
            TerminalGateQueueScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 702_TerminalYardMap sheet — opened by tapping the trailing
        // "View yard →" header CTA on the home. Detents `[.large]` +
        // drag indicator matches the 701 doctrine so the two Terminal
        // detail surfaces feel structurally identical.
        .sheet(isPresented: $yardMapOpen) {
            TerminalYardMapScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = movements.refresh()
        async let d: Void = recent.refresh()
        async let e: Void = reloadYardLocations()
        _ = await (a, b, c, d, e)
    }

    /// Load the operator's facilities/yards (with real lat/lng) from
    /// `yardManagement.getYardLocations`. No fabrication: on any failure
    /// the card surfaces an honest error/retry state. Same router the
    /// role already calls from 702.
    private func reloadYardLocations() async {
        yardLocationsLoading = true
        yardLocationsError = nil
        struct LocsIn: Encodable { let status: String }
        do {
            let envelope: TerminalYardLocations700 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardLocations", input: LocsIn(status: "active"))
            let list = envelope.locations ?? []
            self.yardLocations = list
            if selectedYardId == nil { selectedYardId = mappableYards.first?.id }
        } catch {
            self.yardLocationsError =
                (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        yardLocationsLoading = false
    }

    // MARK: - Header
    //
    // Bespoke hero — matches the gold-standard Driver-010 idiom: a
    // gradient eyebrow chip ("✦ TERMINAL · DASHBOARD") with the
    // time-of-day · context caps trailing on the right (per the SVG
    // header motif, sparkle glyph used exactly once per surface), then
    // the identity headline rendered in the brand gradient so the
    // role homes read as one family in both Night and Afternoon.
    // Every prior element is preserved — building glyph, headline,
    // subhead — only the styling rhythm is elevated.

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Bespoke eyebrow row — gradient role chip + tertiary
            // time-of-day · live-count, mirroring the Dark-SVG header
            // and the Driver-010 / Shipper-200 idiom.
            HStack {
                Text("✦ TERMINAL · DASHBOARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text(eyebrowContext)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            headerRow
        }
        .padding(.top, 4)
    }

    /// Greeting + building glyph row. Split out of `header` so the new
    /// bespoke eyebrow can sit above it without exploding the type-check
    /// budget on one giant view literal (mirrors DriverHome's headerRow).
    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(LinearGradient.diagonal.opacity(0.12))
                )
                .overlay(Circle().strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(subhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// Time-of-day greeting (caps) paired with the live in-yard count so
    /// the eyebrow right rail reads as live context, never a placeholder.
    private var eyebrowContext: String {
        let tod = timeOfDayGreeting.uppercased()
        if let outer = dashboard.state.value, let s = outer {
            return "\(tod) · \(s.activeMovements) IN YARD"
        }
        return "\(tod) · TERMINAL OPS"
    }

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    /// Identity-aware headline. Falls back to the role label so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "On the yard, \(name)"
        }
        return "Terminal · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let live = s.activeMovements
            let week = s.completedThisWeek
            return "\(live) live movement\(live == 1 ? "" : "s") · \(week) gated out · 7d"
        }
        return "Loading yard fabric…"
    }

    // MARK: - KPI strip

    @ViewBuilder
    private var kpiStrip: some View {
        switch dashboard.state {
        case .loading:
            kpiSkeleton
        case .loaded(let maybe):
            if let s = maybe {
                VStack(alignment: .leading, spacing: Space.s2) {
                    kpiGrid(s)
                    yardMapCTA
                }
            } else {
                EusoEmptyState(
                    systemImage: "chart.bar",
                    title: "No KPIs yet",
                    subtitle: "Once your first truck or container clears the gate, the dashboard will populate the moment the yard opens."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Once your first truck or container clears the gate, the dashboard will populate the moment the yard opens."
            )
        case .error(let e):
            inlineError(e) { Task { await dashboard.refresh() } }
        }
    }

    /// "View yard map →" drill-in CTA. Wired in the 154th eusotrip-killers
    /// firing — opens the 702_TerminalYardMap sheet so the operator can
    /// see slot-level occupancy and release slots directly. Mirrors the
    /// 701 "View queue →" CTA pattern: gradient text, plain button,
    /// no decorative chrome.
    private var yardMapCTA: some View {
        HStack {
            Spacer()
            Button { yardMapOpen = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("View yard map")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var kpiSkeleton: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func kpiGrid(_ s: TerminalAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            kpiTile(label: "ACTIVE MOVEMENTS", value: "\(s.activeMovements)",          sub: "in-yard")
            kpiTile(label: "GATED OUT · 7D",   value: "\(s.completedThisWeek)",        sub: "movements resolved")
            kpiTile(label: "AVG DWELL · 7D",   value: dwell(s.avgDwellHoursThisWeek),  sub: "yard residency")
            kpiTile(label: "THROUGHPUT · 7D",  value: "\(s.throughputThisWeek)",       sub: "events processed")
        }
    }

    private func kpiTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        // Bespoke iridescent-rim + glow surface — replaces the flat
        // bgCard + strokeBorder + clipShape stack so the KPI tiles read
        // as first-class cards matching the SVG card language.
        .eusoCard(radius: Radius.lg)
    }

    /// Format dwell hours as a one-decimal label. Returns "-" for
    /// zero so the empty case never renders as "0.0 hr".
    private func dwell(_ v: Double) -> String {
        guard v > 0 else { return "-" }
        return String(format: "%.1f hr", v)
    }

    /// Format a utilization ratio (0.0…1.0) as a percentage rounded
    /// to whole digits. Returns "-" for zero so the empty case
    /// never renders as "0%".
    private func utilization(_ v: Double) -> String {
        guard v > 0 else { return "-" }
        return "\(Int((v * 100).rounded()))%"
    }

    // MARK: - Facility-locator map
    //
    // A geographic overview of the operator's own yards/docks pinned on
    // the in-house HERE map (`BespokeMapCanvas`). Each real yard footprint
    // is a translucent `.adZones` polygon (mirrors Driver 022 DockAssigned
    // `yardLayoutPolygons -> .adZones` + Rail 628), with a pin per yard.
    // Tapping a pin opens the existing 702 yard-map drill-in. Terminal is a
    // flat ops board → standard register (tilt: 0, style: .auto).

    /// Yards with REAL server-projected coordinates (lat/lng ≠ 0,0).
    /// Null-island guard — never render a fabricated pin.
    private var mappableYards: [TerminalYardLocation700] {
        yardLocations.filter { y in
            guard let la = y.lat, let lo = y.lng else { return false }
            return !(la == 0 && lo == 0)
        }
    }

    @ViewBuilder
    private var facilityLocatorCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FACILITY LOCATOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !mappableYards.isEmpty {
                    Text("\(mappableYards.count) yard\(mappableYards.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if yardLocationsLoading {
                facilityLocatorSkeleton
            } else if let err = yardLocationsError {
                inlineError(TerminalYardLoadError(message: err)) {
                    Task { await reloadYardLocations() }
                }
            } else if mappableYards.isEmpty {
                // Honest seam — the proc returned no geocoded yards yet.
                // No fabricated pins; the map lights up the moment a
                // facility/terminal row carries real lat/lng.
                EusoEmptyState(
                    systemImage: "mappin.slash",
                    title: "Awaiting yard coordinates",
                    subtitle: "Your facilities will appear on the map here as soon as their geographic coordinates are on file. Tap a yard pin to open its gate queue and yard."
                )
            } else {
                facilityLocatorMap
            }
        }
    }

    private var facilityLocatorMap: some View {
        let yards = mappableYards
        return BespokeMapCanvas(
            center: yardMapCenter,
            zoom: yardMapZoom,
            interactive: true,
            tilt: 0,
            isDark: colorScheme == .dark,
            layers: [
                .adZones(yards.map(yardFootprint(for:))),
                .markers(yards.map { y in
                    HereMarker(
                        at: HereLatLng(y.lat ?? 0, y.lng ?? 0),
                        kind: .pickup,
                        label: y.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Yard",
                        id: y.id)
                })
            ],
            onSelectMarker: { yardId in
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedYardId = yardId
                }
                // Drill into the tapped yard's full yard-map / gate surface.
                yardMapOpen = true
            }
        )
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var facilityLocatorSkeleton: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
    }

    /// Camera center = centroid of the real yard coordinates (no fabrication).
    /// The CONUS fallback (39.5, -98.35) is the only acceptable coordinate
    /// literal and is never reached while `mappableYards` is non-empty.
    private var yardMapCenter: HereLatLng {
        let yards = mappableYards
        guard !yards.isEmpty else { return HereLatLng(39.5, -98.35) }
        let lat = yards.reduce(0.0) { $0 + ($1.lat ?? 0) } / Double(yards.count)
        let lng = yards.reduce(0.0) { $0 + ($1.lng ?? 0) } / Double(yards.count)
        return HereLatLng(lat, lng)
    }

    /// Tight framing for a single yard; wider when the network spans out.
    private var yardMapZoom: Int { mappableYards.count <= 1 ? 13 : 8 }

    /// Honest ~250 m footprint box around each yard's real coordinate — the
    /// server projects a point, not a GeoJSON ring, so we draw a square
    /// footprint around the true location. Mirrors the `.adZones` contract
    /// used by Driver 022's `yardLayoutPolygons` + Rail 628.
    private func yardFootprint(for y: TerminalYardLocation700) -> HerePolygon {
        let lat = y.lat ?? 0
        let lng = y.lng ?? 0
        let dLat = 0.0022
        let dLng = 0.0022 / max(cos(lat * .pi / 180), 0.2)
        let ring = [
            HereLatLng(lat + dLat, lng - dLng),
            HereLatLng(lat + dLat, lng + dLng),
            HereLatLng(lat - dLat, lng + dLng),
            HereLatLng(lat - dLat, lng - dLng),
        ]
        let isSelected = (selectedYardId ?? mappableYards.first?.id) == y.id
        return HerePolygon(
            ring: ring,
            fillHex: "#1473FF",
            opacity: isSelected ? 0.30 : 0.16,
            label: y.name.flatMap { $0.isEmpty ? nil : $0 })
    }

    // MARK: - Attention strip

    @ViewBuilder
    private var attentionStrip: some View {
        switch alerts.state {
        case .loading:
            EmptyView()
        case .empty:
            // Don't render anything — silence is the right empty state
            // for an alert feed (empty == nothing's wrong).
            EmptyView()
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("NEEDS YOUR ATTENTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                ForEach(rows) { row in
                    alertRow(row)
                }
            }
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    private func alertRow(_ row: TerminalAPI.MovementAlert) -> some View {
        let severityColor: Color = {
            switch row.severity.lowercased() {
            case "critical":  return Brand.danger
            case "warning":   return Brand.warning
            default:          return palette.textTertiary
            }
        }()
        return HStack(spacing: Space.s3) {
            Circle()
                .fill(AnyShapeStyle(severityColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(row.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(row.issue.uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(severityColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(severityColor.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        // Bespoke nested-row surface — iridescent whisper rim, no
        // compounding glow inside the already-carded section.
        .eusoRow(radius: Radius.md)
    }

    // MARK: - Active movements

    @ViewBuilder
    private var activeMovementsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ACTIVE MOVEMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = movements.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                // 150th firing — tap opens 701_TerminalGateQueue sheet
                // for the deep queue + per-row "Assign dock" mutation.
                Button { gateQueueOpen = true } label: {
                    HStack(spacing: 4) {
                        Text("View queue")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(LinearGradient.diagonal)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                .buttonStyle(.plain)
            }
            switch movements.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { movementRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No live movements",
                    subtitle: "When a truck or container clears the gate you'll see the dock assignment and dwell here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await movements.refresh() } }
            }
        }
    }

    private func movementRow(_ row: TerminalAPI.ActiveMovement) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.stage.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("arrived \(row.arrivedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.dockAssignment.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("Dock \(row.dockAssignment)")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
                if row.dwellHours > 0 {
                    Text(dwell(row.dwellHours))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("dwell")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        // Bespoke nested-row surface — iridescent whisper rim.
        .eusoRow(radius: Radius.md)
    }

    // MARK: - Recent activity

    @ViewBuilder
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch recent.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { recentRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "clock",
                    title: "No recent activity",
                    subtitle: "Once a movement gates out or a container resolves, it'll show up here with the lane and final dwell."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: TerminalAPI.RecentMovement) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if row.finalDwellHours > 0 {
                    Text(dwell(row.finalDwellHours))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                if !row.resolvedAt.isEmpty {
                    Text(row.resolvedAt)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        // Bespoke nested-row surface — iridescent whisper rim.
        .eusoRow(radius: Radius.md)
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    // MARK: - Throughput summary widget

    @ViewBuilder
    private var throughputSummaryWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("THROUGHPUT SUMMARY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch dashboard.state {
            case .loading:
                listSkeleton
            case .loaded(let maybe):
                if let s = maybe {
                    HStack(spacing: Space.s2) {
                        kpiTile(label: "THROUGHPUT · 7D", value: "\(s.throughputThisWeek)", sub: "movements this week")
                        kpiTile(label: "GATE UTIL",       value: String(format: "%.0f%%", s.gateUtilization * 100), sub: "gate utilization")
                        kpiTile(label: "AVG DWELL",       value: String(format: "%.1fh", s.avgDwellHoursThisWeek), sub: "avg dwell · 7d")
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "gauge.with.dots.needle.33percent", title: "No throughput data",
                               subtitle: "Complete a movement and this week's metrics will appear here.")
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    // MARK: - Terminal alerts widget

    @ViewBuilder
    private var terminalAlertsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("TERMINAL ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = alerts.state, !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.danger))
                }
            }
            switch alerts.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                                   subtitle: "No movements need attention right now.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { alertRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                               subtitle: "No movements need attention right now.")
            case .error(let e):
                inlineError(e) { Task { await alerts.refresh() } }
            }
        }
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load this card")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(error.eusoUserCopy)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Screen wrapper

struct TerminalHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TerminalHome()
        } nav: {
            BottomNav(
                leading: terminalNavLeading_700(),
                trailing: terminalNavTrailing_700(),
                orbState: .idle
            )
        }
    }
}

private func terminalNavLeading_700() -> [NavSlot] {
    [NavSlot(label: "Home",      systemImage: "house.fill",      isCurrent: true),
     NavSlot(label: "Movements", systemImage: "shippingbox.fill", isCurrent: false)]
}

private func terminalNavTrailing_700() -> [NavSlot] {
    [NavSlot(label: "Yard", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",   systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("700 · Terminal · Home · Night") {
    TerminalHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("700 · Terminal · Home · Afternoon") {
    TerminalHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
