//
//  564_RailBorderClearance.swift
//  EusoTrip — Rail Engineer · Border Clearance (carrier-side cross-border).
//
//  Cross-border customs clearance drill-down for an active consist at a named
//  US-MX rail interchange. Faithful port of
//  "05 Rail/Light-SVG/564 Rail Border Clearance.svg" (Light + Dark).
//  Gold-standard grammar: eyebrow → H1 28pt -0.4k → gradient-rim hero →
//  3-KPI strip → checklist rows → required-docs strip → CTA pair.
//
//  Data:
//    railShipments.getRailShipmentDetail           (EXISTS :140) → shipment context
//    railShipments.getCrossBorderInterchangePoints (EXISTS :887) → interchange point
//    railShipments.checkCrossBorderRailCompliance  (EXISTS :903) → regulatory checklist
//    railShipments.getCrossBorderRailDocs          (EXISTS :899) → required documents list
//
//  OFFLINE POLICY (§W): READ_CACHED(5m) reads · ONLINE_ONLY submit.
//    · READ_CACHED(5m) — the interchange point, the clearance ladder and the
//      required-doc set are held for the session and stamped on every
//      successful read. A permanently visible monospaced staleness line sits in
//      the header register and flips to Brand.warning past the 5m TTL, and the
//      hero carries its own "cached · not live" band the moment the read ages
//      out or the device drops offline. This is a customs go/no-go surface: a
//      cached CLEARED must never render as live. No cold-launch disk cache is
//      claimed here — offline with nothing read this session the screen shows
//      its real load error rather than an invented clearance.
//    · ONLINE_ONLY(a customs filing must be server-confirmed before the consist
//      can be cleared to cross) — no filing is queued, replayed, or
//      optimistically marked filed on this device.
//
//  NAMED GAP · railShipments.submitCrossBorderRailFiling: the wireframe's
//    second CTA reads "Submit pedimento", but every cross-border rail procedure
//    on the live router is a read (`railReadProcedure` + `.query`):
//    getCrossBorderInterchangePoints railShipments.ts:2967 ·
//    getCrossBorderRailDocs :2979 · checkCrossBorderRailCompliance :2983 ·
//    estimateRailBorderCrossingTime :3019. There is NO filing mutation, so this
//    port ships no submit control at all rather than one that cannot file.
//    Proposed shape (nothing stubbed here):
//      submitCrossBorderRailFiling: railOpsWriteProcedure   // railShipments.ts:160
//        .input(z.object({
//          shipmentId: z.number(),
//          interchangePointId: z.string(),
//          direction: z.string(),
//          documentIds: z.array(z.number()),
//          requestKey: z.string(),
//        }))
//        .mutation(...)   // -> { success, filingId, filedAt, authority }
//
//  ESANG: esangCoach.forScreen EXISTS (esangCoach.ts:264) but its SCREEN_ENUM
//    (esangCoach.ts:112) is a driver in-cab list — home / trips / earnings /
//    tax / dvir / availability / missions / badges / referrals / zeun / haul /
//    active-trip — with no rail or clearance key, and its system prompt speaks
//    HOS and DVIR. Calling it from a border-clearance surface would return the
//    wrong entity, so the ESANG band below is derived on device from the ladder
//    already decoded and says so on its face. Same call 559 and 665 made.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct RailBorderClearanceScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    let interchangePointId: String
    var body: some View {
        Shell(theme: theme) {
            RailBorderClearanceBody(shipmentId: shipmentId, interchangePointId: interchangePointId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance for this pushed Rail Engineer surface. Fixed
        // leading slot → never overlaps the eyebrow/title; posts the shared
        // NavBack that RailEngineerSurface pops on
        // (RoleSurfaceRouter.swift:4813), so context is preserved on the way out.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shapes

private struct RailYard564: Decodable {
    let id: Int
    let name: String?
    let city: String?
    let state: String?
}

private struct RailShipmentDetail564: Decodable {
    let id: Int
    let shipmentNumber: String?
    let status: String?
    let hazmatClass: String?
    let unNumber: String?
    let numberOfCars: Int?
    let originRailroad: String?
    let waybillNumber: String?
    let originYard: RailYard564?
    let destinationYard: RailYard564?
}

private struct RailInterchangePoint564: Decodable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let interchangeType: String?
    let hazmatAllowed: Bool?
    let customsOffice: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
}

private struct ComplianceItem564: Decodable {
    let requirement: String
    let status: String
    let details: String
    let regulation: String
}

private struct CrossBorderCompliance564: Decodable {
    let interchangePoint: String?
    let direction: String?
    let regulatory: [ComplianceItem564]
    let overallCompliant: Bool
}

// MARK: - Body

private struct RailBorderClearanceBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var reach = OfflineReachabilityHub.shared
    let shipmentId: Int
    let interchangePointId: String

    @State private var detail: RailShipmentDetail564? = nil
    @State private var interchange: RailInterchangePoint564? = nil
    @State private var compliance: CrossBorderCompliance564? = nil
    @State private var requiredDocs: [String] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    /// §W READ_CACHED(5m) clock — stamped on every successful server evaluation.
    @State private var lastReadAt: Date? = nil

    private var hasDG: Bool { detail?.hazmatClass != nil }
    private var passCount: Int { compliance?.regulatory.filter { $0.status == "pass" }.count ?? 0 }
    private var failCount: Int { compliance?.regulatory.filter { $0.status == "fail" }.count ?? 0 }
    private var totalCount: Int { compliance?.regulatory.count ?? 0 }

    private var crossingLabel: String {
        guard let p = interchange else { return interchangePointId }
        let stA = p.stateProvinceA ?? (p.countryA ?? "US")
        let stB = p.stateProvinceB ?? (p.countryB ?? "MX")
        let kind = p.interchangeType ?? "crossing"
        return "\(stA) → \(stB) · \(kind)"
    }

    // MARK: §W READ_CACHED(5m) staleness

    private static let readTTL: TimeInterval = 300

    private var readAge: TimeInterval? {
        guard let at = lastReadAt else { return nil }
        return Date().timeIntervalSince(at)
    }

    private var readIsStale: Bool {
        guard let age = readAge else { return true }
        return age > Self.readTTL
    }

    private var stalenessLine: String {
        guard let age = readAge else { return "not checked yet" }
        if age < 60 { return "checked · just now" }
        if age < 3600 { return "checked · \(Int(age / 60))m ago" }
        return "checked · \(Int(age / 3600))h ago"
    }

    /// The go/no-go is only allowed to read as live when the device is online
    /// AND the last server evaluation is still inside the 5m TTL.
    private var clearanceIsLive: Bool {
        reach.isOnline && lastReadAt != nil && !readIsStale
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Running border clearance check…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    // §W honesty law: cached / offline clearance is drawn as a
                    // visibly distinct state, never as a live go/no-go.
                    if !clearanceIsLive { cachedClearanceBand }
                    kpiStrip
                    checklistSection
                    if !requiredDocs.isEmpty { docsStrip }
                    esangBand
                    actionsRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flag.2.crossed")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · BORDER CLEARANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("Border Clearance")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let num = detail?.shipmentNumber {
                    Text(num)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityLabel("Shipment \(num)")
                }
            }
            HStack(alignment: .firstTextBaseline) {
                if let p = interchange {
                    Text("\(p.name ?? interchangePointId) · \(p.customsOffice ?? "CBP/SAT")")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                // §W READ_CACHED(5m) staleness — always visible, warns past TTL.
                Text(stalenessLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(readIsStale ? Brand.warning : palette.textTertiary)
                    .fixedSize()
                    .accessibilityLabel("Clearance \(stalenessLine)")
            }
            IridescentHairline()
                .accessibilityHidden(true)
        }
    }

    // MARK: Cached-clearance honesty band

    /// A customs go/no-go is the one surface where a stale CLEARED is worse than
    /// no answer at all, so cached and offline states are drawn distinctly
    /// rather than left to look live.
    private var cachedClearanceBand: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(reach.isOnline ? "CACHED CLEARANCE · NOT LIVE" : "OFFLINE · CACHED CLEARANCE · NOT LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                Text("This go/no-go is the last server evaluation (\(stalenessLine)), not a live one. Re-check on a connection before the consist is cleared to cross.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.warning.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.45), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Hero Card

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                let ok = compliance?.overallCompliant ?? false
                Text(ok ? "CLEARED" : "HOLD")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(ok ? Brand.success : Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill((ok ? Brand.success : Brand.danger).opacity(0.14)))
                Text(crossingLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.bgCardSoft))
                Spacer()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(failCount)")
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(failCount > 0 ? AnyShapeStyle(LinearGradient.expense) : AnyShapeStyle(LinearGradient.diagonal))
                    Text("blocker\(failCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(failCount > 0 ? "holds consist · must resolve" : "requirements met")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if hasDG, let d = detail {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DG CARS")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text("\(d.numberOfCars ?? 1)")
                            .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("\(d.hazmatClass ?? "") · UN\(d.unNumber ?? "-")")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    /// Spoken form of the hero. The freshness of the verdict is part of the
    /// sentence, so a cached CLEARED is never read aloud as a live one.
    private var heroAccessibilityLabel: String {
        let ok = compliance?.overallCompliant ?? false
        var s = ok ? "Cleared" : "Hold"
        s += ", \(crossingLabel), \(clearanceIsLive ? "live" : "cached, not live")."
        s += " \(failCount) blocker\(failCount == 1 ? "" : "s")."
        if hasDG, let d = detail {
            let cars = d.numberOfCars ?? 1
            s += " Dangerous goods on \(cars) car\(cars == 1 ? "" : "s")."
        }
        return s
    }

    // MARK: KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "REQUIREMENTS", value: "\(totalCount)")
            MetricTile(label: "PASSED",       value: "\(passCount)", gradientNumeral: passCount > 0)
            MetricTile(label: "BLOCKERS",     value: "\(failCount)", accent: failCount > 0 ? Brand.danger : nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(totalCount) requirement\(totalCount == 1 ? "" : "s"), \(passCount) passed, \(failCount) blocking.")
    }

    // MARK: Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CLEARANCE CHECKLIST · compliance check")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalCount)").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            LifecycleCard {
                let items = compliance?.regulatory ?? []
                if items.isEmpty {
                    Text("Compliance check pending.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            checkRow(item)
                            if idx < items.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkRow(_ item: ComplianceItem564) -> some View {
        let (glyph, tint, verdict) = verdictStyle(item.status)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.requirement)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(item.details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary).lineLimit(2)
                Text(item.regulation)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer()
            Text(verdict)
                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(tint)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.requirement), \(verdict.lowercased())")
        .accessibilityValue("\(item.details). \(item.regulation).")
    }

    private func verdictStyle(_ status: String) -> (String, Color, String) {
        switch status.lowercased() {
        case "pass":    return ("checkmark.circle",      Brand.success, "PASS")
        case "warning": return ("exclamationmark.triangle", Brand.warning, "WARNING")
        default:        return ("xmark.circle",          Brand.danger,  "FAIL")
        }
    }

    // MARK: Required Docs Strip

    private var docsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("REQUIRED DOCS · \(requiredDocs.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("border document rules")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(Array(requiredDocs.prefix(4).enumerated()), id: \.offset) { _, doc in
                Text("· \(doc)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if requiredDocs.count > 4 {
                Text("+\(requiredDocs.count - 4) more · SAT / CBP harmonized entry set")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Required documents, \(requiredDocs.count)")
        .accessibilityValue(requiredDocs.joined(separator: ", "))
    }

    // MARK: ESANG band (derived on device — see the ESANG note in the header)

    private var esangBand: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Image(systemName: "flag.2.crossed")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · CLEARANCE READ")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DERIVED ON DEVICE FROM THIS LADDER · NOT AN ASSISTANT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clearance read, derived on this device. \(esangHeadline) \(esangDetail)")
    }

    /// One sentence off the decoded ladder — the first blocking gate by name, or
    /// the honest cleared state. Never a fabricated instruction or saved-hours
    /// figure: there is no rail next-best-action source on the wire.
    private var esangHeadline: String {
        if let blocker = compliance?.regulatory.first(where: { $0.status.lowercased() == "fail" }) {
            return "Blocking gate: \(blocker.requirement)."
        }
        if totalCount == 0 { return "No clearance ladder has been returned for this crossing yet." }
        if failCount == 0 { return "All \(totalCount) gates are cleared for this crossing." }
        return "\(failCount) gate\(failCount == 1 ? "" : "s") still blocking this crossing."
    }

    private var esangDetail: String {
        if let blocker = compliance?.regulatory.first(where: { $0.status.lowercased() == "fail" }) {
            return "\(blocker.regulation) · \(blocker.details)"
        }
        return "\(passCount) of \(totalCount) cleared · \(stalenessLine)"
    }

    // MARK: Actions

    private var actionsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s2) {
                CTAButton(title: "Re-check clearance", action: { Task { await load() } },
                          leadingIcon: "arrow.clockwise", isLoading: loading)
                    .accessibilityLabel("Re-check clearance")
                    .accessibilityHint("Re-runs the cross-border compliance check against the server and re-stamps the freshness line.")
                // DEAD-PRIMARY CURE (§18): this slot shipped as a bare CTAButton
                // titled "Consist" with a tram leading icon and with neither an
                // action argument nor a trailing closure, so it inherited the
                // control's empty-closure default
                // (Theme/DesignSystem.swift:1486) — a full-gradient primary that
                // was permanently inert. Re-cut to the band's own cure for inert
                // secondaries (Views/Rail/RailSecondaryActionButton.swift:12,
                // the same control 566 and 586 use) over the consist facts this
                // screen has ALREADY decoded from the server. No new call, no
                // invented rows, and no fabricated success.
                RailSecondaryActionButton(
                    title: "Consist",
                    sheetTitle: "Consist context",
                    lines: consistContextLines,
                    width: 132,
                    systemImage: "tram.fill"
                )
                .accessibilityLabel("Consist context")
                .accessibilityHint("Opens the cars, railroad and waybill this clearance check is running against.")
            }
            if !reach.isOnline {
                Text("Offline · the ladder above is a cached read, and a customs filing is ONLINE_ONLY. Nothing is queued for replay.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Consist facts already decoded on this screen. Every line is a live server
    /// field or is omitted entirely — nothing is substituted or rounded in.
    private var consistContextLines: [String] {
        var lines: [String] = []
        if let num = detail?.shipmentNumber { lines.append("Shipment \(num)") }
        if let n = detail?.numberOfCars { lines.append("\(n) car\(n == 1 ? "" : "s") on the consist") }
        if let rr = detail?.originRailroad { lines.append("Origin railroad \(rr)") }
        if let wb = detail?.waybillNumber { lines.append("Waybill \(wb)") }
        if let dg = detail?.hazmatClass {
            if let un = detail?.unNumber {
                lines.append("Dangerous goods \(dg) · UN\(un)")
            } else {
                lines.append("Dangerous goods \(dg)")
            }
        }
        if let o = detail?.originYard?.name { lines.append("Origin yard \(o)") }
        if let d = detail?.destinationYard?.name { lines.append("Destination yard \(d)") }
        if let p = interchange {
            lines.append("Interchange \(p.name ?? interchangePointId) · \(p.customsOffice ?? "customs office not returned")")
        }
        lines.append("\(passCount) of \(totalCount) gates cleared · \(stalenessLine)")
        return lines
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct PointsIn: Encodable { let country: String; let railroad: String? }
        struct CheckIn: Encodable {
            let direction: String
            let interchangePointId: String
            let hasManifest: Bool
            let hasCrewCerts: Bool
            let hasDangerousGoods: Bool
            let hasDGDocs: Bool
            let hasCustomsDocs: Bool
            let hasInsurance: Bool
        }
        struct DocsIn: Encodable {
            let direction: String; let mode: String
            let hasHazmat: Bool; let hasOversized: Bool
        }
        do {
            let d: RailShipmentDetail564 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d

            let points: [RailInterchangePoint564] = try await EusoTripAPI.shared.query(
                "railShipments.getCrossBorderInterchangePoints",
                input: PointsIn(country: "MX", railroad: d.originRailroad))
            let point = points.first(where: { String($0.id) == interchangePointId }) ?? points.first
            self.interchange = point

            let dir = "\(point?.countryA ?? "US")_TO_\(point?.countryB ?? "MX")"
            let isDG = d.hazmatClass != nil

            let result: CrossBorderCompliance564 = try await EusoTripAPI.shared.query(
                "railShipments.checkCrossBorderRailCompliance",
                input: CheckIn(
                    direction: dir,
                    interchangePointId: interchangePointId,
                    hasManifest: d.waybillNumber != nil,
                    hasCrewCerts: true,
                    hasDangerousGoods: isDG,
                    hasDGDocs: isDG,
                    hasCustomsDocs: false,
                    hasInsurance: true
                ))
            self.compliance = result
            // §W READ_CACHED(5m): stamp the evaluation the moment the server
            // returns it. Everything drawn above ages against this stamp.
            self.lastReadAt = Date()

            do {
                let docs: [String] = try await EusoTripAPI.shared.query(
                    "railShipments.getCrossBorderRailDocs",
                    input: DocsIn(direction: dir, mode: "RAIL", hasHazmat: isDG, hasOversized: false))
                self.requiredDocs = docs
            } catch { /* non-blocking */ }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("564 · Border Clearance · Night") {
    RailBorderClearanceScreen(theme: Theme.dark, shipmentId: 1001, interchangePointId: "9")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("564 · Border Clearance · Light") {
    RailBorderClearanceScreen(theme: Theme.light, shipmentId: 1001, interchangePointId: "9")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
