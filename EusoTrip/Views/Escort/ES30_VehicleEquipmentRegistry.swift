//
//  ES30_VehicleEquipmentRegistry.swift
//  EusoTrip — Escort · Vehicle & Equipment Registry (ES-30).
//
//  NEW SURFACE. Nothing on disk owns the escort's persistent rig record today,
//  so this file shadows no brick and edits none. It needs a nav entry it does
//  NOT write: `EscortNavController.swift` is single-writer owned and
//  `ContentView.swift` is being landed centrally this fire, so the registry
//  entry ("630" → `EscortVehicleRegistryES30Screen`) is filed in the manifest
//  for that writer rather than added here. Until it lands, the screen is
//  reachable only by direct push from ES-12 Me Profile, whose
//  EQUIPMENT · REGISTRY PREVIEW strip already carries the OPEN REGISTRY
//  chevron and whose own `<desc>` files this surface as "owed".
//
//  Built from the ES-30 twins
//  ("07 Escort/{Light,Dark}-SVG/ES-30 Vehicle Equipment Registry.svg").
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  ══════════════════════════════════════════════════════════════════════════
//  THE BOUNDARY — the whole reason this row exists separately from ES-06.
//
//  ES-06 Vehicle Check is the PER-MOVE inspection: keyed on `assignmentId`
//  (escort_vehicle_inspections.assignmentId int NOT NULL, drizzle/schema.ts:1823),
//  a 12-cell tap grid of independent binary pass/fail for ONE move, carrying a
//  SUBMIT verb that WRITES a row (escorts.submitVehicleCheck, escorts.ts:1208).
//
//  ES-30 is the PERSISTENT record: it writes NOTHING, it is keyed on
//  `escortUserId` across every assignment the operator has ever run
//  (escorts.getVehicleCheckHistory, gate escorts.ts:1356
//   `eq(escortVehicleInspections.escortUserId, userId)`), and every state it
//  prints is LONGITUDINAL. "6 OF 6 PASSED" is a count across six archived
//  checks; it is never this-move state.
//
//  If this file grows a per-item tap target, a pass/fail cell, or a submit
//  button, it has become a second ES-06 and must be reverted.
//  ══════════════════════════════════════════════════════════════════════════
//
//  ARCHETYPE DETAIL — an EXPLODED SIDE ELEVATION over a RECEIPT STACK.
//  Upper register: the operator's own pilot car in true side elevation, drawn
//  once, with every item tagged AT its real physical mount point carrying that
//  item's longitudinal state. The one item the platform cannot track at all is
//  tagged at its mount point as UNTRACKED — you see the physical thing and you
//  see that nobody is recording it, which is far more legible than its absence
//  from a list. Lower register: the real inspection archive as overlapping
//  dated slips receding into depth, most recent face-up. That is the DOT-stop
//  artifact, and depth encodes recency without a table.
//
//  Anti-clone — NOT ES-06's 12-cell equipment BentoGrid of binary pass/fail
//  (the nearest trap: ES-06 is a grid of independent checks for one move; this
//  is a physical diagram plus a time archive, and neither is a grid), NOT
//  ES-12's three-rung cert staircase, NOT ES-20's severed gate track, NOT
//  ES-02's semicircular arc clearance gauge, NOT ES-26's roadway plan view.
//
//  ── WIRING (every pin opened at the line first-hand this fire against the
//     live tree; server/routers/escorts.ts = 4745 lines) ─────────────────────
//
//    EXISTS escorts.getVehicleCheckHistory      escorts.ts:1344
//           input  { assignmentId?: coerce.number,
//                    limit: int.min(1).max(50).default(20) } .optional()
//                  (escorts.ts:1345-1348)
//           gate   getDb() null -> [] (:1351) · resolveEscortUserId falsy -> []
//                  (:1353) · conds = [eq(escortVehicleInspections.escortUserId,
//                  userId)] (:1356) — own rows ONLY, across ALL assignments ·
//                  orderBy desc(signedAt) (:1360)
//           output [{ inspectionId, assignmentId, vehicleDesc, odometer,
//                     passed: Boolean, failedItems: string[], photoCount,
//                     signedAt: ISO|null }] (:1362-1371)
//           → the receipt stack, and the raw material for every mount tag.
//
//    EXISTS escorts.getVehicleCheckDetail       escorts.ts:1374
//           input  { inspectionId: coerce.number } (:1375)
//           gate   and(eq(id,…), eq(escortUserId, userId)) (:1382-1384);
//                  foreign / phantom id returns null, NOT 403 (:1385)
//           output { …, checklist, photos: string[], template } (:1386-1397)
//           → OPEN LATEST INSPECTION. The only drill-in on this screen.
//
//    EXISTS  the .max(50) ceiling               escorts.ts:1347
//           → LOAD ALL 50 is the same history query at the server's own limit.
//             A real re-read, not an invented endpoint.
//
//    DERIVED per-mount longitudinal state       escorts.ts:1369 + schema.ts:1830
//           Folded on device out of the `failedItems[]` arrays the history call
//           already returns. Arithmetic over a real persisted json column — no
//           second read, nothing invented, and the elevation footer says so on
//           glass.
//
//    CEILING the inspection certificate         escorts.ts:1258-1279 / :1253
//           submitVehicleCheck writes a documents row per inspection carrying a
//           base64 JSON data-URL, and the file's own comment at escorts.ts:1253
//           states "PDF render is owed host-side". The card therefore prints
//           CERTIFICATE ON FILE · JSON ONLY, NO PDF and draws NO download
//           button — that CTA would be a link to nowhere.
//
//    STUB   PERSISTENT OWNED-EQUIPMENT REGISTRY. Falsifiable zero-greps re-run
//           this fire over frontend/server/** and frontend/drizzle/**:
//             "escortEquipment"   = 0
//             "escort_vehicles"   = 0
//             "poleRig"           = 0
//             "pole_rig"          = 0
//             "equipmentInventory"= 0
//             "equipment_inventory"= 0
//             "reorderAlert"      = 0
//             "reorder_level"     = 0
//             "reorderThreshold"  = 0
//             "escort_equipment"  = 1  and it is NOT a table — escorts.ts:3391
//                 is a checklist row { id: "height_pole", label: 'Height pole on
//                 lead escort vehicle', required: …, category: "escort_equipment" }
//                 inside getOversizeChecklist.
//             "escortVehicles"    = 6  and all six are a LOCAL ARRAY VARIABLE
//                 inside getActiveAssignmentDetail — declared escorts.ts:4036,
//                 pushed :4038/:4039/:4042/:4046 with synthetic ids
//                 `ESC-${userId}` and lastKnownLocation/lastPingAt null,
//                 returned :4179. Not a table, not a registry.
//           Owed: escortEquipment.list({}) -> { items: [{ equipmentId,
//                 escortUserId, category, make, model, serial, acquiredAt,
//                 retiredAt, lastVerifiedInspectionId }] } and
//                 escortEquipment.setStock({ equipmentId, onHand, reorderAt }).
//
//    STUB   AN ESCORT ROW IN `vehicles`. vehicles.companyId is
//           int("companyId").notNull().references(companies.id) at
//           drizzle/schema.ts:222 — a vehicle cannot exist without a company —
//           and there is NO escortUserId column anywhere in the vehicles block
//           (schema.ts:218-291); the only ownership pointer is currentDriverId
//           at :268. The vehicleType enum DOES carry "pilot_car" (:242),
//           "escort_truck" (:243), "height_pole_vehicle" (:244),
//           "route_survey_vehicle" (:245) — the enum knows what an escort
//           vehicle is and the access model does not. Both read paths are
//           company-scoped: vehicles.list (server/routers/vehicles.ts:32) bails
//           on resolveCompanyId at :35-36, and equipment.list
//           (server/routers/equipment.ts:33) bails at :38-39 and then HARD-
//           FILTERS at equipment.ts:42 with
//           `${vehicles.vehicleType} IN ('trailer','tanker','flatbed',
//           'refrigerated','dry_van','lowboy','step_deck')` — every escort
//           vehicle type is excluded, so even an escort with a companyId gets
//           an empty array. An independent operator gets [] from both. That is
//           why OWNED EQUIPMENT is a designed void with the reason named.
//
//    STUB   THE POLE RIG AS AN OWNED ASSET. escorts.getPoleConfig EXISTS
//           escorts.ts:4218 and escorts.setPoleConfig EXISTS escorts.ts:4301,
//           but the column is escort_assignments.pole_config, added by
//           `ALTER TABLE escort_assignments ADD COLUMN pole_config JSON NULL`
//           at drizzle/0341_clearance_events.sql:13 (drizzle mirror
//           schema.ts:3819). PER-ASSIGNMENT. There is no persistent pole
//           record, so the pole is drawn at its mount point with a hollow
//           marker and the state UNTRACKED / PER-MOVE ONLY, and this screen
//           offers no verb to set it — setPoleConfig needs an assignmentId this
//           surface does not have.
//
//    STUB   VEHICLE HEIGHT AS A PERSISTENT ATTRIBUTE. The height numbers live
//           on escort_surveys.vehicleHeightFt (schema.ts:1847) and
//           clearance_events.load_height_ft (schema.ts:3880) — both PER-EVENT.
//
//  ── PERSIST · AUDIT · REALTIME ───────────────────────────────────────────
//    THIS SCREEN WRITES NOTHING — both procedures are .query(). NO
//    blockchainAuditTrail row is inserted on this path: the literal token
//    `blockchainAuditTrail` appears 0 times in server/routers/escorts.ts and
//    0 times in server/routers/hazmatEscort.ts (both counts re-run this fire).
//    The escort tree's audit surface is recordAuditEvent() from
//    _core/auditService, imported at escorts.ts:17 and called at escorts.ts:110,
//    607, 1282, 1712, 1788, 1830, 1881, 2569, 3836, 4486 — a different table.
//    WS on the write path is WS_EVENTS.ESCORT_CHECK_SUBMITTED to
//    WS_CHANNELS.LOAD(loadId) (escorts.ts:1297/:1301) plus DISPATCH_UPDATES on
//    failure only (:1305), but `grep -rn "ESCORT_CHECK_SUBMITTED" client/src/`
//    = 0 — nothing subscribes. This screen therefore has no realtime, does not
//    claim any, and draws no live dot. Filed as ESC-WS-30.
//
//  ── RBAC ─────────────────────────────────────────────────────────────────
//    Every procedure here is escortProcedure — aliased to the local name
//    protectedProcedure by escorts.ts:11 — which is roleProcedure(ROLES.ESCORT)
//    at _core/trpc.ts:228 (factory _core/trpc.ts:216) over ROLES.ESCORT at
//    _core/trpc.ts:23. Row scope via resolveEscortUserId (escorts.ts:138); on
//    this surface the ownership gate IS the query predicate. The dispatcher
//    counterpart getInspectionForAssignment (escorts.ts:1405) is
//    roleProcedure(ROLES.DISPATCH, ROLES.ADMIN) and is unreachable from here.
//
//  ── OFFLINE §W ───────────────────────────────────────────────────────────
//    READ_CACHED(6h) via EscortOfflineCache, key `escort.es30.registry`. The
//    long TTL is deliberate: this is what an operator shows a DOT officer on a
//    shoulder with no bars, and an append-only archive six hours old cannot be
//    wrong, only short. A cached paint swaps the archive header's count for the
//    staleness line and adds NEWEST ROW MAY BE MISSING. There are no mutations
//    on this screen at all, so ONLINE_ONLY is vacuous here and no queue badge
//    is drawn anywhere — the phone has no escort outbox (EscortOfflineCache is
//    a read cache only; the Unified Outbox is Driver-only, PLANNED per Offline
//    Mode Encyclopedia v2).
//
//  ── CHAIN ────────────────────────────────────────────────────────────────
//    Read chain CLOSED both ways. Write chain N-A (no write verb exists here;
//    the inspection write chain lives on ES-06 and is ONE-SIDED there).
//    Registry chain SILENT — the owned-equipment half has no table, so there is
//    no chain to open, which is exactly what the designed void says.
//
//  ── DECODE DISCIPLINE ────────────────────────────────────────────────────
//    escort_vehicle_inspections carries NO decimal columns (schema.ts:1821-1835:
//    odometer `int`, passed `tinyint`, checklist/photos/failedItems `json`), so
//    the decimal-serialises-as-a-JSON-string class that has killed three escort
//    screens does not apply here. Every field is typed against what the
//    producer literally emits at escorts.ts:1362-1371, including the nullables
//    (`vehicleDesc`, `odometer`, `signedAt`). No force-unwrap, and no `try?`:
//    a swallowed decode is how two escort screens shipped permanently empty.
//

import SwiftUI

// MARK: - Wire models (escorts.ts:1362-1371)

private struct ES30Row: Codable, Identifiable, Equatable {
    let inspectionId: Int
    let assignmentId: Int
    let vehicleDesc: String?          // varchar(160) NULLABLE — schema.ts:1824
    let odometer: Int?                // int NULLABLE — schema.ts:1825
    let passed: Bool                  // Boolean(row.passed) — escorts.ts:1367
    let failedItems: [String]         // ?? [] — escorts.ts:1368
    let photoCount: Int               // a count, never URLs — escorts.ts:1369
    let signedAt: String?             // ISO | null — escorts.ts:1370
    var id: Int { inspectionId }
}

private struct ES30HistoryInput: Encodable {
    var limit: Int = 20
}

private struct ES30DetailInput: Encodable { let inspectionId: Int }

/// escorts.getVehicleCheckDetail (escorts.ts:1386-1397). Only the fields this
/// screen's drill-in actually consumes are decoded; `checklist` stays opaque
/// because the label strings live on `template` and belong to ES-06's renderer.
private struct ES30Detail: Codable {
    let inspectionId: Int
    let assignmentId: Int
    let vehicleDesc: String?
    let odometer: Int?
    let photos: [String]
    let passed: Bool
    let failedItems: [String]
    let signedAt: String?
}

private struct ES30Snapshot: Codable, Equatable {
    var rows: [ES30Row] = []
    var limit: Int = 20
}

// MARK: - The frozen 12 keys and the 7 physical mount points

/// `ESCORT_CHECKLIST_V1` keys — escorts.ts:33-46, set frozen at escorts.ts:47.
/// Mirrored as KEYS only, so `failedItems[]` can be folded per mount point.
/// The human LABELS are never mirrored and never printed: ES-06 retracted a
/// fallback on 2026-07-28 that leaked DB keys to glass, and this file does not
/// reintroduce that class.
private enum ES30Keys {
    static let all: [String] = [
        "height_pole", "oversize_load_signs", "warning_flags",
        "amber_beacons_or_lightbar", "cb_radio", "backup_comms",
        "fire_extinguisher", "first_aid_kit", "stop_slow_paddle",
        "safety_vest_hard_hat", "insurance_card_current", "spare_tire_jack",
    ]
}

private struct ES30Mount: Identifiable {
    enum Register { case archived, untracked(String) }
    let id: String
    let title: String
    let keys: [String]
    let register: Register
    /// Card-local (400 × 262) mount point — identical to the SVG twins.
    let mount: CGPoint
    /// Card-local baseline of the tag title. The ORDER of these baselines is
    /// the order that makes every leader non-crossing; it was verified pairwise
    /// against the twins. Do not reorder without redoing that proof.
    let tagBaseline: CGFloat

    /// The seven mounts partition all twelve keys exactly once.
    static let all: [ES30Mount] = [
        .init(id: "pole",   title: "HEIGHT POLE",       keys: ["height_pole"],
              register: .untracked("PER-MOVE ONLY"), mount: .init(x: 106, y: 30),  tagBaseline: 26),
        .init(id: "signs",  title: "SIGNS + FLAGS",     keys: ["oversize_load_signs", "warning_flags"],
              register: .archived, mount: .init(x: 226, y: 90),  tagBaseline: 56),
        .init(id: "beacon", title: "AMBER LIGHT BAR",   keys: ["amber_beacons_or_lightbar"],
              register: .archived, mount: .init(x: 248, y: 118), tagBaseline: 86),
        .init(id: "cabkit", title: "CAB SAFETY KIT",
              keys: ["fire_extinguisher", "first_aid_kit", "safety_vest_hard_hat", "insurance_card_current"],
              register: .archived, mount: .init(x: 240, y: 137), tagBaseline: 116),
        .init(id: "comms",  title: "CB + BACKUP COMMS", keys: ["cb_radio", "backup_comms"],
              register: .archived, mount: .init(x: 196, y: 142), tagBaseline: 146),
        .init(id: "paddle", title: "STOP/SLOW PADDLE",  keys: ["stop_slow_paddle"],
              register: .archived, mount: .init(x: 280, y: 158), tagBaseline: 176),
        .init(id: "spare",  title: "SPARE TIRE + JACK", keys: ["spare_tire_jack"],
              register: .archived, mount: .init(x: 295, y: 197), tagBaseline: 206),
    ]

    var isUntracked: Bool { if case .untracked = register { return true }; return false }
}

private struct ES30MountState {
    let checked: Int
    let failed: Int
    var passed: Int { checked - failed }
    var isClean: Bool { failed == 0 }

    static func fold(_ m: ES30Mount, over rows: [ES30Row]) -> ES30MountState {
        ES30MountState(checked: rows.count * m.keys.count,
                       failed: rows.reduce(0) { $0 + m.keys.filter($1.failedItems.contains).count })
    }

    var line: String {
        if checked == 0 { return "NO ROWS ON FILE" }
        return isClean ? "\(passed) OF \(checked) PASSED"
                       : "\(passed) OF \(checked) · \(failed) FAIL"
    }
}

// MARK: - Screen

struct EscortVehicleRegistryES30: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    private enum Phase: Equatable { case loading, live, cached, empty, failed(String) }

    @State private var phase: Phase = .loading
    @State private var snap = ES30Snapshot()
    @State private var cacheAge: TimeInterval? = nil
    @State private var expanded = false
    @State private var detailNote: String? = nil

    private let cacheKey = "escort.es30.registry"
    private let cacheTTL: TimeInterval = 6 * 60 * 60       // READ_CACHED(6h)

    private var isDark: Bool { scheme == .dark }
    private var okInk: Color   { isDark ? Color(hex: 0x34D399) : Color(hex: 0x0B7A4B) }
    private var badInk: Color  { isDark ? Color(hex: 0xF87171) : Color(hex: 0xB91C1C) }
    private var blueInk: Color { isDark ? Color(hex: 0x60A5FA) : Color(hex: 0x1D4ED8) }
    private static let mono = "Geist Mono"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            eyebrowRow
            titleRow
            IridescentHairline()
            metaRow
            elevationBand
            ownedEquipmentVoid
            archiveBand
            Spacer(minLength: 0)
            footnotes
            ctaBand
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh(limit: 20) }
        .eusoRefreshable { await refresh(limit: snap.limit) }
    }

    // MARK: Header — DETAIL archetype: H1 28 @ y116, back chevron, hairline y138,
    //                no subline, and the meta row strictly BELOW the hairline.

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · VEHICLE & EQUIPMENT REGISTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient(colors: [Brand.blue, Brand.magenta],
                                                startPoint: .leading, endPoint: .trailing))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text("FMCSA 3 291 447")
                .font(.custom(Self.mono, size: 9).weight(.heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityLabel("Back")
            Text("My Rig")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Text("LEAD")
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(blueInk)
                .frame(width: 52, height: 20)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.info.opacity(0.16)))
            Text(vehicleLine)
                .font(.custom(Self.mono, size: 10).weight(.semibold)).tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Text("Jordan Escoto · JE")
                .font(.custom(Self.mono, size: 10))
                .foregroundStyle(palette.textTertiary)
        }
    }

    /// `vehicleDesc` is nullable free text (schema.ts:1824) the operator typed
    /// on ES-06 — NOT a `vehicles` row. When no row carries one, we say that
    /// rather than printing a placeholder that reads like a registration.
    private var vehicleLine: String {
        let desc = snap.rows.compactMap { $0.vehicleDesc }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return desc?.uppercased() ?? "VEHICLE NOT DESCRIBED ON ANY ROW"
    }

    // MARK: Upper register

    private var elevationBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MOUNTED EQUIPMENT · SIDE ELEVATION",
                          trailing: "\(ES30Keys.all.count) KEYS · \(untrackedKeyCount) UNTRACKED")
            ES30ElevationCanvas(mounts: ES30Mount.all,
                                states: mountStates,
                                archiveDepth: snap.rows.count,
                                palette: palette,
                                okInk: okInk, badInk: badInk)
                .frame(height: 262)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(elevationA11y)
        }
    }

    private var untrackedKeyCount: Int {
        ES30Mount.all.filter(\.isUntracked).reduce(0) { $0 + $1.keys.count }
    }

    private var mountStates: [String: ES30MountState] {
        Dictionary(uniqueKeysWithValues:
            ES30Mount.all.map { ($0.id, ES30MountState.fold($0, over: snap.rows)) })
    }

    private var elevationA11y: String {
        ES30Mount.all.map { m in
            m.isUntracked ? "\(m.title): untracked, per-move only."
                          : "\(m.title): \(mountStates[m.id]?.line.lowercased() ?? "no rows on file")."
        }.joined(separator: " ")
    }

    // MARK: The designed void
    //
    // Not a blank card and not an "empty state" — an empty state implies rows
    // could arrive. Nothing can arrive here: there is no table. The reason is
    // named in plain English because it is a platform fact the founder should
    // read off the screen, and the schema pins live in the header above.

    private var ownedEquipmentVoid: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .foregroundStyle(palette.textTertiary.opacity(0.45))
                Image(systemName: "shippingbox")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                Rectangle().frame(width: 22, height: 1.4)
                    .rotationEffect(.degrees(-45))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("OWNED EQUIPMENT · NO REGISTRY EXISTS")
                        .font(.system(size: 10.5, weight: .heavy)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 6)
                    Text("0 ROWS")
                        .font(.custom(Self.mono, size: 8.5).weight(.heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Beacons, signs, the pole rig and the radios are drawn above — nothing here can record them as equipment you own.")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .foregroundStyle(palette.textTertiary.opacity(0.55)))
    }

    // MARK: Lower register

    private var archiveBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("INSPECTION ARCHIVE · ALL MOVES, ALL TIME",
                          trailing: archiveTrailing,
                          trailingColor: phase == .cached ? Brand.warning : nil)
            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft)
                    .frame(height: 100)
                    .overlay(Text("Reading your archive…")
                        .font(EType.caption).foregroundStyle(palette.textTertiary))
            case .failed(let why):
                honestBlock(title: "The archive did not answer",
                            body: "Nothing is drawn, because a history that failed to read is not an empty one. \(why)")
            case .empty:
                honestBlock(title: "No inspections on file yet",
                            body: "Your first signed pre-trip check lands here and stays here, across every move you run.")
            case .live, .cached:
                ES30ReceiptStackView(rows: snap.rows, palette: palette, okInk: okInk, badInk: badInk)
            }
            if let detailNote {
                Text(detailNote)
                    .font(.custom(Self.mono, size: 8).weight(.bold))
                    .foregroundStyle(badInk)
            }
        }
    }

    /// A cached paint NEVER wears the live count as if it were live. ES-16
    /// printed a cached wind band tagged LIVE in success green; that is the
    /// defect this branch exists to avoid.
    private var archiveTrailing: String {
        switch phase {
        case .live:    return "\(snap.rows.count) ON FILE · MAX 50"
        case .cached:  return EscortOfflineCache.stalenessLine(age: cacheAge ?? 0).uppercased()
        case .loading: return "READING…"
        case .empty:   return "0 ON FILE"
        case .failed:  return "NOT READ"
        }
    }

    private func honestBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
            Text(body).font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint))
    }

    // MARK: Footnotes + CTA

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(drawnLine)
                .font(.custom(Self.mono, size: 7.5).weight(.bold))
            Text("READ-ONLY · UPDATE EQUIPMENT THROUGH YOUR COMPANY PROFILE")
                .font(.custom(Self.mono, size: 7).weight(.bold))
        }
        .foregroundStyle(palette.textTertiary)
        .lineLimit(1).minimumScaleFactor(0.65)
    }

    private var drawnLine: String {
        let drawn = min(snap.rows.count, 5)
        let stale = phase == .cached ? " · REFRESH FOR THE LATEST EQUIPMENT" : ""
        return "SHOWING \(drawn) OF \(snap.rows.count) REGISTERED ITEMS\(stale)"
    }

    /// Two verbs, both real reads. No PDF button — the certificate is a JSON
    /// data-URL and escorts.ts:1253 says the render is owed host-side, so that
    /// CTA would be a link to nowhere.
    private var ctaBand: some View {
        HStack(spacing: 8) {
            Button { Task { await openLatest() } } label: {
                Text("OPEN LATEST INSPECTION")
                    .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Capsule().fill(LinearGradient(
                        colors: [Brand.blue, Brand.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .disabled(snap.rows.isEmpty)
            .opacity(snap.rows.isEmpty ? 0.45 : 1)

            Button { Task { await refresh(limit: 50); expanded = true } } label: {
                Text(expanded ? "ALL 50 LOADED" : "LOAD ALL 50")
                    .font(.system(size: 11.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144)
                    .frame(minHeight: 42)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().stroke(palette.textPrimary.opacity(0.28), lineWidth: 1.5))
            }
            .disabled(expanded || snap.rows.isEmpty)
            .opacity(expanded || snap.rows.isEmpty ? 0.45 : 1)
        }
    }

    private func sectionHeader(_ title: String, trailing: String,
                               trailingColor: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(trailing)
                .font(.custom(Self.mono, size: 9).weight(.heavy)).tracking(0.4)
                .foregroundStyle(trailingColor ?? palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Load
    //
    // No `try?` anywhere. A live read that throws falls back to the cache ONLY
    // if the cache is inside its TTL, and a cached paint is visibly distinct.
    // If neither answers, the screen says so — it never renders 0 rows as a
    // finding, because `0` is a value and ES-26 already paid for that lesson.

    private func refresh(limit: Int) async {
        await MainActor.run { if snap.rows.isEmpty { phase = .loading } }
        do {
            let rows: [ES30Row] = try await EusoTripAPI.shared.query(
                "escorts.getVehicleCheckHistory",
                input: ES30HistoryInput(limit: limit))
            let fresh = ES30Snapshot(rows: rows, limit: limit)
            EscortOfflineCache.store(fresh, key: cacheKey)
            await MainActor.run {
                snap = fresh
                cacheAge = nil
                phase = rows.isEmpty ? .empty : .live
            }
        } catch {
            if let hit = EscortOfflineCache.load(ES30Snapshot.self, key: cacheKey, ttl: cacheTTL) {
                await MainActor.run {
                    snap = hit.value
                    cacheAge = hit.age
                    phase = hit.value.rows.isEmpty ? .empty : .cached
                }
            } else {
                await MainActor.run {
                    phase = .failed(Self.reason(error))
                }
            }
        }
    }

    private func openLatest() async {
        guard let newest = snap.rows.first else { return }
        await MainActor.run { detailNote = nil }
        do {
            let detail: ES30Detail = try await EusoTripAPI.shared.query(
                "escorts.getVehicleCheckDetail",
                input: ES30DetailInput(inspectionId: newest.inspectionId))
            NotificationCenter.default.post(
                name: .esES30OpenInspectionDetail, object: nil,
                userInfo: ["inspectionId": detail.inspectionId,
                           "assignmentId": detail.assignmentId,
                           "photoCount": detail.photos.count])
        } catch {
            // getVehicleCheckDetail answers `null` for a foreign or phantom id
            // (escorts.ts:1385), which decodes as a failure here. We name it;
            // we do not silently do nothing.
            await MainActor.run {
                detailNote = "THAT INSPECTION DID NOT OPEN · \(Self.reason(error).uppercased())"
            }
        }
    }

    private static func reason(_ error: Error) -> String {
        if error is URLError { return "Equipment records couldn't be reached. Check your connection and try again." }
        if error is DecodingError { return "The response did not match the expected shape." }
        return "Equipment records couldn't be loaded. Pull to retry."
    }
}

extension Notification.Name {
    /// Consumed by the escort navigation host once the registry entry lands.
    static let esES30OpenInspectionDetail = Notification.Name("esES30OpenInspectionDetail")
}

// MARK: - The elevation — true vector geometry, no raster, no traced blob
//
// Card-local space is 400 × 262, identical to the SVG twins, and the Canvas is
// uniformly scaled so the drawing is resolution-independent at any width.

private struct ES30ElevationCanvas: View {
    let mounts: [ES30Mount]
    let states: [String: ES30MountState]
    let archiveDepth: Int
    let palette: Theme.Palette
    let okInk: Color
    let badInk: Color

    private static let mono = "Geist Mono"
    private var ink: Color { palette.textPrimary }
    private var faint: Color { palette.textTertiary }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 400
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    ground(&ctx)
                    spare(&ctx)
                    bodyShell(&ctx)
                    wheels(&ctx)
                    pole(&ctx)
                    signRack(&ctx)
                    lightBar(&ctx)
                    cabFittings(&ctx)
                    leaders(&ctx)
                }
                tagColumn(s)
                footers(s)
            }
        }
    }

    private func ground(_ ctx: inout GraphicsContext) {
        var g = Path(); g.move(to: .init(x: 40, y: 206)); g.addLine(to: .init(x: 292, y: 206))
        ctx.stroke(g, with: .color(faint.opacity(0.55)), lineWidth: 1)
        var h = Path()
        for x in stride(from: 46.0, through: 292.0, by: 22.0) {
            h.move(to: .init(x: x, y: 206)); h.addLine(to: .init(x: x - 6, y: 212))
        }
        ctx.stroke(h, with: .color(faint.opacity(0.30)), lineWidth: 1)
    }

    /// Drawn before the wheel so the wheel occludes it — the occlusion IS the
    /// depth cue for an under-slung spare, not a layering accident.
    private func spare(_ ctx: inout GraphicsContext) {
        let outer = Path(ellipseIn: CGRect(x: 279, y: 183, width: 18, height: 18))
        ctx.fill(outer, with: .color(ink.opacity(0.14)))
        ctx.stroke(outer, with: .color(ink.opacity(0.60)), lineWidth: 1.8)
        ctx.stroke(Path(ellipseIn: CGRect(x: 284.8, y: 188.8, width: 6.4, height: 6.4)),
                   with: .color(ink.opacity(0.40)), lineWidth: 1.2)
        var hang = Path()
        hang.move(to: .init(x: 283, y: 184)); hang.addLine(to: .init(x: 283, y: 180))
        hang.move(to: .init(x: 293, y: 184)); hang.addLine(to: .init(x: 293, y: 180))
        ctx.stroke(hang, with: .color(ink.opacity(0.45)), lineWidth: 1.2)
    }

    private func bodyShell(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: .init(x: 76, y: 180))
        p.addLine(to: .init(x: 76, y: 162))
        p.addQuadCurve(to: .init(x: 82, y: 155), control: .init(x: 76, y: 156))
        p.addLine(to: .init(x: 150, y: 150))
        p.addLine(to: .init(x: 172, y: 124))
        p.addLine(to: .init(x: 250, y: 124))
        p.addLine(to: .init(x: 256, y: 152))
        p.addLine(to: .init(x: 300, y: 152))
        p.addLine(to: .init(x: 300, y: 180))
        p.addLine(to: .init(x: 282, y: 180))
        // Wheel arches. Written as quad curves, not addArc: SwiftUI's
        // `clockwise:` flag is ambiguous in a y-down space and an inverted
        // sweep here would punch the arch DOWNWARD through the rocker. These
        // control points put the crown at y=164, matching the SVG twins' r=16
        // semicircles to within a pixel.
        p.addQuadCurve(to: .init(x: 250, y: 180), control: .init(x: 266, y: 148))
        p.addLine(to: .init(x: 130, y: 180))
        p.addQuadCurve(to: .init(x: 98, y: 180), control: .init(x: 114, y: 148))
        p.closeSubpath()
        ctx.fill(p, with: .color(palette.bgCardSoft))
        ctx.stroke(p, with: .color(ink.opacity(0.55)), lineWidth: 1.6)

        for pts in [[CGPoint(x: 156, y: 148), CGPoint(x: 174, y: 128), CGPoint(x: 200, y: 128), CGPoint(x: 200, y: 148)],
                    [CGPoint(x: 206, y: 128), CGPoint(x: 240, y: 128), CGPoint(x: 246, y: 148), CGPoint(x: 206, y: 148)]] {
            var w = Path(); w.addLines(pts); w.closeSubpath()
            ctx.fill(w, with: .color(ink.opacity(0.10)))
            ctx.stroke(w, with: .color(ink.opacity(0.35)), lineWidth: 1)
        }

        var trim = Path()
        trim.move(to: .init(x: 203, y: 152)); trim.addLine(to: .init(x: 203, y: 177))
        trim.move(to: .init(x: 192, y: 158)); trim.addLine(to: .init(x: 199, y: 158))
        trim.move(to: .init(x: 258, y: 170)); trim.addLine(to: .init(x: 298, y: 170))
        trim.move(to: .init(x: 278, y: 152)); trim.addLine(to: .init(x: 278, y: 158))
        ctx.stroke(trim, with: .color(ink.opacity(0.24)), lineWidth: 1)

        ctx.fill(Path(roundedRect: CGRect(x: 70, y: 167, width: 8, height: 13), cornerRadius: 2),
                 with: .color(ink.opacity(0.50)))
        ctx.fill(Path(roundedRect: CGRect(x: 79, y: 157, width: 7, height: 5), cornerRadius: 1.5),
                 with: .color(Brand.warning.opacity(0.75)))
    }

    private func wheels(_ ctx: inout GraphicsContext) {
        for cx in [114.0, 266.0] {
            let tyre = Path(ellipseIn: CGRect(x: cx - 16, y: 174, width: 32, height: 32))
            ctx.fill(tyre, with: .color(ink.opacity(0.16)))
            ctx.stroke(tyre, with: .color(ink.opacity(0.70)), lineWidth: 2.4)
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - 6, y: 184, width: 12, height: 12)),
                       with: .color(ink.opacity(0.45)), lineWidth: 1.6)
        }
    }

    /// A 15'4" mast to scale would leave the card, so it is drawn BROKEN with a
    /// standard draughting break mark and the card says NOT TO SCALE. Shrinking
    /// the truck to fit the pole would have been a lie about proportion.
    private func pole(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 76, y: 152, width: 14, height: 10), cornerRadius: 2.5),
                 with: .color(ink.opacity(0.45)))
        var mast = Path()
        mast.move(to: .init(x: 84, y: 152)); mast.addLine(to: .init(x: 84, y: 92))
        mast.move(to: .init(x: 84, y: 78));  mast.addLine(to: .init(x: 84, y: 34))
        mast.move(to: .init(x: 60, y: 30));  mast.addLine(to: .init(x: 108, y: 30))
        ctx.stroke(mast, with: .color(faint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var brk = Path()
        brk.move(to: .init(x: 76, y: 93)); brk.addLine(to: .init(x: 92, y: 87))
        brk.move(to: .init(x: 76, y: 85)); brk.addLine(to: .init(x: 92, y: 79))
        ctx.stroke(brk, with: .color(faint.opacity(0.65)), lineWidth: 1.2)
    }

    private func signRack(_ ctx: inout GraphicsContext) {
        var posts = Path()
        posts.move(to: .init(x: 182, y: 124)); posts.addLine(to: .init(x: 182, y: 99))
        posts.move(to: .init(x: 214, y: 124)); posts.addLine(to: .init(x: 214, y: 99))
        ctx.stroke(posts, with: .color(ink.opacity(0.50)), lineWidth: 1.6)

        let panel = Path(roundedRect: CGRect(x: 170, y: 90, width: 56, height: 9), cornerRadius: 1.5)
        ctx.fill(panel, with: .color(Brand.warning.opacity(0.85)))
        ctx.stroke(panel, with: .color(ink.opacity(0.40)), lineWidth: 1)
        var lettering = Path()
        lettering.move(to: .init(x: 176, y: 94.5)); lettering.addLine(to: .init(x: 220, y: 94.5))
        ctx.stroke(lettering, with: .color(ink.opacity(0.60)), lineWidth: 2)

        for pts in [[CGPoint(x: 170, y: 99), CGPoint(x: 160, y: 104), CGPoint(x: 170, y: 108)],
                    [CGPoint(x: 226, y: 99), CGPoint(x: 236, y: 104), CGPoint(x: 226, y: 108)]] {
            var f = Path(); f.addLines(pts); f.closeSubpath()
            ctx.fill(f, with: .color(Brand.danger.opacity(0.80)))
        }
    }

    private func lightBar(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 222, y: 117, width: 26, height: 7), cornerRadius: 2.5),
                 with: .color(ink.opacity(0.50)))
        for cx in [229.0, 241.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 4, y: 112, width: 8, height: 6)),
                     with: .color(Brand.warning.opacity(0.90)))
        }
    }

    /// The cab kit and the stowed paddle are HIDDEN LINES — dashed, because in
    /// a true side elevation they sit behind the door skin and the bedside.
    /// Draughting convention, not decoration.
    private func cabFittings(_ ctx: inout GraphicsContext) {
        ctx.stroke(Path(roundedRect: CGRect(x: 216, y: 127, width: 24, height: 10), cornerRadius: 2),
                   with: .color(faint.opacity(0.70)),
                   style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))

        ctx.fill(Path(roundedRect: CGRect(x: 178, y: 138, width: 18, height: 9), cornerRadius: 2),
                 with: .color(ink.opacity(0.55)))
        for cx in [182.0, 186.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.3, y: 141.2, width: 2.6, height: 2.6)),
                     with: .color(palette.bgCard))
        }
        var whip = Path(); whip.move(to: .init(x: 196, y: 138)); whip.addLine(to: .init(x: 200, y: 130))
        ctx.stroke(whip, with: .color(ink.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        ctx.stroke(Path(ellipseIn: CGRect(x: 264.5, y: 155.5, width: 15, height: 15)),
                   with: .color(faint.opacity(0.75)),
                   style: StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
        var handle = Path()
        handle.move(to: .init(x: 264, y: 165)); handle.addLine(to: .init(x: 259, y: 166))
        ctx.stroke(handle, with: .color(faint.opacity(0.75)),
                   style: StrokeStyle(lineWidth: 1.3, dash: [3, 2]))
    }

    private func leaders(_ ctx: inout GraphicsContext) {
        for m in mounts {
            var l = Path()
            l.move(to: .init(x: 296, y: m.tagBaseline + 1)); l.addLine(to: m.mount)
            if m.isUntracked {
                ctx.stroke(l, with: .color(ink.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                let dot = Path(ellipseIn: CGRect(x: m.mount.x - 2.6, y: m.mount.y - 2.6,
                                                 width: 5.2, height: 5.2))
                ctx.fill(dot, with: .color(palette.bgCard))
                ctx.stroke(dot, with: .color(faint), lineWidth: 1.4)
            } else {
                ctx.stroke(l, with: .color(ink.opacity(0.28)), lineWidth: 1)
                let clean = states[m.id]?.isClean ?? true
                ctx.fill(Path(ellipseIn: CGRect(x: m.mount.x - 2.4, y: m.mount.y - 2.4,
                                                width: 4.8, height: 4.8)),
                         with: .color(clean ? Brand.success : Brand.danger))
            }
        }
    }

    private func tagColumn(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(mounts) { m in
                let st = states[m.id] ?? ES30MountState(checked: 0, failed: 0)
                HStack(alignment: .top, spacing: 6.5 * s) {
                    Group {
                        if m.isUntracked {
                            Rectangle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 3 * s,
                                                                 dash: [3 * s, 3 * s]))
                                .foregroundStyle(palette.textTertiary)
                                .frame(width: 3 * s)
                        } else {
                            Capsule().fill(st.isClean ? Brand.success : Brand.danger)
                                .frame(width: 3 * s)
                        }
                    }
                    .frame(height: 16 * s)
                    VStack(alignment: .leading, spacing: 1.5 * s) {
                        Text(m.title)
                            .font(.system(size: 7.5 * s, weight: .heavy)).tracking(0.2 * s)
                            .foregroundStyle(palette.textPrimary)
                        Text(m.isUntracked ? "UNTRACKED" : st.line)
                            .font(.custom(Self.mono, size: 7 * s).weight(.bold))
                            .foregroundStyle(m.isUntracked ? palette.textTertiary
                                             : (st.isClean ? okInk : badInk))
                        if case .untracked(let reason) = m.register {
                            Text(reason)
                                .font(.custom(Self.mono, size: 7 * s).weight(.bold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                .fixedSize()
                .offset(x: 298 * s, y: (m.tagBaseline - 11) * s)
            }
        }
    }

    /// Three independently placed baselines, not a stack with a nested overlay:
    /// an offset inside an already-offset container compounds, and the
    /// "NOT TO SCALE" line belongs under the ground line.
    private func footers(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text("NOT TO SCALE · MAST DRAWN BROKEN")
                .font(.custom(Self.mono, size: 7 * s).weight(.bold))
                .offset(x: 16 * s, y: 210 * s)
            Text("MOUNT POINTS ARE PHYSICAL · STATE IS LONGITUDINAL ACROSS \(archiveDepth) ARCHIVED CHECKS")
                .font(.custom(Self.mono, size: 7.5 * s).weight(.bold))
                .offset(x: 16 * s, y: 226 * s)
            Text("THIS-MOVE PASS/FAIL IS NOT HERE — IT LIVES ON THE PRE-TRIP VEHICLE CHECK")
                .font(.custom(Self.mono, size: 7.5 * s).weight(.bold))
                .offset(x: 16 * s, y: 238 * s)
        }
        .foregroundStyle(palette.textTertiary)
        .lineLimit(1).minimumScaleFactor(0.6)
    }
}

// MARK: - The receipt stack
//
// Overlapping dated slips receding into depth, most recent face-up. The
// face-up slip is this screen's ONE ActiveCard (rx20 outer / 18.5 inner, one
// gradient rim). Each slip behind it is inset 10pt further, runs 28pt longer,
// and fades one step — that inset + length + fade is the depth, and it encodes
// recency without a table.

private struct ES30ReceiptStackView: View {
    let rows: [ES30Row]
    let palette: Theme.Palette
    let okInk: Color
    let badInk: Color

    private static let mono = "Geist Mono"
    private static let dims: [Double] = [0.85, 0.70, 0.55, 0.45]

    var body: some View {
        let visible = Array(rows.prefix(5))
        ZStack(alignment: .top) {
            ForEach(Array(visible.dropFirst().enumerated()).reversed(), id: \.element.id) { idx, row in
                let inset = CGFloat(10 * (idx + 1))
                let height = CGFloat(100 + 28 * (idx + 1))
                slip(row, height: height, dim: Self.dims[min(idx, Self.dims.count - 1)])
                    .padding(.horizontal, inset)
            }
            if let face = visible.first { faceCard(face) }
        }
        .frame(height: CGFloat(100 + 28 * max(0, visible.count - 1)), alignment: .top)
    }

    private func slip(_ row: ES30Row, height: CGFloat, dim: Double) -> some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint))
            HStack(spacing: 10) {
                Capsule().fill(row.passed ? Brand.success : Brand.danger)
                    .frame(width: 3, height: 15)
                Text(ES30Fmt.stamp(row.signedAt))
                    .font(.custom(Self.mono, size: 9.5).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 6)
                Text(ES30Fmt.odometer(row.odometer))
                    .font(.custom(Self.mono, size: 8.5))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 6)
                Text(ES30Fmt.verdict(row))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(row.passed ? okInk : badInk)
            }
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 12).padding(.bottom, 8)
            .opacity(dim)
        }
        .frame(height: height, alignment: .top)
    }

    /// The one ActiveCard on this screen: rx20 gradient rim, rx18.5 inner.
    private func faceCard(_ row: ES30Row) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill((row.passed ? Brand.success : Brand.danger).opacity(0.14))
                    Image(systemName: row.passed ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.system(size: 18))
                        .foregroundStyle(row.passed ? okInk : badInk)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ES30Fmt.stampLong(row.signedAt))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(ES30Fmt.faceSub(row))
                        .font(.custom(Self.mono, size: 11)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ES30Fmt.verdict(row))
                        .font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(row.passed ? okInk : badInk)
                    Text(ES30Fmt.age(row.signedAt))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Divider().overlay(palette.borderFaint).padding(.top, 12)
            HStack {
                Text("CERTIFICATE ON FILE · JSON ONLY, NO PDF")
                    .font(.custom(Self.mono, size: 8).weight(.bold))
                Spacer(minLength: 8)
                Text("ASSIGNMENT \(row.assignmentId)")
                    .font(.custom(Self.mono, size: 8).weight(.heavy))
            }
            .foregroundStyle(palette.textTertiary)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .frame(height: 100)
        .background(RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard))
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(LinearGradient(
            colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
            startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

// MARK: - Formatting
//
// Nothing here synthesizes a value. Each function takes a nullable field off
// the wire and either renders it or renders its absence. ES-15 computed clock
// times as `5*60 + idx*45` and drew them as server data; these guards are why
// that cannot happen on this surface.

private enum ES30Fmt {
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFrac.date(from: s) ?? isoPlain.date(from: s)
    }

    static func stamp(_ s: String?) -> String {
        guard let d = date(s) else { return "TIME NOT ON FILE" }
        let f = DateFormatter(); f.dateFormat = "E dd MMM · HH:mm"
        return f.string(from: d)
    }

    static func stampLong(_ s: String?) -> String {
        guard let d = date(s) else { return "Signing time not on file" }
        let f = DateFormatter(); f.dateFormat = "EEE dd MMM · HH:mm"
        return f.string(from: d)
    }

    static func age(_ s: String?) -> String {
        guard let d = date(s) else { return "—" }
        let hrs = Int(Date().timeIntervalSince(d) / 3600)
        if hrs < 1 { return "JUST NOW" }
        if hrs < 48 { return "\(hrs) H AGO" }
        return "\(hrs / 24) D AGO"
    }

    static func odometer(_ v: Int?) -> String {
        guard let v else { return "NO ODOMETER" }
        let f = NumberFormatter(); f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " MI"
    }

    static func faceSub(_ row: ES30Row) -> String {
        let total = ES30Keys.all.count
        let ok = total - row.failedItems.count
        return "\(odometer(row.odometer)) · \(ok) OF \(total) OK · \(row.photoCount) PHOTOS"
    }

    static func verdict(_ row: ES30Row) -> String {
        if row.passed { return "PASSED" }
        if row.failedItems.count == 1 { return "1 FAIL · \(human(row.failedItems[0]))" }
        return "\(row.failedItems.count) FAIL"
    }

    /// Keys never reach glass as keys. ES-06 retracted exactly this fallback on
    /// 2026-07-28 after it showed DB keys to a pilot-car driver.
    static func human(_ key: String) -> String {
        key.split(separator: "_").map { $0.uppercased() }.joined(separator: " ")
    }
}

// MARK: - Registered surface wrapper

struct EscortVehicleRegistryES30Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortVehicleRegistryES30()
        } nav: {
            // The registry hangs off ME beside the cert wallet and the profile —
            // it is a persistent record of the operator, not of a move. Escort
            // enum HOME · ASSIGNMENTS · [ESang orb] · CORRIDOR · ME
            // (EscortNavController.swift:77-85; orb :63).
            BottomNav(
                leading: EscortNavRoute.leading(current: .me),
                trailing: EscortNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

// MARK: - Previews (DEBUG only; `.task` does not run in the canvas, so both
//         variants render in their loading register without touching the network)

#if DEBUG
#Preview("ES-30 · Vehicle & Equipment Registry · Light") {
    EscortVehicleRegistryES30Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("ES-30 · Vehicle & Equipment Registry · Dark") {
    EscortVehicleRegistryES30Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#endif
