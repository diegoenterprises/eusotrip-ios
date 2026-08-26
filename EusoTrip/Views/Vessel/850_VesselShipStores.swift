//
//  850_VesselShipStores.swift
//  EusoTrip — Vessel Operator · Ship's Stores & Crew Effects · IMO FAL Forms 3 + 4 (850).
//
//  Port of "850 Vessel Ship's Stores & Crew Effects.svg" (Light + Dark).
//
//  ARCHETYPE — TWO-PANEL QUANTITY MANIFEST + SEAL REGISTER.
//  FAL 3 (Ship's Stores) and FAL 4 (Crew's Effects) are two declarations
//  lodged together at the same arrival, and the only question either of them
//  exists to answer is a QUANTITY one: how much was DECLARED, how much was
//  SEALED under bond, how much was LANDED. Every line on this screen therefore
//  carries three quantity cells against one declared unit, and the two forms
//  are two PANELS of one manifest rather than two screens — a stores line and
//  a crew-effects line reconcile against the same customs officer's visit.
//  Beneath the manifest sits the SEAL REGISTER: the numbered customs seals on
//  the ship's bonded spaces, because a stores declaration is only worth the
//  seal that closes it, and a broken seal is the finding an officer acts on.
//
//  Sibling separation — this band is dense with customs surfaces, so the
//  separation is stated rather than assumed:
//    · 828 (Bonded Warehouse / FTZ) is SHORE-SIDE and financial — a
//      duty-in-suspense hero, a three-segment custody split bar and an
//      admissions/withdrawals double-entry ledger. It reconciles MONEY in
//      suspense. 850 holds no money at all: it reconciles QUANTITY aboard, and
//      the ship's own lockers are not a zone.
//    · 838 (AMS 24-Hour Manifest) declares CARGO to CBP before loading. Stores
//      and crew effects are explicitly NOT cargo — they never appear on a
//      manifest, are never entered, and move under bond aboard.
//    · 846 (Crew Change) moves PEOPLE on and off the ship. 850's crew panel
//      does not move anybody: it declares what the people already aboard are
//      carrying.
//    · 843 (Ballast) is a hull plan with a gate; 842 (Bunkering) is a two-party
//      transaction with a graduated sulphur axis. Neither shares a spine here.
//
//  WIRING (honest — every line number read off the live router this fire):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts:561 ·
//        vesselProcedure · input { id: Int }). Returns a FLAT spread of the
//        vessel_shipments row plus { lifecycleStage, bols, customs, events,
//        demurrage, containers, originPort, destinationPort } — there is NO
//        `shipment` wrapper key, so this screen decodes off the ROOT. The
//        booking, the voyage and both port rows are live and drive the header.
//    REAL — vesselShipments.getPortDetails (vesselShipments.ts:2313 ·
//        vesselProcedure · input { portId: Int }) → the ports row + berths.
//        A stores declaration is lodged AT a port to that port's customs
//        office, so the port identity (name, UN/LOCODE, country, customsOffice)
//        is read for real and the country regime below is selected from it
//        rather than assumed. Arrival port first, load port as the fallback.
//    REAL — vesselShipments.getVesselCrew (vesselShipments.ts:2417 ·
//        vesselProcedure · input { companyId?, search? }) → { crew[],
//        certifications[], expiringCount }. This is the honest source for the
//        FAL 4 panel: the people aboard are real, so the crew-effects panel
//        lists real crew rather than invented ones. HONESTY CONSTRAINT: the
//        procedure has no shipmentId / callId / voyageId input — it scopes by
//        COMPANY, not by ship. The panel says so on its own header rather than
//        implying the roster was filtered to this hull.
//    REAL (fixed regulatory reference, not data) — the FAL 3 line items and the
//        FAL 4 declarable classes are the FORM, printed the way 843 prints the
//        D-2 ceiling. IMO FAL Convention Forms 3 and 4; US enforcement CBP
//        19 CFR 4.7 (CBP Forms 1303 Ship's Stores Declaration / 1304 Crew's
//        Effects Declaration). Printing the form is not inventing a reading.
//    STUB · named-gap — vessel.getShipStores({ shipmentId, portId }). Grepped
//        repo-wide this fire: `shipStores|crewEffects` = 0 occurrences. There
//        is no stores model, no bonded-locker model and no seal table on disk.
//        Proposed TS shape:
//            getShipStores: vesselProcedure
//              .input(z.object({ shipmentId: z.number(), portId: z.number().optional() }))
//              .query(): {
//                declaredAt: string | null,
//                officerBadge: string | null,
//                stores: { line: "tobacco"|"spirits"|"wineBeer"|"provisions"
//                                |"medicines"|"bunkers"|"freshWater",
//                          unit: string,
//                          declaredQty: number | null,
//                          sealedQty: number | null,
//                          landedQty: number | null,
//                          bondState: "sealed"|"free"|"landed"|"unverified" }[],
//                crewEffects: { userId: number,
//                               effectsDeclared: boolean | null,
//                               currencyOverThreshold: boolean | null,
//                               dutiableGoods: boolean | null,
//                               lineFiledAt: string | null }[],
//                seals: { space: string, sealNumber: string,
//                         appliedBy: string, appliedAt: string,
//                         intact: boolean | null, brokenAt: string | null }[],
//                discrepancies: { line: string, note: string }[]
//              }
//        Until it ships, every declared / sealed / landed cell is an em-dash,
//        every crew line reads NO FAL 4 LINE, and the seal register renders its
//        three bonded spaces UNSEALED with no number.
//    STUB · named-gap REGULATORY — vessel.sealBondedLocker({ shipmentId,
//        space, sealNumber, confirm: true }) [gated + confirm:true + audit +
//        test]; writes the ship_stores_seal row + blockchainAuditTrail
//        vessel.bond_sealed and broadcasts WS_CHANNELS.VESSEL_OPS /
//        WS_EVENTS.BOND_SEALED. RBAC vesselProcedure (master / ship's agent).
//    STUB · named-gap — vessel.recordStoresDiscrepancy({ shipmentId, line,
//        declaredQty, foundQty, note, confirm: true }) [gated + audit].
//    NOT WIRED, and why — vesselShipments.createCustomsEntry:1349 and
//        vesselShipments.updateCustomsStatus:1401 are REAL customs mutations
//        and were read first-hand before this note was written. createCustomsEntry
//        takes { shipmentId, declarationType: import|export|transit|
//        temporary_import, htsCode?, countryOfOrigin?, declaredValue?, currency,
//        dutyRate?, brokerId? } and inserts a customsDeclarations row. That row
//        is a CARGO ENTRY: an HTS-classified, valued, duty-rated declaration of
//        merchandise. Ship's stores and crew effects are the one class of goods
//        that is expressly NOT entered — they are declared on FAL 3 / FAL 4 and
//        held under seal. Forcing this manifest through createCustomsEntry
//        would file a cargo entry that no officer asked for, and the fields the
//        screen actually owns (quantity, unit, locker, seal number) have
//        nowhere to land in that shape. The input does NOT honestly fit, so it
//        is not called. Same reasoning for updateCustomsStatus: it moves a
//        customsDeclarations row through draft→filed→cleared, and a bonded
//        locker's seal is not a declaration status.
//
//  OFFLINE POLICY (doctrine W):
//    READ  · READ_CACHED(15m) — the manifest and the seal register may be
//            served from the last decoded payload. A stores list is a readable
//            list even when it is an hour old, and nothing on the read side is
//            a decision. The staleness is made unmistakable rather than
//            implied: a retained serve paints the manifest with a dashed rim
//            and prints an explicit AS OF line above it. HONEST SCOPE OF THAT
//            TIER: what this file actually does is retain the last decoded
//            serve IN MEMORY for the life of the session and flag a failed
//            refresh above it. Services/EusoTripAPI.swift sets
//            .reloadIgnoringLocalAndRemoteCacheData with urlCache = nil, so
//            nothing survives a cold launch and the 15m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(a customs seal is a legal act) — confirming a seal
//            asserts that a named officer closed a named space at a named
//            minute under a numbered seal. Queued and replayed later it would
//            record a seal that may never have been applied, or backdate one
//            that was. A discrepancy record carries the same weight in the
//            other direction: it is the opening move of a customs finding.
//            Neither is ever queued.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.BOND_SEALED on WS_CHANNELS.VESSEL_OPS, read by the
//    compliance surface (652) and by 851 Clearance, whose OUTWARD gate holds a
//    "stores sealed under bond" condition that this screen is the source of.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does not exist — RealtimeService.swift carries no vessel:* case and
//    Views/Vessel has zero realtime subscribers, so a sealed locker would land
//    on no listener. Named rather than papered over.
//
//  COUNTRY (single-country content, never a file fork) — selected from the live
//    port row's country, not stamped: US CBP 19 CFR 4.7 · Forms 1303 / 1304,
//    currency reportable over USD 10,000 (FinCEN 105) · CA CBSA sealed marine
//    stores, currency reportable over CAD 10,000 (form E677) · MX Aduanas
//    rancho de nave, currency reportable over USD 10,000.
//
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME — matches the SVG
//  NAV field, which marks COMPLIANCE.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselShipStoresScreen: View {
    let theme: Theme.Palette
    /// vessel_shipments.id — the call whose stores are declared. 0 = nothing
    /// threaded; the screen renders an honest "no call selected" state rather
    /// than inventing a ship.
    var shipmentId: Int = 0
    /// ports.id of the declaration port. 0 = resolve from the shipment's
    /// destination (arrival) port, then its origin port.
    var portId: Int = 0
    /// Optional tenant scope for the crew roster. Omitted by default so the
    /// server scopes from ctx.user.companyId.
    var companyId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselShipStoresBody(shipmentId: shipmentId, portId: portId, companyId: companyId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes

/// The ports row as getPortDetails:2313 and getVesselShipmentDetail:561 both
/// return it (drizzle/schema.ts `ports`). `berths` is present on the
/// getPortDetails serve only and is not read here.
private struct StoresPort850: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let city: String?
    let country: String?
    let customsOffice: String?
}

/// getVesselShipmentDetail:561 returns `{ ...shipment, lifecycleStage, bols,
/// customs, events, demurrage, containers, originPort, destinationPort }`.
/// Decoded off the ROOT — there is no wrapper key, and decoding a wrapper
/// against the real payload does not throw, it silently yields nil and the
/// screen renders its awaiting state forever.
private struct StoresDetail850: Decodable {
    let id: Int?
    let bookingNumber: String?
    let billOfLading: String?
    let voyageNumber: String?
    let originPortId: Int?
    let destinationPortId: Int?
    let status: String?
    let originPort: StoresPort850?
    let destinationPort: StoresPort850?
}

/// getVesselCrew:2417 crew row — the select list at vesselShipments.ts:2432.
private struct StoresCrew850: Decodable, Identifiable {
    let id: Int
    let name: String?
    let email: String?
    let role: String?
    let isActive: Bool?
}

private struct StoresCrewPayload850: Decodable {
    let crew: [StoresCrew850]
}

// MARK: - The FAL 3 form (printed, not fetched)

/// One statutory line of IMO FAL Form 3. The line and its unit are the FORM;
/// the three quantities are data nobody has returned, so they are nil and
/// render as em-dashes. A nil quantity and a zero quantity are different legal
/// statements — "nothing declared" and "not yet declared" must never collapse
/// into each other — so the quantities are Optional rather than defaulted.
private struct StoresLine850: Identifiable {
    let id: String
    let name: String
    let category: String
    let unit: String
    var declared: Double? = nil
    var sealed: Double? = nil
    var landed: Double? = nil
}

/// The three bonded spaces a customs officer seals on a stores declaration.
/// The spaces are the ship's fixed arrangement; the seal number, the officer
/// and the minute are data and stay absent.
private struct SealSlot850: Identifiable {
    let id: String
    let space: String
    let holds: String
    var sealNumber: String? = nil
    var appliedBy: String? = nil
    var appliedAt: String? = nil
    var intact: Bool? = nil
}

// MARK: - Body

private struct VesselShipStoresBody: View {
    @Environment(\.palette) private var palette

    let shipmentId: Int
    let portId: Int
    let companyId: Int

    @State private var detail: StoresDetail850? = nil
    @State private var port: StoresPort850? = nil
    @State private var crew: [StoresCrew850] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    /// The minute the content on screen was decoded. Drives the staleness line;
    /// nil until a serve lands.
    @State private var servedAt: Date? = nil
    @State private var panel: StoresPanel850 = .stores

    private enum StoresPanel850: String, CaseIterable {
        case stores = "FAL 3 · Ship's stores"
        case effects = "FAL 4 · Crew effects"
    }

    /// IMO FAL Form 3, line for line. Fixed content; declared once for the
    /// process so the ForEach identity is stable across re-renders.
    private static let falThree: [StoresLine850] = [
        StoresLine850(id: "tobacco",    name: "Tobacco · cigarettes & cigars", category: "TOBACCO",  unit: "sticks"),
        StoresLine850(id: "spirits",    name: "Spirits & liquor",              category: "ALCOHOL",  unit: "L"),
        StoresLine850(id: "wineBeer",   name: "Wine & beer",                   category: "ALCOHOL",  unit: "L"),
        StoresLine850(id: "provisions", name: "Provisions · victualling",      category: "FOOD",     unit: "kg"),
        StoresLine850(id: "medicines",  name: "Medicines & controlled drugs",  category: "PHARMA",   unit: "items"),
        StoresLine850(id: "bunkers",    name: "Bunkers remaining on board",    category: "FUEL",     unit: "MT"),
        StoresLine850(id: "freshWater", name: "Fresh water",                   category: "WATER",    unit: "m³")
    ]

    private static let sealSlots: [SealSlot850] = [
        SealSlot850(id: "bondStore", space: "Bonded store locker",     holds: "tobacco · duty-free sales stock"),
        SealSlot850(id: "spirits",   space: "Spirits & tobacco locker", holds: "spirits · wine · beer"),
        SealSlot850(id: "drugs",     space: "Controlled drugs cabinet", holds: "narcotics & psychotropics")
    ]

    // MARK: Derived context (never fabricated)

    /// The port the declaration is lodged at: the live getPortDetails row when
    /// it resolved, otherwise the port row that rode in on the shipment detail.
    private var declarationPort: StoresPort850? {
        port ?? detail?.destinationPort ?? detail?.originPort
    }

    private var portTitle: String {
        declarationPort?.name ?? (shipmentId > 0 ? "Port not resolved" : "No call selected")
    }

    private var portCode: String? {
        declarationPort?.unlocode?.uppercased()
    }

    private var countryCode: String {
        (declarationPort?.country ?? "US").uppercased()
    }

    private var voyageLine: String {
        guard let d = detail else {
            return shipmentId > 0 ? "Call not loaded · FAL 3 + 4 declaration"
                                  : "No call threaded · FAL 3 + 4 declaration"
        }
        let booking = d.bookingNumber ?? "booking —"
        if let voy = d.voyageNumber, !voy.isEmpty {
            return "\(booking) · voy \(voy) · stores & effects under bond"
        }
        return "\(booking) · stores & effects under bond"
    }

    /// Currency-reporting threshold printed on the FAL 4 panel. This is the
    /// governing rule for the port's country, not a reading of anybody's
    /// wallet.
    private var currencyRule: String {
        switch countryCode {
        case "CA": return "Currency or monetary instruments over CAD 10,000 are reportable · CBSA E677"
        case "MX": return "Currency or monetary instruments over USD 10,000 are reportable · Aduanas"
        default:   return "Currency or monetary instruments over USD 10,000 are reportable · FinCEN 105"
        }
    }

    private var regulatorRows: [VesselRegulatorRow] {
        [
            .init("US", "CBP 19 CFR 4.7 · Forms 1303 / 1304",  active: countryCode == "US"),
            .init("CA", "CBSA · sealed marine stores",          active: countryCode == "CA"),
            .init("MX", "Aduanas · rancho de nave",             active: countryCode == "MX")
        ]
    }

    /// A retained serve that a refresh failed to replace. Everything the
    /// manifest paints in this state is last-known, not current.
    private var servingStale: Bool { loadError != nil && detail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · SHIP'S STORES & EFFECTS",
                caption: "FAL 3 · 4 · BOND",
                title: portTitle,
                idText: portCode,
                subtitle: voyageLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading && detail == nil {
                    skeleton
                } else if let err = loadError, detail == nil {
                    VesselErrorCard(text: err)
                    emptyCallNote
                } else {
                    if servingStale { staleBanner }
                    bondHero
                    manifestSection
                    sealRegisterSection
                    VesselSummaryStrip(
                        label: "Declared — · sealed — · landed — · discrepancies —",
                        value: "no stores record",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "BOND AUTHORITY · SINGLE-COUNTRY",
                        reference: "port · \(countryCode)",
                        rows: regulatorRows
                    )
                    lockedActions
                    VesselGapNote(text: "Vessel, booking, declaration port, and company roster are available. Ship-stores quantities, bonded-locker seals, and landed quantities have not been provided, so they remain unknown. No value is estimated.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Staleness (READ_CACHED made unmistakable)

    private var staleBanner: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOT LIVE · AS OF \(Self.clock(servedAt))")
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                Text("Refresh failed — \(loadError ?? "no reason returned") The manifest below is the last serve this session returned and is not being updated.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.55),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var emptyCallNote: some View {
        VesselGapNote(text: "No vessel call is threaded into this screen, so there is nothing to declare against. A stores declaration belongs to one arrival at one port; the screen refuses to render a generic one.")
    }

    // MARK: - Hero: the three quantities the whole declaration turns on

    private var bondHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text(declarationPort?.customsOffice.map { "Declared to \($0)" } ?? "Customs office not on the port row")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("BOND STATE UNVERIFIED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(palette.tintNeutral))
                        .overlay(
                            Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                                   style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                        )
                }
                // The reconciliation, stated as the screen's premise. Three
                // figures, neutral, never green — a green SEALED figure nobody
                // reported is exactly the lie a seal exists to prevent.
                HStack(alignment: .top, spacing: Space.s3) {
                    quantityPillar(label: "DECLARED", value: "—", detail: "FAL 3 lines")
                    pillarDivider
                    quantityPillar(label: "SEALED",   value: "—", detail: "under bond")
                    pillarDivider
                    quantityPillar(label: "LANDED",   value: "—", detail: "duty paid")
                }
                Text("Ship's stores and crew's effects are not cargo: they are declared on FAL 3 and FAL 4 and held under customs seal, never entered. The declaration reconciles when declared equals sealed plus landed.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.shield.checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("Boarding officer — · badge — · visit —:—")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func quantityPillar(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .monospaced)).tracking(-0.5)
                .foregroundStyle(palette.textTertiary)
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pillarDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 46)
    }

    // MARK: - The two-panel manifest

    private var manifestSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(
                // NOT "aboard". getVesselCrew:2417 scopes by COMPANY — it has
                // no shipmentId / voyageId input — so the count is labelled as
                // the roster it actually is. A company roster rendered as a
                // ship's complement is the quiet kind of lie this band exists
                // to stop.
                label: panel == .stores ? "DECLARED ITEMS · 7 FAL 3 LINES" : "CREW EFFECTS · \(crew.count) ON COMPANY ROSTER",
                right: "Record not connected"
            )
            panelSelector
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    if panel == .stores { storesPanel } else { effectsPanel }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(servingStale ? Brand.warning.opacity(0.5) : Color.clear,
                                  style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            panelFooter
        }
    }

    /// A real segmented control over the two forms. This switches which PANEL
    /// is on screen and writes nothing anywhere — it is a view mode, not a
    /// local imitation of persistence.
    private var panelSelector: some View {
        HStack(spacing: 0) {
            ForEach(StoresPanel850.allCases, id: \.self) { option in
                Button {
                    panel = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.3)
                        .foregroundStyle(panel == option ? Color.white : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(panel == option ? AnyShapeStyle(LinearGradient.primary)
                                                      : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.rawValue)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCardSoft))
    }

    // MARK: FAL 3 panel — the quantity manifest

    private var storesPanel: some View {
        VStack(spacing: 0) {
            quantityHeaderRow
            ForEach(Array(Self.falThree.enumerated()), id: \.element.id) { idx, line in
                if idx > 0 { Divider().overlay(palette.borderFaint) }
                storesRow(line)
            }
        }
    }

    private var quantityHeaderRow: some View {
        HStack(spacing: 0) {
            Text("LINE")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("DECL.")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 46, alignment: .trailing)
            Text("SEALED")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 50, alignment: .trailing)
            Text("LANDED")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.bottom, 6)
    }

    private func storesRow(_ line: StoresLine850) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    HStack(spacing: 5) {
                        Text(line.category)
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Brand.blue.opacity(0.14)))
                        Text("in \(line.unit)")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                quantityCell(line.declared, width: 46)
                quantityCell(line.sealed,   width: 50)
                quantityCell(line.landed,   width: 50)
            }
            HStack(spacing: 5) {
                Text("NO DECLARATION")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(Capsule().fill(palette.tintNeutral))
                    .overlay(
                        Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                               style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                    )
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.s3)
    }

    /// A quantity cell has exactly two renderings: a returned figure or an
    /// em-dash. There is no third, and no zero stands in for silence.
    private func quantityCell(_ value: Double?, width: CGFloat) -> some View {
        Text(value.map { Self.qty($0) } ?? "—")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
            .frame(width: width, alignment: .trailing)
    }

    // MARK: FAL 4 panel — real people, unfiled lines

    private var effectsPanel: some View {
        VStack(spacing: 0) {
            effectsHeaderRow
            if crew.isEmpty {
                HStack(spacing: Space.s3) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text(loading ? "Loading the roster…" : "No crew returned for this company. A FAL 4 declaration is one line per person aboard, so the panel stays empty rather than inventing one.")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s4)
            } else {
                ForEach(Array(crew.enumerated()), id: \.element.id) { idx, member in
                    if idx > 0 { Divider().overlay(palette.borderFaint) }
                    effectsRow(member)
                }
            }
        }
    }

    private var effectsHeaderRow: some View {
        HStack(spacing: 0) {
            Text("PERSON")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("EFFECTS")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 52, alignment: .trailing)
            Text("CURR.")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 42, alignment: .trailing)
            Text("DUTIABLE")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.bottom, 6)
    }

    private func effectsRow(_ member: StoresCrew850) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: Space.s2) {
                initialsDisc(for: member.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name ?? "Name not set")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(Self.rankLabel(member.role))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            effectsCell(width: 52)
            effectsCell(width: 42)
            effectsCell(width: 52)
        }
        .padding(.vertical, Space.s3)
    }

    private func effectsCell(width: CGFloat) -> some View {
        Text("—")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(width: width, alignment: .trailing)
    }

    /// Initials disc for a party — the house device. Never a glyph, and never
    /// an invented pair of letters: an unnamed person shows an em-dash.
    private func initialsDisc(for name: String?) -> some View {
        let initials = Self.initials(name)
        return ZStack {
            Circle().fill(palette.tintNeutral).frame(width: 26, height: 26)
            Text(initials)
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var panelFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: panel == .stores ? "shippingbox" : "banknote")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(panel == .stores
                     ? "Quantities are declared per line at arrival and re-checked at departure"
                     : currencyRule)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            if panel == .effects {
                // The scoping caveat, stated once and plainly rather than
                // buried in a header note nobody reads.
                Text("The available roster is company-wide and does not establish this vessel's signed-on complement.")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Seal register

    private var sealRegisterSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CUSTOMS SEAL REGISTER · 3 BONDED SPACES",
                                right: "0 SEALS ON RECORD")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.sealSlots.enumerated()), id: \.element.id) { idx, slot in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        sealRow(slot)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "seal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("0 seal numbers on record — nothing to verify against")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    private func sealRow(_ slot: SealSlot850) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: slot.sealNumber == nil ? "lock.open" : "lock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.space)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(slot.holds)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(slot.sealNumber ?? "SEAL —")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                Text(slot.sealNumber == nil ? "NO SEAL RECORDED" : "APPLIED \(slot.appliedAt ?? "—")")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 2.5)
                    .background(Capsule().fill(palette.tintNeutral))
                    .overlay(
                        Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                               style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                    )
            }
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Actions (both ONLINE_ONLY · both disabled behind a named gap)

    private var lockedActions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("Seal confirmation and stores-discrepancy recording are unavailable until a ship-stores record is connected.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: "Confirm seals", action: {}, trailingIcon: "seal")
                    .opacity(0.55)
                    .disabled(true)
                    .accessibilityHint("Unavailable until a ship-stores record is connected")
                VesselGhostButton(title: "Discrepancy", width: 150) {}
                    .opacity(0.55)
                    .disabled(true)
                    .accessibilityHint("Unavailable until a ship-stores record is connected")
            }
            VesselGapNote(text: "Seal confirmation records a numbered customs seal for a named space and time. A discrepancy record opens a customs finding. Both are legal acts that require an online confirmation and are never queued. A cargo-duty entry cannot substitute for ship's stores held under seal.")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 300)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail · getPortDetails · getVesselCrew)

    private func load() async {
        loading = true
        loadError = nil

        struct DetailIn: Encodable { let id: Int }
        struct PortIn: Encodable { let portId: Int }
        struct CrewIn: Encodable { let companyId: Int?; let search: String? }

        var failures: [String] = []

        // 1. The call. Everything else keys off it, so it is read first rather
        //    than raced — the port id is not known until this returns.
        if shipmentId > 0 {
            do {
                let d: StoresDetail850? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
                if let d { self.detail = d }
            } catch {
                // The prior serve is deliberately NOT cleared. A failed refresh
                // keeps the manifest on screen under an explicit NOT LIVE
                // banner rather than blanking a page an officer may be reading.
                failures.append(error.eusoUserCopy)
            }
        }

        // 2. The declaration port — the arrival port of this call, falling back
        //    to the load port, falling back to whatever was threaded in.
        let resolvedPortId = portId > 0
            ? portId
            : (detail?.destinationPortId ?? detail?.originPortId ?? 0)
        if resolvedPortId > 0 {
            do {
                let p: StoresPort850? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: resolvedPortId))
                if let p { self.port = p }
            } catch {
                failures.append(error.eusoUserCopy)
            }
        }

        // 3. The people aboard — the honest source for the FAL 4 panel.
        //    companyId is omitted unless the host threaded one so the server
        //    scopes from ctx.user.companyId rather than a caller-chosen tenant.
        do {
            let payload: StoresCrewPayload850 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew",
                input: CrewIn(companyId: companyId > 0 ? companyId : nil, search: nil))
            // Unconditional overwrite — an honest empty roster empties the panel.
            self.crew = payload.crew
        } catch {
            failures.append(error.eusoUserCopy)
        }

        if failures.isEmpty {
            servedAt = Date()
        } else {
            loadError = failures.joined(separator: " · ")
        }
        loading = false
    }

    // MARK: - Formatting helpers

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func clock(_ date: Date?) -> String {
        guard let date else { return "—:—" }
        return clockFormatter.string(from: date)
    }

    private static func qty(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.0f", value) }
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static func initials(_ name: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "—" : letters.uppercased()
    }

    /// The role enum getVesselCrew filters on (vesselShipments.ts:2426),
    /// rendered as the rank a declaration would name.
    private static func rankLabel(_ role: String?) -> String {
        switch role?.uppercased() {
        case "SHIP_CAPTAIN":    return "Master"
        case "VESSEL_OPERATOR": return "Vessel operator"
        case "PORT_MASTER":     return "Port master"
        case "VESSEL_BROKER":   return "Broker"
        case "CUSTOMS_BROKER":  return "Customs broker"
        case "VESSEL_SHIPPER":  return "Shipper"
        default:                return "Role not set"
        }
    }
}

#Preview("850 · Vessel Ship's Stores & Crew Effects · Night") {
    VesselShipStoresScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("850 · Vessel Ship's Stores & Crew Effects · Light") {
    VesselShipStoresScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
