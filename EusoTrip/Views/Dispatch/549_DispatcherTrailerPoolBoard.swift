//
//  549_DispatcherTrailerPoolBoard.swift
//  EusoTrip 2027 · 04 Dispatcher · CATALOG 549 "Dispatcher Trailer Pool Board"
//  (DISPATCHER vantage · Aurora · RM)
//
//  MIRRORS: "04 Dispatcher/Light-SVG/549 Dispatcher Trailer Pool Board.svg"
//  (+ Dark). DETAIL TopBar -> PHYSICAL INVENTORY STRIP hero (every trailer drawn
//  as an individual equipment chip coloured by state, so the dispatcher counts
//  real boxes rather than reading an aggregate) + legend row -> SITE LEDGER
//  (every site row leads with the mandatory 40x40 rx10 icon chip carrying a dock
//  glyph, with the title and mono terms sub-line indented after it) -> ESang row
//  -> CTA pair. Empty trailers are the asset that goes missing quietly.
//  Deliberately unlike 406 Yard Slots (single-yard slot grid), 544 Demand Map
//  (market heat), 536 Fleet Map (map hero), 545 Maintenance Due (depletion).
//
//  ── DESIGN-SYSTEM PORT 2026-08-26 ────────────────────────────────────────
//  Raw/system colors replaced by the EusoTrip design system: Theme.Palette
//  through @Environment(\.palette), Brand.*, LinearGradient.primary /
//  .diagonal, IridescentHairline, Space.* and Radius.* tokens, Shell +
//  BottomNav chrome via the house `ShellNav` idiom (see
//  Dpch730_DispatcherOpsQuartet.swift, matched by the batch sibling
//  546_DispatcherShiftHandover.swift). THE DATA LAYER IS UNCHANGED — every
//  endpoint string, decoder shape, error branch and `.disabled(...)` gate below
//  is byte-for-byte the behavior that was endpoint-verified on 2026-08-17.
//
//  ── WIRED READS (every line number re-verified on disk 2026-08-17) ────────
//    yardManagement.getTrailerPool       EXISTS yardManagement.ts:1046
//        -> the chip strip + the legend counts. Returns {trailers, summary},
//           NOT a bare array.
//    yardManagement.getDetentionTracking EXISTS yardManagement.ts:2083
//        -> the hero figures. `summary.activeDetentions` is the real count of
//           boxes past free time and `summary.totalAccruedCharges` is the real
//           dwell exposure. Both were literals before the 2026-08-17 rebuild.
//    yardManagement.getYardLocations     EXISTS yardManagement.ts:281
//        -> the site rows: real name, address, type, capacity, dockDoors, status.
//    equipment.list                      EXISTS equipment.ts:33
//        -> the fleet-wide equipment count on the net line.
//    equipment.getUtilization            EXISTS equipment.ts:185
//        -> `overall.utilizationRate` on the net line. NOTE: the rest of this
//           procedure is hollow server-side — `byEquipment` is always [] and
//           every field of `costAnalysis` is always 0 — so ONLY
//           `overall.utilizationRate` is read. Counter-party row filed.
//    users.me                            EXISTS users.ts:99
//        -> the yard-ops grant, which this file once hardcoded to `true`. There
//           is NO permission-introspection endpoint a dispatcher may call (the
//           whole rbacAdmin router is admin-gated), so the grant is derived from
//           the caller's real `role` against the exact role set that
//           `yardOpsProcedure` requires. See the RBAC note below.
//
//  ── WIRED READ ON TAP ────────────────────────────────────────────────────
//    yardManagement.getTrailerDetails    EXISTS yardManagement.ts:1162
//        -> a chip tap. Returns NULL on four paths — decoded as Optional.
//
//  ── HONEST GAP 1 · assetInterchange.getOpenInterchanges DOES NOT EXIST ────
//    Re-confirmed absent 2026-08-17: a repo-wide search of frontend/server for
//    `assetInterchange` / `getOpenInterchanges` returns NO match. The
//    "Interchange" CTA is therefore `.disabled` with its reason printed beneath
//    the CTA pair — never a dead tap. Proposed shape, filed to the Catalyst
//    queue and NOT built in this lane:
//      assetInterchange.getOpenInterchanges: protectedProcedure
//        .input(z.object({ companyId: z.string() }))
//        .query(): Array<{ interchangeId: string; trailerId: string;
//          counterpartyCompanyId: string; direction: 'in'|'out';
//          openedAt: string; expectedReturnAt: string | null }>
//
//  ── HONEST GAP 2 · THE PER-SITE HAVE-vs-NEED BAR IS SUPPRESSED ───────────
//    THE SERVER RETURNS CONSTANTS WHERE THE BAR NEEDS DATA, so the bar is not
//    drawn. Two independent reasons, both on disk today:
//      (a) getYardLocations returns `occupied` as a HARDCODED 0 for every site
//          (yardManagement.ts:348 — the source comment admits it), so
//          capacity − occupied would report every site in surplus by its full
//          capacity. That is not a deficit board, it is a fabrication.
//      (b) getTrailerPool returns `locationId` as the HARDCODED string "LOC-1"
//          for every trailer (and `spotId` fabricated from the array index), so
//          the pool cannot be grouped by site either.
//    Drawing a ± bar off either would invent the exact number the screen exists
//    to report. The row chrome, the 40x40 icon chip, the dashed centre axis and
//    the ledger geometry are all preserved; where the fabricated ±delta stood,
//    the row prints the site's REAL capacity and dock-door count, and the ledger
//    carries one stated line explaining the suppression.
//    Proposed server shape, filed and NOT built in this lane: give
//    getYardLocations a real `occupied` (count of vehicles whose current yard
//    location is that site) and getTrailerPool the trailer's real `locationId`,
//    so have-vs-need becomes computable. Until then this board reports inventory
//    and detention truthfully and reports nothing about per-site balance.
//
//  ── HONEST GAP 3 · THE DISPATCH_BOARD_UPDATE LISTENER ────────────────────
//    CHAIN: OPEN (S3, the deaf console). Views/Dispatch observes realtime in 1
//    of 47 files, so a trailer another desk moves does not repaint this board
//    and two dispatchers can promise the same empty. Counter-party row filed;
//    this lane does not touch the repos.
//      // shared/websocket-events.ts:205  DISPATCH_BOARD_UPDATE: 'dispatch:board_update'
//      // payload: { companyId, trailerId, fromSiteId, toSiteId, state,
//      //            movedAt, movedByUserId }
//
//  ── HONEST RE-SOURCING (composition preserved, provenance corrected) ──────
//  1. CHIP STATES. The original literal legend was loaded / empty / at customer /
//     stranded. The server cannot produce two of those: `mapVehicleStatusToYard`
//     (yardManagement.ts:65) only ever emits available | loaded | in_repair |
//     empty — "at customer" and "stranded" are not reachable values. The legend
//     names the four states the server actually returns. Same four palette
//     slots, same opacities, same grid: only the labels tell the truth now.
//  2. THE HERO. "12 stranded / $4,320" were literals. They are now
//     `getDetentionTracking.summary.activeDetentions` and `.totalAccruedCharges`.
//
//  ── CITED BUT DELIBERATELY NOT CALLED (each with its reason) ──────────────
//    yardManagement.moveTrailer     EXISTS yardManagement.ts:440 (yardOpsProcedure)
//    yardManagement.assignTrailer   EXISTS yardManagement.ts:1214
//      NOT WIRED. `moveTrailer` requires {trailerId, toSpot, locationId} — a
//      DESTINATION SPOT this composition never collects; there is no spot picker
//      on 549. Committing a custody move to a spot the client invented is worse
//      than not committing one. The primary CTA therefore BUILDS the plan from
//      real reads (which boxes are past free time, which sites have open doors)
//      and says what committing it would need. `assignTrailer` is additionally
//      flagged for the counter-party row: when `db` is falsy or the id parses to
//      0 it returns `success: true` WITHOUT WRITING — a false success path.
//    yardManagement.checkInTrailer  EXISTS yardManagement.ts:848
//    yardManagement.checkOutTrailer EXISTS yardManagement.ts:922
//      NOT WIRED. This composition has no gate-event control; 406 Yard Slots
//      owns the gate. Kept in the manifest as verified.
//    yardManagement.getDropYardOperations EXISTS yardManagement.ts:1718
//      NOT WIRED. Its resolver destructures only `{ ctx }` (yardManagement.ts:1720)
//      so its `locationId` input is a NO-OP, its `status` is the literal
//      "dropped" for every row, and `sealIntact` is always true — it cannot
//      distinguish drop-and-hook readiness per site, which is the only thing
//      this screen would have wanted it for. Counter-party row filed.
//    tracking.getRealtimePositions  EXISTS tracking.ts:878
//    tracking.getGeofenceEvents     EXISTS tracking.ts:465
//      NOT WIRED. Position reconciliation is moot while every trailer reports
//      the hardcoded "LOC-1", and the free-time clocks are already carried
//      truthfully by getDetentionTracking. Kept in the manifest as verified.
//    esangCoach.forScreen           EXISTS esangCoach.ts:264
//      NOT CALLABLE FROM ANY DISPATCHER SCREEN. Its `screen` input is
//      SCREEN_ENUM (esangCoach.ts:112-125) = home | trips | earnings | tax |
//      dvir | availability | missions | badges | referrals | zeun | haul |
//      active-trip — every member a DRIVER surface. Any call from here fails zod
//      validation with BAD_REQUEST. The ESang row is a Button in this
//      composition, so it is `.disabled` and states why rather than being a dead
//      tap; its text is derived from this screen's own live reads.
//      Counter-party row filed: add a dispatch token to SCREEN_ENUM.
//
//  RBAC: `yardOpsProcedure` is defined at yardManagement.ts:19-21 as
//    roleProcedure(ROLES.TERMINAL_MANAGER, ROLES.DISPATCH, ROLES.ADMIN,
//    ROLES.SUPER_ADMIN) — enforced by roleGuard (_core/trpc.ts:169). Only
//    moveTrailer uses it; every other procedure on this screen is
//    protectedProcedure, company-scoped. There is no `canMoveTrailer` probe, so
//    `hasYardOpsGrant` is derived from users.me `role` against that exact set,
//    and a FORBIDDEN would still have to be surfaced at call time.
//  OFFLINE POLICY: READ_CACHED(120s) for the pool and yard reads; this surface
//    performs no writes; no money movement.
//  transportMode=truck; country US (per-state free-time terms, USD).
//  NAV (REAL · DispatchNavRoute / DispatchNavDispatcher,
//    DispatchNavController.swift:44/99): Home(house) · Board(
//    rectangle.split.3x1.fill · current) · [orb] ·
//    Comms(bubble.left.and.bubble.right.fill) · Me(person) — rendered by the
//    house `Shell` + `BottomNav` chrome, not by screen-owned nav.
//  Persona Aurora Freight Lines · Renée Marquette (RM); shipper-of-record
//  Eusorone Technologies (Diego Usoro · DU).
//
//  HONEST STATUS: 6 reads + 1 tap-read live · 2 named gaps disabled with their
//  reasons on screen · 1 measurement (per-site have-vs-need) UNSOURCEABLE and
//  suppressed with its reason on screen · 7 verified procedures deliberately
//  unwired with reasons · 5 server-side hardcodes surfaced. No literal row
//  arrays. No stubs, no placeholder literals, no invented fallbacks.
//  No retired names. No emoji icons. Exactly one ✦ eyebrow.
//  Exactly one iridescent hairline; six iridescent elements in total.
//  — Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - WCAG text pair for tinted washes
//
// These are the WCAG-contrast-tested TEXT partners for small type sitting on a
// `palette.tint*` wash — the Palette ships the washes but no matching text
// token, and Brand.danger / Brand.warning / Brand.success are the WASH hues
// (too light for 11–14pt type on a white surface), so they cannot be
// substituted here without dropping small-text contrast on light surfaces.
// (The house set's fourth member, #1565C0 — the info partner — has no call-site
// on 549 and is deliberately not declared rather than shipped as dead code.)

/// #D2342A — WCAG text partner for `palette.tintDanger`.
private let poolDangerText_549  = Color(red: 0.824, green: 0.204, blue: 0.165)
/// #B27300 — WCAG text partner for `palette.tintWarning`.
private let poolWarnText_549    = Color(red: 0.698, green: 0.451, blue: 0.0)
/// #00966B — WCAG text partner for `palette.tintSuccess`.
private let poolSuccessText_549 = Color(red: 0.0,   green: 0.588, blue: 0.420)

// MARK: - House chrome wrapper (idiom copied from Dpch730_DispatcherOpsQuartet)

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire decoders (shapes copied from the server's own return statements)

/// Explicit null-tolerant box. getTrailerDetails returns `null` on four
/// separate paths, and relying on `Optional` as the generic `Output` of a tRPC
/// envelope is fragile — a JSON `null` in that position can surface as
/// `valueNotFound` rather than `.none`. This decodes the null case openly.
private struct Nullable_549<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : try c.decode(T.self)
    }
}

/// yardManagement.getTrailerPool — yardManagement.ts:1046. Envelope, not an array.
private struct TrailerPool_549: Decodable {
    let trailers: [PoolTrailer_549]
    let summary: PoolSummary_549?
}

private struct PoolTrailer_549: Decodable {
    let id: String?
    let trailerNumber: String?
    let type: String?
    /// Only ever available | loaded | in_repair | empty (yardManagement.ts:65).
    let status: String?
    let condition: String?
    let make: String?
    let year: Int?
    let lastMoveTime: String?
    let loadId: String?
}

private struct PoolSummary_549: Decodable {
    let total: Int?
    let available: Int?
    let loaded: Int?
    let empty: Int?
    let inRepair: Int?
    let reserved: Int?
}

/// yardManagement.getDetentionTracking — yardManagement.ts:2083.
private struct Detention_549: Decodable {
    let summary: DetentionSummary_549?
}

private struct DetentionSummary_549: Decodable {
    let activeDetentions: Int?
    let totalAccruedCharges: Double?
    let avgDetentionHours: Double?
    let criticalCount: Int?
}

/// yardManagement.getYardLocations — yardManagement.ts:281.
private struct YardLocations_549: Decodable {
    let locations: [YardLocation_549]
    let total: Int?
}

private struct YardLocation_549: Decodable {
    let id: String?
    let name: String?
    let address: String?
    let type: String?
    let capacity: Int?
    /// HARDCODED 0 server-side (yardManagement.ts:348). Never used to derive a bar.
    let occupied: Int?
    let dockDoors: Int?
    let status: String?
}

/// equipment.list — equipment.ts:33.
private struct EquipmentList_549: Decodable {
    let total: Int?
    let summary: EquipmentSummary_549?
}

private struct EquipmentSummary_549: Decodable {
    let total: Int?
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
}

/// equipment.getUtilization — equipment.ts:185. Only `overall` is real.
private struct Utilization_549: Decodable {
    let overall: UtilizationOverall_549?
}

private struct UtilizationOverall_549: Decodable {
    let utilizationRate: Double?
    let avgDaysInUse: Double?
    let avgDaysIdle: Double?
}

/// users.me — users.ts:99. `role` falls back to the lowercase literal 'shipper'.
private struct Me_549: Decodable {
    let role: String?
    let companyId: Int?
}

/// yardManagement.getTrailerDetails — yardManagement.ts:1162. Nullable on 4 paths.
private struct TrailerDetails_549: Decodable {
    let id: String?
    let trailerNumber: String?
    let type: String?
    let status: String?
    let condition: String?
    let make: String?
    let model: String?
    let year: Int?
    let vin: String?
    let nextInspection: String?
}

// MARK: - View models

/// The four states the server can actually emit (yardManagement.ts:65).
private struct TrailerChip_549: Identifiable {
    let id = UUID()
    enum State { case loaded, empty, available, inRepair }
    let state: State
    let trailerId: String?
}

private struct PoolLegend_549: Identifiable {
    let id = UUID()
    let state: TrailerChip_549.State
    let label: String
}

/// One site row. Real name / terms / capacity from getYardLocations. There is
/// deliberately NO delta field: per-site balance is unsourceable (see header).
private struct Site_549: Identifiable {
    let id = UUID()
    let name: String
    let terms: String
    let capacityLine: String
    let dockLine: String
    let isActive: Bool
}

// `private` at file scope: this view model's published properties are typed with
// the file-private row structs above, so the class must be no more accessible
// than they are. (The inherited declaration was `internal`, which is a hard
// access-control error — further evidence this file had never been compiled.)
@MainActor
private final class TrailerPoolVM_549: ObservableObject {

    // ---- RBAC · yardOpsProcedure yardManagement.ts:19-21 ------------------
    // Derived from users.me `role`, NOT asserted. False => the commit path is
    // unavailable and the reason is printed on screen.
    @Published var hasYardOpsGrant = false
    @Published var yardOpsDeniedReason = "Repositioning needs the yard-ops role (terminal manager, dispatch or admin) — ask an Aurora yard admin"

    /// The exact role set `yardOpsProcedure` admits (yardManagement.ts:19-21).
    private static let yardOpsRoles: Set<String> = ["TERMINAL_MANAGER", "DISPATCH", "ADMIN", "SUPER_ADMIN"]

    // ---- Named gaps, carried explicitly and shown on screen ---------------
    let STUB_ASSET_INTERCHANGE = "assetInterchange.getOpenInterchanges"
    let interchangeBlockedReason = "Interchange needs assetInterchange.getOpenInterchanges — the Catalyst-side echo is not on the server yet"
    let STUB_DISPATCH_BOARD_UPDATE_LISTENER = "iOS Views/Dispatch needs the WS_CHANNELS.DISPATCH(companyId) subscription block"
    let esangBlockedReason = "ESang has no dispatch screen token — esangCoach.forScreen only accepts driver surfaces"

    // ---- Load-cycle state (house pattern, per 545) ------------------------
    @Published var loading = true
    @Published var loadError: String?
    @Published var working = false
    @Published var actionNote: String?

    // ---- TopBar -----------------------------------------------------------
    @Published var poolCaption = "—"

    // ---- Pool inventory hero ----------------------------------------------
    @Published var inventoryLabel = "POOL INVENTORY · EVERY BOX, NOT A TOTAL"
    @Published var strandedCount  = "—"
    @Published var strandedCaption = "past free time"
    @Published var dwellExposure  = "—"
    @Published var dwellCaption   = "dwell exposure today"
    @Published var chips: [TrailerChip_549] = []
    @Published var legend: [PoolLegend_549] = []

    // ---- Site ledger ------------------------------------------------------
    @Published var ledgerLabel  = "SITES"
    @Published var ledgerSource = "yardManagement.ts:281"
    @Published var siteGlyph    = "door.garage.closed"
    @Published var sites: [Site_549] = []
    @Published var netNote = ""
    /// Printed inside the ledger. The have-vs-need bar is suppressed, not faked.
    let balanceSuppressedReason = "Per-site have-vs-need is not drawn: getYardLocations returns occupied = 0 for every site and getTrailerPool returns the same hardcoded locationId for every trailer, so a surplus/deficit bar could only be invented. Real capacity and dock counts are shown instead."

    // ---- ESang row (derived from this screen's own reads) ------------------
    @Published var esangTitle = "Pool state"
    @Published var esangBody  = "Reading the yard…"

    // ---- CTA pair ---------------------------------------------------------
    @Published var primaryTitle   = "Build reposition plan"
    @Published var secondaryTitle = "Interchange"

    private let api = EusoTripAPI.shared

    /// The interchange CTA can never fire on this build.
    var canInterchange: Bool { false }

    // MARK: Load — ONE tick

    func load() async {
        loading = true
        loadError = nil

        struct PoolIn: Encodable { let limit: Int; let offset: Int }
        struct LocationsIn: Encodable { let status: String }
        struct DetentionIn: Encodable { let onlyActive: Bool }
        struct EquipmentIn: Encodable { let limit: Int; let offset: Int }
        struct UtilIn: Encodable { let period: String }

        var failures: [String] = []

        // 0 · the yard-ops grant — read, not asserted
        do {
            let me: Me_549 = try await api.queryNoInput("users.me")
            hasYardOpsGrant = Self.yardOpsRoles.contains((me.role ?? "").uppercased())
        } catch {
            hasYardOpsGrant = false
            failures.append("role")
        }

        // 1 · the chip strip
        do {
            let pool: TrailerPool_549 = try await api.query(
                "yardManagement.getTrailerPool", input: PoolIn(limit: 100, offset: 0))
            chips = pool.trailers.map {
                TrailerChip_549(state: Self.state(for: $0.status), trailerId: $0.id)
            }
            let s = pool.summary
            legend = [
                .init(state: .loaded,    label: "loaded \(Self.count(chips, .loaded))"),
                .init(state: .empty,     label: "empty \(Self.count(chips, .empty))"),
                .init(state: .available, label: "available \(Self.count(chips, .available))"),
                .init(state: .inRepair,  label: "in repair \(Self.count(chips, .inRepair))")
            ]
            poolCaption = "\(s?.total ?? chips.count) UNITS"
        } catch {
            chips = []
            legend = []
            failures.append("trailer pool")
        }

        // 2 · the hero figures
        do {
            let det: Detention_549 = try await api.query(
                "yardManagement.getDetentionTracking", input: DetentionIn(onlyActive: true))
            let active = det.summary?.activeDetentions ?? 0
            strandedCount = "\(active)"
            strandedCaption = active == 1 ? "box past free time" : "boxes past free time"
            dwellExposure = Self.currency(det.summary?.totalAccruedCharges ?? 0)
            if let hrs = det.summary?.avgDetentionHours, hrs > 0 {
                dwellCaption = String(format: "dwell exposure · avg %.1fh", hrs)
            }
        } catch {
            strandedCount = "—"
            dwellExposure = "—"
            failures.append("detention")
        }

        // 3 · the site rows
        do {
            let locs: YardLocations_549 = try await api.query(
                "yardManagement.getYardLocations", input: LocationsIn(status: "active"))
            sites = locs.locations.map { l in
                Site_549(
                    name: l.name ?? l.id ?? "Site",
                    terms: [l.type?.replacingOccurrences(of: "_", with: " "), l.address]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    capacityLine: l.capacity.map { "cap \($0)" } ?? "cap —",
                    dockLine: l.dockDoors.map { "\($0) dock\($0 == 1 ? "" : "s")" } ?? "docks —",
                    isActive: (l.status ?? "active") == "active")
            }
            ledgerLabel = "SITES · \(locs.total ?? sites.count)"
            poolCaption = "\(chips.count) UNITS · \(sites.count) SITE\(sites.count == 1 ? "" : "S")"
        } catch {
            sites = []
            failures.append("yard locations")
        }

        // 4 · the net line — real equipment count + the one real utilisation field
        var netParts: [String] = []
        do {
            let eq: EquipmentList_549 = try await api.query(
                "equipment.list", input: EquipmentIn(limit: 100, offset: 0))
            if let t = eq.total ?? eq.summary?.total { netParts.append("\(t) units on the equipment roll") }
            if let m = eq.summary?.maintenance, m > 0 { netParts.append("\(m) in maintenance") }
        } catch {
            failures.append("equipment")
        }
        do {
            let u: Utilization_549 = try await api.query(
                "equipment.getUtilization", input: UtilIn(period: "month"))
            if let rate = u.overall?.utilizationRate {
                netParts.append(String(format: "%.0f%% utilised this month", rate))
            }
        } catch {
            failures.append("utilisation")
        }
        netNote = netParts.isEmpty ? "" : netParts.joined(separator: " · ")

        // ESang row — over the numbers actually loaded on this screen.
        let inRepair = Self.count(chips, .inRepair)
        esangTitle = chips.isEmpty
            ? "No trailers in the pool right now"
            : "\(Self.count(chips, .empty) + Self.count(chips, .available)) of \(chips.count) boxes are free to move"
        esangBody = "\(strandedCount) past free time · \(dwellExposure) exposure · \(inRepair) in repair"

        if !failures.isEmpty && chips.isEmpty && sites.isEmpty {
            loadError = "Couldn't reach the yard (\(failures.joined(separator: ", ")))."
        }
        loading = false
    }

    // MARK: Actions

    /// yardManagement.getTrailerDetails:1162 — a real chip tap.
    func openTrailer(_ id: UUID) async {
        guard let chip = chips.first(where: { $0.id == id }), let trailerId = chip.trailerId else { return }
        working = true
        actionNote = nil
        struct In: Encodable { let trailerId: String }
        do {
            let box: Nullable_549<TrailerDetails_549> = try await api.query(
                "yardManagement.getTrailerDetails", input: In(trailerId: trailerId))
            if let d = box.value {
                let unit = d.trailerNumber ?? d.id ?? trailerId
                var parts: [String] = [unit]
                if let t = d.type { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
                if let s = d.status { parts.append(s.replacingOccurrences(of: "_", with: " ")) }
                if let c = d.condition { parts.append(c.replacingOccurrences(of: "_", with: " ")) }
                if let v = d.vin, !v.isEmpty { parts.append("VIN \(v.suffix(6))") }
                actionNote = parts.joined(separator: " · ")
            } else {
                actionNote = "That trailer is not visible to your company."
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't load that trailer."
        }
        working = false
    }

    /// Builds the reposition plan from the real reads on this screen and states
    /// exactly what committing it would need. It does NOT call moveTrailer:
    /// that requires a destination spot this composition never collects, and a
    /// custody move to an invented spot is worse than no move at all.
    func buildRepositionPlan() async {
        working = true
        actionNote = nil
        struct DetentionIn: Encodable { let onlyActive: Bool }
        do {
            let det: Detention_549 = try await api.query(
                "yardManagement.getDetentionTracking", input: DetentionIn(onlyActive: true))
            let over = det.summary?.activeDetentions ?? 0
            let critical = det.summary?.criticalCount ?? 0
            let free = Self.count(chips, .empty) + Self.count(chips, .available)
            let openSites = sites.filter { $0.isActive }.count
            if over == 0 {
                actionNote = "Nothing is past free time — no reposition needed. \(free) boxes are free to move across \(openSites) active site\(openSites == 1 ? "" : "s")."
            } else {
                actionNote = "\(over) box\(over == 1 ? "" : "es") past free time (\(critical) critical) · \(free) free to move · \(openSites) active site\(openSites == 1 ? "" : "s"). Committing a move needs a destination spot, which this board does not collect — use 406 Yard Slots to place it."
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't build the plan."
        }
        working = false
    }

    /// NAMED GAP — assetInterchange.getOpenInterchanges does not exist. The
    /// control is `.disabled`; if this is ever reached it refuses honestly.
    func openInterchange() async {
        actionNote = interchangeBlockedReason
    }

    /// NAMED GAP — esangCoach.forScreen admits no dispatcher screen token. The
    /// control is `.disabled`; the row's text comes from this screen's reads.
    func openEsangProposal() async {
        actionNote = esangBlockedReason
    }

    // NOTE — yardManagement.moveTrailer (:440), assignTrailer (:1214),
    // checkInTrailer (:848) and checkOutTrailer (:922) are verified and
    // deliberately NOT wired here. See the header for each reason.

    // MARK: Derivations

    private static func state(for raw: String?) -> TrailerChip_549.State {
        switch (raw ?? "").lowercased() {
        case "loaded":    return .loaded
        case "empty":     return .empty
        case "in_repair": return .inRepair
        default:          return .available
        }
    }

    private static func count(_ chips: [TrailerChip_549], _ s: TrailerChip_549.State) -> Int {
        chips.filter { $0.state == s }.count
    }

    private static func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Public entry point

struct DispatcherTrailerPoolBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { TrailerPoolBoardBody_549() }
    }
}

// MARK: - Body

private struct TrailerPoolBoardBody_549: View {
    @Environment(\.palette) private var palette
    @StateObject private var vm = TrailerPoolVM_549()

    // Ledger geometry, taken straight off the SVG: content span 368pt, dashed
    // centre axis at x=300 within a card that starts at x=36 -> 0.7174.
    private let axisFraction: CGFloat = 0.7174

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if vm.loading {
                    loadingCard
                } else if let err = vm.loadError {
                    errorCard(err)
                } else {
                    inventoryHero
                    siteLedger
                    esangRow
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }.padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await vm.load() }
        .eusoRefreshable { await vm.load() }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading the yard…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(palette.textPrimary)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
    }

    // MARK: - tone map (four real server states, same four palette slots)

    private func stateColor(_ s: TrailerChip_549.State) -> Color {
        switch s {
        case .loaded:    return Brand.escort   // #9C27B0
        case .empty:     return Brand.rail     // #607D8B
        case .available: return Brand.info     // #2196F3
        case .inRepair:  return Brand.danger   // #F44336
        }
    }
    private func stateOpacity(_ s: TrailerChip_549.State) -> Double {
        switch s {
        case .loaded:    return 0.95
        case .empty:     return 0.55
        case .available: return 0.75
        case .inRepair:  return 0.95
        }
    }

    // MARK: - DETAIL TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EusoTripEyebrow(verbatim: "DISPATCHER · TRAILER POOL")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm.poolCaption)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                // Real control, not a decorative glyph — the house pattern every
                // pre-existing Dispatch peer uses (410:194-200). 44-unit target.
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Trailer pool").font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            IridescentHairline()
        }
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    // MARK: - physical inventory strip hero

    private var inventoryHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(vm.inventoryLabel)
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(vm.strandedCount)
                    .font(.system(size: 32, weight: .bold)).monospacedDigit().kerning(-0.5)
                    .foregroundStyle(poolDangerText_549)
                Text(vm.strandedCaption).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(vm.dwellExposure).font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.dwellCaption).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.top, 14)

            chipStrip.padding(.top, Space.s4)
            legendRow.padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // Every trailer, 12 to a row — not a total.
    private var chipStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 12), spacing: 5, alignment: .leading),
                                 count: 12),
                  alignment: .leading, spacing: 7) {
            ForEach(vm.chips) { c in
                Button { Task { await vm.openTrailer(c.id) } } label: { trailerChip(c) }
                    .buttonStyle(.plain)
                    .disabled(vm.working)
            }
        }
    }

    private func trailerChip(_ c: TrailerChip_549) -> some View {
        let tint = stateColor(c.state).opacity(stateOpacity(c.state))
        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(tint).frame(height: 15)
            HStack(spacing: 0) {
                Color.clear.frame(width: 2)
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 4, height: 2)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 4, height: 2)
                Color.clear.frame(width: 4)
            }.frame(height: 2)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 0) {
            ForEach(vm.legend) { l in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(stateColor(l.state)).frame(width: 9, height: 6)
                    Text(l.label).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                if l.id != vm.legend.last?.id { Spacer(minLength: Space.s2) }
            }
        }
    }

    // MARK: - Site ledger
    // The dashed centre axis and the row chrome are preserved. The ±delta bar is
    // SUPPRESSED because it has no server source — see the header and the stated
    // line at the foot of this ledger.

    private var siteLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.ledgerLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ledgerSource).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }.padding(.bottom, Space.s3)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(vm.sites.enumerated()), id: \.element.id) { idx, s in
                    siteRow(s)
                    if idx < vm.sites.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s2)
                    }
                }
                if vm.sites.isEmpty {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("No active yard locations for this company.").font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
                if !vm.netNote.isEmpty {
                    Text(vm.netNote).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .padding(.top, 14)
                }
                // The one thing this board will not invent, said out loud.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Text(vm.balanceSuppressedReason).font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }.padding(.top, 10)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard)
                    .overlay(
                        GeometryReader { geo in
                            Path { p in
                                let x = 16 + (geo.size.width - 32) * axisFraction
                                p.move(to: CGPoint(x: x, y: 16))
                                p.addLine(to: CGPoint(x: x, y: max(16, geo.size.height - 40)))
                            }
                            .stroke(palette.borderSoft,
                                    style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        }
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    private func siteRow(_ s: Site_549) -> some View {
        // Active site = the success hue over the Palette's success wash. An
        // inactive site is the house neutral pairing (rail hue, neutral wash) —
        // never a raw .gray.
        let tint = s.isActive ? Brand.success : Brand.rail
        let wash = s.isActive ? palette.tintSuccess : palette.tintNeutral
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                // MANDATORY 40x40 rx10 icon chip — a dock glyph.
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(wash)
                        .frame(width: 40, height: 40)
                    Image(systemName: vm.siteGlyph)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(s.name).font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(s.terms)
                        .font(.system(size: 11, design: .monospaced)).kerning(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }.padding(.top, 2)
                Spacer(minLength: Space.s2)
                // Real capacity + dock counts stand where the invented ±delta stood.
                VStack(alignment: .trailing, spacing: Space.s1) {
                    Text(s.capacityLine)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(s.isActive ? poolSuccessText_549 : palette.textSecondary)
                    Text(s.dockLine).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }.padding(.top, 2)
            }
        }
    }

    // MARK: - ESang row (NAMED GAP — disabled, with the reason on screen)

    private var esangRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await vm.openEsangProposal() } } label: {
                HStack(spacing: Space.s4) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                     center: .topLeading, startRadius: 1, endRadius: 14))
                            .frame(width: 28, height: 28)
                        Text("E").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textOnGradient)
                    }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(vm.esangTitle).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(vm.esangBody).font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: Space.s2)
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4).frame(height: 56)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .opacity(0.6)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityHint(vm.esangBlockedReason)
            Text(vm.esangBlockedReason).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - CTA pair (yard-ops gate · interchange gap · never a dead tap)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await vm.buildRepositionPlan() } } label: {
                    Text(vm.working ? "Working…" : vm.primaryTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textOnGradient)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                .disabled(vm.working)

                Button { Task { await vm.openInterchange() } } label: {
                    Text(vm.secondaryTitle).font(.system(size: 15, weight: .semibold))
                        .frame(width: 132, height: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                        .opacity(vm.canInterchange ? 1.0 : 0.45)
                }
                .foregroundStyle(palette.textPrimary)
                .disabled(!vm.canInterchange)
                .accessibilityHint(vm.interchangeBlockedReason)
            }
            if !vm.canInterchange {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(poolWarnText_549)
                    Text(vm.interchangeBlockedReason).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(poolWarnText_549)
                }
            }
            if !vm.hasYardOpsGrant {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(poolWarnText_549)
                    Text(vm.yardOpsDeniedReason).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(poolWarnText_549)
                }
            }
            if let note = vm.actionNote {
                Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("549 · Trailer Pool Board · Dark")  { DispatcherTrailerPoolBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("549 · Trailer Pool Board · Light") { DispatcherTrailerPoolBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
