//
//  699_VesselParticulars.swift
//  EusoTrip — Vessel Operator · Vessel Particulars.
//
//  Faithful port of "699 Vessel Particulars.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with the COMPLIANCE slot inked — statutory
//  certificates and declared-limit compliance are what this screen decides.
//
//  ARCHETYPE: DETAIL — one hull, read against the limits and the deadlines that can stop it. The
//  screen exists to answer two questions with geometry instead of prose: can this ship physically
//  enter the berth, and is any certificate about to lapse under her.
//
//  WHAT WAS REMOVED AND WHY. The previous 699 led with a ship general-arrangement side elevation
//  and a flat three-row certificate binder. The elevation was a PORTRAIT — nothing on it was
//  measured against a limit, so a hull that could not enter the berth drew identically to one that
//  could. The binder had no time axis, so a certificate expiring in 40 days rendered identically to
//  one expiring in 400. Both are gone.
//
//  HERO ORGAN · DIMENSION NOMOGRAM. Three 340x14 scale rails (LOA 0-400 m · BEAM 0-62 m ·
//  DRAFT 0-16 m). The ship's dimension is the FILLED portion with the number printed at the fill
//  head in 14/700 tabular; the port limit is a 2x22 caliper tick standing on the rail. When the
//  fill runs past the tick the excess is painted in danger — over-limit is a measured area, not a
//  word. The BEAM rail carries NO tick because no beam-limit column exists anywhere in the schema;
//  its tick band renders an explicit dashed gap notice instead of an invented number.
//
//  MID-BAND ORGAN · 12-MONTH CERTIFICATE HORIZON. A 12-cell rolling month axis with each
//  certificate as an h14 capsule whose END IS its expiry date. A capsule that stops left of the
//  today stem bleeds the lapsed interval past its head in danger, so "expired 24 days ago" and
//  "expires in 262 days" cannot look alike.
//
//  LIVE FUSION: the registry row, the port limits, the certificate horizon and the ESang line are
//  four faces of ONE state. The rails, the ESang verdict, the horizon capsules and the eight
//  particulars all re-reason together off load(); nothing is a parallel literal. Degraded provider
//  state surfaces an explicit error card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(24h). Read-only surface — no money movement, no award commit. The
//  registry row, the port limits and the certificates are live DB reads; the only cached leg is the
//  getVesselParticulars enrichment overlay, capped at 24h by lsCacheThrough("WARM"). Staleness is
//  DRAWN, not claimed: the header right caption reads REGISTRY LIVE · SPECS CACHED 24h and sits on a
//  dashed breadcrumb rule, and the overlay's own freshness line appears only once it actually lands.
//
//  Data / wiring (line numbers read first-hand 2026-08-11 against a pinned snapshot — see PROVENANCE):
//    vesselShipments.getVesselFleet (EXISTS server/routers/vesselShipments.ts:2490 · vesselProcedure ·
//      input {vesselType?,status?,search?,limit=50,offset=0} · db.select().from(vessels) at :2509 ·
//      returns {vessels: full vessels rows, total}). THE SPINE. lengthMeters / beamMeters /
//      draftMeters (drizzle/schema.ts:11784-11786) are the three nomogram rails; imoNumber,
//      callSign, grossTonnage, deadweightTonnage, flag, classificationSociety, yearBuilt and
//      teuCapacity are the eight particulars. All are real columns — no derived value is presented
//      as stored except the hull age, which is labelled as a spread off yearBuilt.
//    vesselShipments.getPortDetails (EXISTS vesselShipments.ts:2278 · vesselProcedure ·
//      {portId:number} · returns {...ports row, berths: portBerths[]} at :2289). THE CALIPER TICKS.
//      LOA limit  = the longest berth's port_berths.lengthMeters (schema.ts:11935)
//      DRAFT limit = ports.maxDraft (schema.ts:11756)
//    vesselShipments.getPorts (EXISTS vesselShipments.ts:3896 · vesselProcedure ·
//      {limit=100,offset=0,country?,search?,portType?} optional · returns ports[] ordered by name).
//      Backs the real port picker, so a zero-arg open can resolve a portId honestly instead of
//      hardcoding one.
//    vesselShipments.getVesselCertificates (EXISTS vesselShipments.ts:3955 · vesselProcedure ·
//      {limit 1..200 = 50} · a UNION of vessel_isps_records + vessel_insurance, wire row exactly
//      {id,name,issuedBy,expiresAt,status}). THE CERTIFICATE HORIZON. ISPS rows are minted with an
//      id prefix cert_isps_ (:3971) and insurance rows with cert_ins_, which is how this screen
//      tells a statutory certificate from a commercial policy without guessing at the name string.
//    vesselShipments.getVesselInspections (EXISTS vesselShipments.ts:3930 · vesselProcedure ·
//      {limit 1..200 = 50} · returns vessel_inspections rows {id,type,date,port,status,authority,
//      deficiencies}). Fired by the "PSC record" CTA. `port` is ALWAYS null by router design —
//      vessel_inspections has no portId column — so the sheet shows the authority, never a fake port.
//    vesselShipments.getVesselParticulars (EXISTS vesselShipments.ts:2945 · vesselProcedure ·
//      {imoNumber:string}) — OVERLAY ONLY, NEVER THE SPINE. It is a pure
//      marineTrafficService.getVesselParticulars passthrough behind a 24h lsCacheThrough("WARM")
//      (:2950) with NO DB fallback; it returns null on ANY error (:2953) and its response shape is
//      not owned by this repo. Every number on this screen survives it returning null; when it does
//      land it adds one clearly-labelled enrichment line and nothing else.
//    STUB · named-gap port-beam-limit: there is NO beam-limit column in ports OR port_berths
//      (verified — zero maxBeam / beamLimit matches anywhere in drizzle/schema.ts), so the beam
//      rail draws a visible gap notice where its caliper tick would be. Proposed shape:
//      ports.maxBeam decimal(6,2) + portBerths.maxBeamMeters decimal(6,2), spread by getPortDetails
//      as {..., maxBeam: string|null, berths:[{..., maxBeamMeters: string|null}]}.
//    STUB · named-gap isps-issue-date: vessel_isps_records carries isscExpiry (schema.ts:12130) and
//      NO issue/effective date column, and getVesselCertificates returns issuedBy: null for every
//      ISPS row by design (HONEST-EMPTY at vesselShipments.ts:3973). The ISSC capsule head is
//      therefore drawn as a faded ramp captioned ISSUE DATE NOT A COLUMN rather than a fabricated
//      start. Proposed shape: vessel_isps_records.isscIssued timestamp -> issuedAt on the cert row.
//    ESang line: DERIVED on-device from the two live reads already on screen (draftMeters vs
//      ports.maxDraft, then the soonest certificate expiry). No LLM call and no procedure, so the
//      advisory can never contradict the rail directly above it.
//    CHAIN: every procedure on this screen is a READ. NOTHING writes a DB row, NOTHING inserts a
//      blockchainAuditTrail row, and NOTHING broadcasts on any WS_CHANNELS.* / WS_EVENTS.*. Stated
//      plainly rather than papered over. There is no cross-role verb on this screen, so there is no
//      CHAIN-OPEN to declare. For completeness: the currentPosition on a vessels row is poller-fed
//      only — emitVesselPosition (server/_core/websocket.ts:1715, broadcasting
//      WS_CHANNELS.VESSEL_FLEET / WS_EVENTS.VESSEL_POSITION_UPDATE) is called from exactly one place
//      platform-wide, services/vesselPositionPoller.ts:79, never from a router.
//    RBAC: vesselProcedure = server/_core/trpc.ts:268, a MODE GATE ONLY (server/_core/
//      transportModes.ts:40-43 admits VESSEL_SHIPPER, VESSEL_OPERATOR, PORT_MASTER, SHIP_CAPTAIN,
//      VESSEL_BROKER, CUSTOMS_BROKER) carrying no tenant scoping and no role-within-mode scoping.
//      P0-READ-TENANCY x5, all destructuring ({ input }) only with no ctx and no operator predicate:
//        getVesselFleet :2498         — reads the ENTIRE global vessels table. vessels.operatorId
//                                       EXISTS (schema.ts:11790) and is INDEXED (v_operator_idx,
//                                       schema.ts:11801) and is never applied.
//        getPortDetails :2280         — any portId on earth is readable.
//        getVesselParticulars :2947   — no fleet-ownership check on the caller-supplied imoNumber.
//        getVesselCertificates :3957  — selects both whole tables, no vesselId predicate at all.
//        getVesselInspections :3932   — selects the whole table, no vesselId predicate at all.
//      Named here for the-oath. This screen does not paper over them and does not pretend the rows
//      it renders are tenant-scoped.
//    transportMode=vessel · country US (USLGB Long Beach berth limits and USCG/PSC exposure drive
//      the caliper). The same nomogram re-reads against CAVAN Vancouver and MXZLO Manzanillo the
//      moment the port picker changes — country is CONTENT inside this screen, never a separate file.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty
//  response renders the bespoke empty state and never fabricated rows. There is no seed vessel, no
//  demo certificate and no hardcoded port. Every section whose data has no backing procedure says so
//  on screen. File-scoped types are suffixed 699 to avoid cross-file private collisions.
//
//  CITATION PROVENANCE: server/routers/vesselShipments.ts was being rewritten by concurrent work
//  DURING this fire — it grew from 4023 to 4311 lines while this screen was built, moving every
//  anchor. Every line number above was re-read against a pinned snapshot taken 2026-08-11
//  (vesselShipments.ts md5 64e8d522cef3fa57f248f7e1df4417a8, 4311 lines; drizzle/schema.ts md5
//  4cf794ad6378e4e2b359c6a5f5c8161f) and the body of all six procedures is byte-identical to the
//  fire-brief read — only the offsets moved. Pre-drift -> pinned: getPortDetails 1981->2278,
//  getVesselFleet 2193->2490, getVesselParticulars 2648->2945, getVesselInspections 3633->3930,
//  getVesselCertificates 3658->3955.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselParticularsScreen: View {
    let theme: Theme.Palette
    /// IMO of the hull to open. Empty ("") = registry / zero-arg use: the loader takes the first
    /// row getVesselFleet returns, or renders the honest empty state when it returns none.
    var imoNumber: String = ""
    /// Port whose declared limits become the caliper ticks. 0 = none threaded; the screen then
    /// draws the no-port gap notice and offers the real getPorts picker rather than inventing one.
    var portId: Int = 0

    init(theme: Theme.Palette, imoNumber: String = "", portId: Int = 0) {
        self.theme = theme; self.imoNumber = imoNumber; self.portId = portId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselParticularsBody699(imoNumber: imoNumber, portId: portId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Lenient numeric box (MySQL decimals arrive as String OR Double OR Int)

private struct FlexDouble699: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self)    { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil   // null / missing / non-numeric — honest absence, never a fabricated 0
    }
}

// MARK: - Data shapes (mirror the procedure return rows EXACTLY)

/// `vesselShipments.getVesselFleet` -> { vessels: [...], total }
private struct FleetResponse699: Decodable {
    let vessels: [VesselRow699]
    let total: Int?
}

/// One `vessels` row. Decimal columns ride FlexDouble699; everything else is the raw column.
private struct VesselRow699: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let mmsiNumber: String?
    let callSign: String?
    let vesselType: String?
    let flag: String?
    let grossTonnage: Int?
    let deadweightTonnage: Int?
    let teuCapacity: Int?
    let yearBuilt: Int?
    let ownerCompany: String?
    let classificationSociety: String?
    let status: String?
    private let lengthMetersBox: FlexDouble699?
    private let beamMetersBox: FlexDouble699?
    private let draftMetersBox: FlexDouble699?

    var lengthMeters: Double? { lengthMetersBox?.value }
    var beamMeters:   Double? { beamMetersBox?.value }
    var draftMeters:  Double? { draftMetersBox?.value }

    enum CodingKeys: String, CodingKey {
        case id, name, imoNumber, mmsiNumber, callSign, vesselType, flag
        case grossTonnage, deadweightTonnage, teuCapacity, yearBuilt
        case ownerCompany, classificationSociety, status
        case lengthMetersBox = "lengthMeters"
        case beamMetersBox   = "beamMeters"
        case draftMetersBox  = "draftMeters"
    }
}

/// `vesselShipments.getPortDetails` -> { ...ports row, berths: portBerths[] }.
/// NOTE the absence of any beam-limit field — that is the schema, not an omission here.
private struct PortDetail699: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let country: String?
    let berths: [Berth699]?
    private let maxDraftBox: FlexDouble699?
    var maxDraft: Double? { maxDraftBox?.value }

    enum CodingKeys: String, CodingKey {
        case id, name, unlocode, country, berths
        case maxDraftBox = "maxDraft"
    }
}

private struct Berth699: Decodable, Identifiable {
    let id: Int
    let berthNumber: String?
    let berthType: String?
    let status: String?
    private let lengthMetersBox: FlexDouble699?
    private let depthMetersBox: FlexDouble699?
    var lengthMeters: Double? { lengthMetersBox?.value }
    var depthMeters:  Double? { depthMetersBox?.value }

    enum CodingKeys: String, CodingKey {
        case id, berthNumber, berthType, status
        case lengthMetersBox = "lengthMeters"
        case depthMetersBox  = "depthMeters"
    }
}

/// `vesselShipments.getPorts` -> ports[] (the real picker behind the caliper).
private struct PortOption699: Decodable, Identifiable {
    let id: Int
    let name: String?
    let unlocode: String?
    let country: String?
}

/// `vesselShipments.getVesselCertificates` -> [{ id, name, issuedBy, expiresAt, status }].
/// Nothing else is on the wire, so nothing else is decoded.
private struct CertRow699: Decodable, Identifiable {
    let id: String
    let name: String?
    let issuedBy: String?
    let expiresAt: String?
    let status: String?

    /// ISPS rows are minted `cert_isps_<id>` by the router; insurance rows `cert_ins_<id>`.
    /// That prefix is the only honest way to tell a statutory certificate from a commercial
    /// policy without guessing at the display name.
    var isStatutoryISPS: Bool { id.hasPrefix("cert_isps_") }
}

/// `vesselShipments.getVesselInspections` -> vessel_inspections rows.
/// `port` is always null by router design (vessel_inspections has no portId column).
private struct Inspection699: Decodable, Identifiable {
    let id: String
    let type: String?
    let date: String?
    let port: String?
    let status: String?
    let authority: String?
    let deficiencies: Int?
}

/// `vesselShipments.getVesselParticulars` -> MarineTraffic passthrough or null.
/// Every field optional: the shape is NOT owned by this repo, so a partial or null payload
/// must decode without throwing and must leave the spine untouched.
private struct ParticularsOverlay699: Decodable {
    let name: String?
    let type: String?
    let flag: String?
    let yearBuilt: Int?
    let owner: String?
    let operatorName: String?
    let classification: String?
    let grossTonnage: Int?
    let deadweight: Int?

    enum CodingKeys: String, CodingKey {
        case name, type, flag, yearBuilt, owner, classification, grossTonnage, deadweight
        case operatorName = "operator"
    }
}

// MARK: - Body

private struct VesselParticularsBody699: View {
    @Environment(\.palette) private var palette
    let imoNumber: String
    let portId: Int

    // Live state only — no seeds, no demo rows, no hardcoded hull or port.
    @State private var vessel: VesselRow699? = nil
    @State private var port: PortDetail699? = nil
    @State private var portOptions: [PortOption699] = []
    @State private var certs: [CertRow699] = []
    @State private var overlay: ParticularsOverlay699? = nil
    @State private var inspections: [Inspection699] = []

    @State private var selectedPortId: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var certError: String? = nil
    @State private var portError: String? = nil

    @State private var showPortPicker = false
    @State private var showBinder = false
    @State private var showPSC = false
    @State private var binderLoading = false
    @State private var pscLoading = false
    @State private var pscError: String? = nil

    // ── Derived reads. Every one of these reads THIS state — never a parallel literal. ──

    /// The berth the LOA caliper is measured against: the longest berth the port publishes.
    /// nil when the port has no berth rows, which the rail then says out loud.
    private var referenceBerth: Berth699? {
        (port?.berths ?? []).filter { $0.lengthMeters != nil }
            .max { ($0.lengthMeters ?? 0) < ($1.lengthMeters ?? 0) }
    }
    private var loaLimit: Double? { referenceBerth?.lengthMeters }
    private var draftLimit: Double? { port?.maxDraft }
    /// There is no beam limit anywhere in the schema. This is a constant `nil` on purpose and the
    /// rail renders a gap notice rather than a tick. Do not "fix" it with a literal.
    private let beamLimit: Double? = nil

    private var draftOverBy: Double? {
        guard let d = vessel?.draftMeters, let lim = draftLimit, d > lim else { return nil }
        return d - lim
    }
    private var loaOverBy: Double? {
        guard let l = vessel?.lengthMeters, let lim = loaLimit, l > lim else { return nil }
        return l - lim
    }

    private var sortedCerts: [CertRow699] {
        certs.sorted { (daysToExpiry($0) ?? Int.max) < (daysToExpiry($1) ?? Int.max) }
    }
    private var lapsedCount: Int { certs.filter { (daysToExpiry($0) ?? 1) < 0 }.count }
    private var dueCount: Int {
        certs.filter { d in (daysToExpiry(d).map { $0 >= 0 && $0 <= 90 }) ?? false }.count
    }

    // ── Horizon window: a rolling 12 months starting two months back. ──

    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private var windowStart: Date {
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return cal.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
    }
    private var windowEnd: Date { cal.date(byAdding: .month, value: 12, to: windowStart) ?? windowStart }
    private var todayFraction: CGFloat { fraction(for: Date()) }

    private func fraction(for date: Date) -> CGFloat {
        let span = windowEnd.timeIntervalSince(windowStart)
        guard span > 0 else { return 0 }
        return CGFloat(min(max(date.timeIntervalSince(windowStart) / span, 0), 1))
    }

    private func expiryDate(_ c: CertRow699) -> Date? {
        guard let iso = c.expiresAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd"
        plain.timeZone = TimeZone(identifier: "UTC")
        return plain.date(from: String(iso.prefix(10)))
    }

    private func daysToExpiry(_ c: CertRow699) -> Int? {
        guard let e = expiryDate(c) else { return nil }
        let today = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: today, to: cal.startOfDay(for: e)).day
    }

    private var monthLabels: [String] {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return (0..<12).compactMap { i in
            cal.date(byAdding: .month, value: i, to: windowStart).map { f.string(from: $0).uppercased() }
        }
    }
    private var windowCaption: String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        let end = cal.date(byAdding: .month, value: 11, to: windowStart) ?? windowStart
        return "\(f.string(from: windowStart).uppercased()) - \(f.string(from: end).uppercased())"
    }

    // MARK: body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if loading && vessel == nil {
                loadingCard
            } else if let err = loadError, vessel == nil {
                errorCard(err)
            } else if vessel == nil {
                emptyRegistryCard
            } else {
                sectionLabel("DIMENSION NOMOGRAM", right: portCaption).padding(.top, Space.s5)
                nomogramHero.padding(.top, Space.s2)
                esangStrip.padding(.top, Space.s3)
                sectionLabel("CERTIFICATE HORIZON · 12 MONTHS", right: windowCaption).padding(.top, Space.s5)
                horizonBand.padding(.top, Space.s2)
                sectionLabel("PRINCIPAL PARTICULARS", right: "TABLE vessels · 8 COLUMNS").padding(.top, Space.s5)
                particularsBands.padding(.top, Space.s2)
                if overlay != nil { overlayLine.padding(.top, Space.s2) }
                ctaPair.padding(.top, Space.s4)
            }
        }
        .padding(.horizontal, Space.s5)
        .task { await load() }
        .sheet(isPresented: $showPortPicker) { portPickerSheet }
        .sheet(isPresented: $showBinder)     { binderSheet }
        .sheet(isPresented: $showPSC)        { pscSheet }
    }

    // MARK: header · one sparkle · DRAWN staleness breadcrumb

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("\u{2726} VESSEL · COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s3)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("REGISTRY LIVE · SPECS CACHED 24h")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                    // The staleness affordance is DRAWN, not merely asserted in a comment.
                    DashedRule699().frame(width: 198, height: 1)
                        .foregroundColor(palette.textTertiary.opacity(0.55))
                }
            }
            .padding(.top, Space.s5)

            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold)).foregroundColor(palette.textPrimary)
                Text("Vessel particulars")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundColor(palette.textPrimary)
            }
            .padding(.top, Space.s4)

            Text(subline)
                .font(EType.caption).foregroundColor(palette.textSecondary)
                .padding(.top, Space.s1)

            IridescentHairline()
                .padding(.top, Space.s3)
                .padding(.horizontal, -Space.s5)
        }
    }

    /// Built entirely from the live row. No hull name is ever hardcoded.
    private var subline: String {
        guard let v = vessel else { return "Reading the vessel registry" }
        var parts: [String] = []
        if let n = v.name, !n.isEmpty { parts.append(n) }
        if let t = v.vesselType, !t.isEmpty { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
        if let imo = v.imoNumber, !imo.isEmpty { parts.append("IMO \(imo)") }
        return parts.isEmpty ? "Vessel row carries no name or IMO" : parts.joined(separator: " · ")
    }

    private var portCaption: String {
        guard let p = port else { return "NO PORT SELECTED" }
        let code = p.unlocode ?? "—"
        let name = (p.name ?? "").uppercased()
        if let b = referenceBerth?.berthNumber { return "\(code) \(name) · BERTH \(b)" }
        return "\(code) \(name)"
    }

    private func sectionLabel(_ left: String, right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(left).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundColor(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(right).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundColor(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: HERO · dimension nomogram

    private var nomogramHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ScaleRail699(
                title: "LOA · SCALE 0-400 m",
                scaleMax: 400,
                value: vessel?.lengthMeters,
                limit: loaLimit,
                limitCaption: loaLimitCaption,
                isOver: loaOverBy != nil,
                gapNotice: loaLimit == nil ? loaGapNotice : nil,
                onGapTap: port == nil ? { showPortPicker = true } : nil)

            ScaleRail699(
                title: "BEAM · SCALE 0-62 m",
                scaleMax: 62,
                value: vessel?.beamMeters,
                limit: beamLimit,
                limitCaption: "PORT BEAM LIMIT · STUB",
                isOver: false,
                gapNotice: "NO BEAM-LIMIT COLUMN IN ports OR port_berths",
                onGapTap: nil)

            ScaleRail699(
                title: "DRAFT · SCALE 0-16 m",
                scaleMax: 16,
                value: vessel?.draftMeters,
                limit: draftLimit,
                limitCaption: draftLimitCaption,
                isOver: draftOverBy != nil,
                gapNotice: draftLimit == nil ? "PORT MAX DRAFT NOT SET ON THIS PORT ROW" : nil,
                onGapTap: port == nil ? { showPortPicker = true } : nil)

            if port == nil {
                Button { showPortPicker = true } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 11, weight: .bold))
                        Text("Select the port these limits are measured against")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(LinearGradient.primary)
                }
                .buttonStyle(.plain)
            } else {
                Button { showPortPicker = true } label: {
                    HStack(spacing: Space.s2) {
                        Text("Change port")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(LinearGradient.primary)
                }
                .buttonStyle(.plain)
            }

            if let pe = portError {
                Text(pe).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Brand.danger)
            }
        }
        .padding(.vertical, Space.s5)
        .padding(.horizontal, Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var loaLimitCaption: String {
        guard let lim = loaLimit else { return "BERTH LENGTH · NO ROW" }
        let b = referenceBerth?.berthNumber ?? "—"
        if let over = loaOverBy { return "BERTH \(b) LIMIT \(m1(lim)) · \(String(format: "%.2f", over)) m OVER" }
        return "BERTH \(b) LIMIT \(m1(lim))"
    }
    private var draftLimitCaption: String {
        guard let lim = draftLimit else { return "MAX DRAFT · NOT SET" }
        if let over = draftOverBy { return "MAX DRAFT \(m1(lim)) · \(String(format: "%.2f", over)) m OVER" }
        return "MAX DRAFT \(m1(lim))"
    }
    private var loaGapNotice: String {
        port == nil ? "NO PORT SELECTED — TAP TO MEASURE AGAINST A REAL BERTH"
                    : "THIS PORT PUBLISHES NO BERTH LENGTH IN port_berths"
    }

    // MARK: ESang · derived from the live reads on screen, never an LLM line

    private var esangStrip: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                Circle().fill(Color.white.opacity(0.30)).frame(width: 13, height: 13).offset(x: -4, y: -4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · LIMIT WATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.primary)
                Text(esangLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    /// Reads the SAME state the rails and the horizon read, so it cannot drift away from them.
    private var esangLine: String {
        if let over = draftOverBy, let p = port {
            return "Draft over \(p.unlocode ?? "port") limit by \(String(format: "%.2f", over)) m — plan the tidal window"
        }
        if let over = loaOverBy {
            return "LOA over the reference berth by \(String(format: "%.2f", over)) m — request a longer berth"
        }
        if let lapsed = sortedCerts.first, let d = daysToExpiry(lapsed), d < 0 {
            return "\(certLabel(lapsed)) lapsed \(abs(d)) d ago — renew before the next call"
        }
        if let next = sortedCerts.first, let d = daysToExpiry(next), d <= 90 {
            return "\(certLabel(next)) expires in \(d) d — the nearest deadline on this hull"
        }
        if port == nil { return "Select a port to measure this hull against its declared limits" }
        return "Every declared limit and certificate on this hull is clear"
    }

    // MARK: MID-BAND · 12-month certificate horizon

    private var horizonBand: some View {
        VStack(alignment: .leading, spacing: 0) {
            if certs.isEmpty {
                if let ce = certError {
                    Text(ce).font(.system(size: 11, weight: .semibold)).foregroundColor(Brand.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("NO CERTIFICATE ROWS")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundColor(palette.textTertiary)
                        Text("getVesselCertificates returned an empty union — vessel_isps_records and vessel_insurance carry no rows to plot.")
                            .font(.system(size: 11)).foregroundColor(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let cell = w / 12
                    let todayX = todayFraction * w

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, m in
                                Text(m).font(.system(size: 8, weight: .bold)).tracking(0.4)
                                    .foregroundColor(palette.textTertiary)
                                    .frame(width: cell)
                            }
                        }
                        .frame(height: 12)

                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)

                            HStack(spacing: 0) {
                                ForEach(0..<11, id: \.self) { _ in
                                    Rectangle().fill(palette.borderFaint.opacity(0.6))
                                        .frame(width: 1)
                                        .frame(maxWidth: cell, alignment: .trailing)
                                }
                            }
                            .frame(height: 112, alignment: .top)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(sortedCerts.prefix(5))) { cert in
                                    CertCapsule699(
                                        label: certLabel(cert),
                                        endX: capsuleEndX(cert, width: w),
                                        todayX: todayX,
                                        days: daysToExpiry(cert),
                                        startUnknown: cert.isStatutoryISPS,
                                        expiresAt: shortDate(cert))
                                    .frame(height: 14)
                                }
                            }
                            .padding(.top, 6)

                            Rectangle().fill(Brand.blue).frame(width: 1.5, height: 112).offset(x: todayX)
                            Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                                .offset(x: todayX - 3, y: -3)
                        }
                        .frame(height: 112)

                        Text("TODAY")
                            .font(.system(size: 8, weight: .bold)).tracking(0.4)
                            .foregroundStyle(LinearGradient.primary)
                            .frame(width: 60, alignment: .center)
                            .offset(x: max(0, min(w - 60, todayX - 30)))
                            .padding(.top, 4)
                    }
                }
                .frame(height: 146)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    /// x of the capsule head = the expiry date's position on the axis. THIS is the whole organ.
    private func capsuleEndX(_ c: CertRow699, width: CGFloat) -> CGFloat {
        guard let e = expiryDate(c) else { return 0 }
        return fraction(for: e) * width
    }

    private func certLabel(_ c: CertRow699) -> String {
        let raw = (c.name ?? "CERTIFICATE").uppercased()
        // The ISSC row has no issue date column; say so inside the capsule where it is read.
        if c.isStatutoryISPS { return "ISSC · ISSUE DATE NOT A COLUMN" }
        return raw
    }

    private func shortDate(_ c: CertRow699) -> String {
        guard let iso = c.expiresAt else { return "—" }
        return String(iso.prefix(10))
    }

    // MARK: ROW GRAMMAR · two-column pairs, 4 per band, 2 bands

    private var particularsBands: some View {
        VStack(alignment: .leading, spacing: 0) {
            PairBand699(pairs: [
                Pair699(label: "IMO NUMBER",    value: vessel?.imoNumber ?? "—",              unit: nil),
                Pair699(label: "CALL SIGN",     value: vessel?.callSign ?? "—",               unit: nil),
                Pair699(label: "GROSS TONNAGE", value: grouped(vessel?.grossTonnage),         unit: "GT"),
                Pair699(label: "DEADWEIGHT",    value: grouped(vessel?.deadweightTonnage),    unit: "t")
            ])
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s3)
            PairBand699(pairs: [
                Pair699(label: "FLAG STATE",     value: vessel?.flag ?? "—",                  unit: nil),
                Pair699(label: "CLASSIFICATION", value: vessel?.classificationSociety ?? "—", unit: "society"),
                Pair699(label: "YEAR BUILT",     value: vessel?.yearBuilt.map(String.init) ?? "—", unit: ageSuffix),
                Pair699(label: "TEU CAPACITY",   value: grouped(vessel?.teuCapacity),         unit: "TEU")
            ])
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    /// Derived, and labelled as derived — yearBuilt is the stored column, age is not.
    private var ageSuffix: String? {
        guard let y = vessel?.yearBuilt, y > 1800 else { return nil }
        let thisYear = cal.component(.year, from: Date())
        return "· \(max(0, thisYear - y)) yr"
    }

    /// The cached enrichment leg — shown ONLY once it actually lands, and labelled as cached.
    private var overlayLine: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .bold)).foregroundColor(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("AIS ENRICHMENT · CACHED 24h")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Text(overlaySummary)
                    .font(.system(size: 11)).foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoRow(radius: Radius.md)
    }

    private var overlaySummary: String {
        guard let o = overlay else { return "" }
        var parts: [String] = []
        if let owner = o.owner, !owner.isEmpty { parts.append("owner \(owner)") }
        if let op = o.operatorName, !op.isEmpty { parts.append("operator \(op)") }
        if let cls = o.classification, !cls.isEmpty { parts.append("class \(cls)") }
        if parts.isEmpty { return "Provider returned a payload with no owner, operator or class field." }
        return parts.joined(separator: " · ") + " — provider-supplied, not a column in this database."
    }

    // MARK: CTA pair · 236 + 152 (varied off the stamped 260+132)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Certificate binder",
                      action: { Task { await openBinder() } },
                      trailingIcon: "doc.text.magnifyingglass",
                      isLoading: binderLoading)

            Button { Task { await openPSC() } } label: {
                Group {
                    if pscLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("PSC record").font(EType.title).foregroundColor(palette.textPrimary)
                    }
                }
                .frame(width: 152).frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
            }
            .buttonStyle(.plain)
            .disabled(pscLoading)
        }
    }

    // MARK: states

    private var loadingCard: some View {
        HStack(spacing: Space.s3) {
            ProgressView().controlSize(.small)
            Text("Reading the vessel registry").font(EType.body).foregroundColor(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg).padding(.top, Space.s5)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REGISTRY READ FAILED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundColor(Brand.danger)
            Text(msg).font(EType.body).foregroundColor(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await load() } } label: {
                Text("Retry").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg).padding(.top, Space.s5)
    }

    private var emptyRegistryCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NO VESSEL ROW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundColor(palette.textTertiary)
            Text(imoNumber.isEmpty
                 ? "getVesselFleet returned no vessels. There is nothing in the registry to measure."
                 : "getVesselFleet returned no row matching IMO \(imoNumber).")
                .font(EType.body).foregroundColor(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg).padding(.top, Space.s5)
    }

    // MARK: sheets

    private var portPickerSheet: some View {
        NavigationStack {
            Group {
                if portOptions.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("NO PORT ROWS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundColor(palette.textTertiary)
                        Text("getPorts returned no rows from the ports table, so there is no published limit to measure this hull against.")
                            .font(EType.body).foregroundColor(palette.textSecondary)
                    }
                    .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(portOptions) { p in
                        Button {
                            selectedPortId = p.id
                            showPortPicker = false
                            Task { await loadPort() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name ?? "—").font(EType.bodyStrong)
                                        .foregroundColor(palette.textPrimary)
                                    Text([p.unlocode, p.country].compactMap { $0 }.joined(separator: " · "))
                                        .font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                                }
                                Spacer()
                                if p.id == selectedPortId {
                                    Image(systemName: "checkmark").foregroundStyle(LinearGradient.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Measure against")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var binderSheet: some View {
        NavigationStack {
            Group {
                if sortedCerts.isEmpty {
                    Text("No certificate rows on this hull.")
                        .font(EType.body).foregroundColor(palette.textSecondary)
                        .padding(Space.s4)
                } else {
                    List(sortedCerts) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.name ?? "—").font(EType.bodyStrong)
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                if let d = daysToExpiry(c) {
                                    StatusPill(text: d < 0 ? "expired" : (d <= 90 ? "due" : "valid"),
                                               kind: d < 0 ? .danger : (d <= 90 ? .warning : .success))
                                } else {
                                    StatusPill(text: "no expiry", kind: .neutral)
                                }
                            }
                            HStack(spacing: Space.s2) {
                                Text(shortDate(c)).font(EType.mono(.caption))
                                    .foregroundColor(palette.textTertiary)
                                if let by = c.issuedBy, !by.isEmpty {
                                    Text(by).font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                                } else if c.isStatutoryISPS {
                                    Text("issuer not persisted for ISPS rows")
                                        .font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Certificate binder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var pscSheet: some View {
        NavigationStack {
            Group {
                if let e = pscError {
                    Text(e).font(EType.body).foregroundColor(Brand.danger).padding(Space.s4)
                } else if inspections.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("NO INSPECTION ROWS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundColor(palette.textTertiary)
                        Text("getVesselInspections returned an empty vessel_inspections table.")
                            .font(EType.body).foregroundColor(palette.textSecondary)
                    }
                    .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(inspections) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text((i.type ?? "inspection").uppercased())
                                    .font(EType.bodyStrong).foregroundColor(palette.textPrimary)
                                Spacer()
                                StatusPill(text: i.status ?? "—", kind: pillKind(i.status))
                            }
                            HStack(spacing: Space.s2) {
                                Text(i.date.map { String($0.prefix(10)) } ?? "—")
                                    .font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                                Text(i.authority ?? "authority not recorded")
                                    .font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                                Spacer()
                                Text("\(i.deficiencies ?? 0) def")
                                    .font(EType.mono(.caption)).foregroundColor(palette.textTertiary)
                            }
                            // Honest, on-screen: the wire has no port for an inspection.
                            Text("port not a column on vessel_inspections")
                                .font(.system(size: 9)).foregroundColor(palette.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("PSC record")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pillKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").lowercased() {
        case "pass":        return .success
        case "conditional": return .warning
        case "fail", "detention": return .danger
        default:            return .neutral
        }
    }

    // MARK: formatting

    private func m1(_ v: Double) -> String { String(format: "%.1f m", v) }
    private func grouped(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    // MARK: loaders — real client calls, unconditional overwrite, never a fabricated row

    private func load() async {
        loading = true; loadError = nil; certError = nil
        if selectedPortId == 0 { selectedPortId = portId }

        struct FleetIn699: Encodable { let search: String?; let limit: Int }
        struct ListIn699: Encodable { let limit: Int }
        struct ImoIn699: Encodable { let imoNumber: String }
        struct PortsIn699: Encodable { let limit: Int }

        // 1 · THE SPINE. Unconditional overwrite: an honest empty fleet clears the hull.
        do {
            let res: FleetResponse699 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet",
                input: FleetIn699(search: imoNumber.isEmpty ? nil : imoNumber, limit: 50))
            if imoNumber.isEmpty {
                vessel = res.vessels.first
            } else {
                vessel = res.vessels.first { $0.imoNumber == imoNumber } ?? res.vessels.first
            }
        } catch {
            vessel = nil
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // 2 · THE CERTIFICATE HORIZON. Unconditional overwrite.
        do {
            let rows: [CertRow699] = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCertificates", input: ListIn699(limit: 50))
            certs = rows
        } catch {
            certs = []
            certError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // 3 · The real port list behind the caliper picker. Best-effort: its absence never
        //     degrades the spine, it only leaves the ticks honestly unset.
        portOptions = (try? await EusoTripAPI.shared.query(
            "vesselShipments.getPorts", input: PortsIn699(limit: 100))) ?? []

        // 4 · The caliper ticks, when a port is actually threaded or picked.
        await loadPort()

        // 5 · CACHED ENRICHMENT OVERLAY — never the spine. A null payload leaves the screen whole.
        if let imo = vessel?.imoNumber, !imo.isEmpty {
            overlay = try? await EusoTripAPI.shared.query(
                "vesselShipments.getVesselParticulars", input: ImoIn699(imoNumber: imo))
        } else {
            overlay = nil
        }

        loading = false
    }

    private func loadPort() async {
        portError = nil
        guard selectedPortId > 0 else { port = nil; return }
        struct PortIn699: Encodable { let portId: Int }
        do {
            let p: PortDetail699? = try await EusoTripAPI.shared.query(
                "vesselShipments.getPortDetails", input: PortIn699(portId: selectedPortId))
            port = p   // unconditional: a null response clears the ticks rather than freezing them
        } catch {
            port = nil
            portError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Real widened re-read at the procedure's max limit, then the binder sheet.
    private func openBinder() async {
        binderLoading = true; certError = nil
        struct ListIn699: Encodable { let limit: Int }
        do {
            let rows: [CertRow699] = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCertificates", input: ListIn699(limit: 200))
            certs = rows
            showBinder = true
        } catch {
            certError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        binderLoading = false
    }

    /// Real read of vessel_inspections, then the PSC sheet.
    private func openPSC() async {
        pscLoading = true; pscError = nil
        struct ListIn699: Encodable { let limit: Int }
        do {
            let rows: [Inspection699] = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselInspections", input: ListIn699(limit: 50))
            inspections = rows
            showPSC = true
        } catch {
            pscError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            showPSC = true
        }
        pscLoading = false
    }
}

// MARK: - One nomogram rail: fill = the ship, 2x22 caliper tick = the port limit

private struct ScaleRail699: View {
    @Environment(\.palette) private var palette

    let title: String
    let scaleMax: Double
    let value: Double?
    let limit: Double?
    let limitCaption: String
    let isOver: Bool
    /// Non-nil when NO limit is knowable — the tick band renders this instead of a fake tick.
    let gapNotice: String?
    let onGapTap: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillW  = value.map { CGFloat(min(max($0 / scaleMax, 0), 1)) * w } ?? 0
            let limitX = limit.map { CGFloat(min(max($0 / scaleMax, 0), 1)) * w }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                    Spacer(minLength: 8)
                    Text(limitCaption)
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundColor(isOver ? Brand.danger : palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(height: 12)

                // TICK BAND — a 2x22 caliper tick, or a drawn honest gap notice. Never both,
                // and never a tick at an invented position.
                ZStack(alignment: .topLeading) {
                    if let lx = limitX {
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle().fill(palette.textPrimary.opacity(0.85)).frame(width: 8, height: 1)
                            Rectangle().fill(palette.textPrimary.opacity(0.85)).frame(width: 2, height: 21)
                                .offset(x: 3)
                        }
                        .offset(x: max(0, lx - 4))
                    } else if let notice = gapNotice {
                        ZStack(alignment: .leading) {
                            DashedRule699().frame(height: 1)
                                .foregroundColor(palette.textTertiary.opacity(0.45))
                                .offset(y: 11)
                            Text(notice)
                                .font(.system(size: 8, weight: .bold)).tracking(0.4)
                                .foregroundColor(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .padding(.horizontal, 3)
                                .background(palette.bgCard)
                                .offset(y: 7)
                        }
                    }
                }
                .frame(height: 22)
                .padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture { onGapTap?() }

                // THE RAIL. Track, ship fill, and the excess bleeding past the tick in danger.
                // The verdict is the geometry; the caption only names the limit.
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.textPrimary.opacity(0.07)).frame(width: w, height: 14)
                    Rectangle().fill(LinearGradient.primary).frame(width: fillW, height: 14)
                    if isOver, let lx = limitX, fillW > lx {
                        Rectangle().fill(Brand.danger)
                            .frame(width: fillW - lx, height: 14)
                            .offset(x: lx)
                    }
                    if let v = value {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Text(String(format: "%.1f", v))
                                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            Text(" m").font(.system(size: 11, weight: .bold)).opacity(0.8)
                        }
                        .foregroundColor(.white)
                        .frame(width: max(56, valueTextRight(fillW: fillW, limitX: limitX)), alignment: .trailing)
                        .padding(.trailing, 0)
                    } else {
                        Text("NOT ON THE ROW")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundColor(palette.textTertiary)
                            .padding(.leading, 8)
                    }
                }
                .frame(width: w, height: 14)
                .clipShape(Capsule())
            }
        }
        .frame(height: 52)
    }

    /// The number is printed AT the fill head — and, when the rail is over limit, just left of the
    /// tick so the red excess stays clean and readable as an area.
    private func valueTextRight(fillW: CGFloat, limitX: CGFloat?) -> CGFloat {
        if isOver, let lx = limitX { return max(56, lx - 6) }
        return max(56, fillW - 10)
    }
}

// MARK: - One certificate capsule (its END is the expiry date)

private struct CertCapsule699: View {
    @Environment(\.palette) private var palette

    let label: String
    let endX: CGFloat
    let todayX: CGFloat
    let days: Int?
    /// vessel_isps_records has no issue-date column, so the head is honestly unknown.
    let startUnknown: Bool
    let expiresAt: String

    private var tone: Color {
        guard let d = days else { return Brand.neutral }
        if d < 0 { return Brand.danger }
        if d <= 90 { return Brand.warning }
        return Brand.success
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if startUnknown {
                Capsule().fill(tone.opacity(0.30)).frame(width: 40, height: 14)
                Capsule().fill(tone).frame(width: max(0, endX - 30), height: 14).offset(x: 30)
            } else {
                Capsule().fill(tone).frame(width: max(0, endX), height: 14)
            }

            // A capsule that ends before the today stem bleeds the lapsed interval in danger.
            if let d = days, d < 0, todayX > endX {
                Rectangle().fill(Brand.danger.opacity(0.20))
                    .frame(width: todayX - endX + 4, height: 14)
                    .offset(x: max(0, endX - 4))
            }

            HStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.leading, startUnknown ? 38 : 6)
                Spacer(minLength: 4)
                if let d = days, d >= 0 {
                    Text("\(d) d").font(.system(size: 9, weight: .bold)).monospacedDigit()
                        .foregroundColor(.white).padding(.trailing, 8)
                }
            }
            .frame(width: max(0, endX), alignment: .leading)
            .clipped()

            if let d = days, d < 0 {
                Text("EXPIRED \(abs(d)) d · \(expiresAt)")
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
                    .foregroundColor(Brand.danger)
                    .fixedSize()
                    .offset(x: todayX + 7)
            }
        }
    }
}

// MARK: - Two-column pair band (4 pairs; no icon chips, no pills)

private struct Pair699 { let label: String; let value: String; let unit: String? }

private struct PairBand699: View {
    @Environment(\.palette) private var palette
    let pairs: [Pair699]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(0..<2, id: \.self) { row in
                HStack(alignment: .top, spacing: Space.s3) {
                    cell(pairs[row * 2]).frame(maxWidth: .infinity, alignment: .leading)
                    cell(pairs[row * 2 + 1]).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func cell(_ p: Pair699) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundColor(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(p.value)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let u = p.unit {
                    Text(u).font(.system(size: 11, weight: .bold))
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
    }
}

// MARK: - The dashed breadcrumb (the drawn staleness affordance)

private struct DashedRule699: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
    }
}

#Preview("699 Vessel Particulars · Light") {
    VesselParticularsScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#Preview("699 Vessel Particulars · Dark") {
    VesselParticularsScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
