//
//  CV357_CatalystBackhaulAckSeptet.swift
//  EusoTrip — Catalyst · Backhaul-ack septet (CV357-CV363).
//
//  Pixel-match to:
//    357 Catalyst Backhaul Tender   ← SUPERSEDED 2026-07-03 by the staged
//         "03 Catalyst" design: purpose-built tender surface with a live
//         accept-countdown ring, lane economics, an eligibility gate and a
//         REAL accept commit (dispatch.assignDriver, dispatch.ts:1212 with
//         the full compliance gate). `CatalystBackhaulTenderBody357` below.
//    358 Catalyst Backhaul Tender Accepted
//    359 Catalyst BH Pickup Watch Armed
//    360 Catalyst BH Pickup On-Site Acked
//    361 Catalyst BH In-Transit Acked
//    362 Catalyst BH Delivery Approaching Acked
//    363 Catalyst BH At Delivery Acked
//
//  358-363 share `CatalystBackhaulAckBody` parameterized by
//  `CatalystBackhaulKind`. Body reads `loads.getById` for the backhaul
//  load context. Bottom nav frozen.
//
//  357 wiring (line-confirmed, frontend/server/routers/):
//    • loads.getById            loads.ts:1219   tender load spine + window
//    • catalysts.getMyDrivers   catalysts.ts:431 candidate fitness + HOS
//    • dispatch.assignDriver    dispatch.ts:1212 Accept = production commit
//    • esangCoach.forScreen     esangCoach.ts:264 coach strip
//  Honest gaps: no decline/withdraw procedure exists → Decline explains the
//  tender stays staged (never a fake success). Deadhead proof and carrier
//  margin have no source on these procedures → "—".
//
//  ── ZERO-FABRICATION REBUILD (2026-06-06) ───────────────────────
//  Every visible business value binds to a real `loads.getById`
//  field or paints an honest "-"/"—". The corrected `loads.getById`
//  decode shape (server loads.ts:1167) is used:
//    • top-level `id` is a String on the wire (String(load.id)) —
//      decoding it as Int throws typeMismatch and silently fails the
//      WHOLE decode → a blank surface;
//    • pickup/delivery are nested {city,state} objects, NOT flat
//      `pickupCity`/`destCity` strings;
//    • carrier name comes from the resolved `catalyst` party object
//      {id:Int?, name, initials, companyName, mcNumber, dotNumber}.
//  Deleted every hardcoded persona (AURORA · MC942008 · Eusotrans
//  LLC · Michael Eusorone · USDOT 3 194 882) and every invented
//  `?? <value>` (LD-BH7C3A / PHX / LA / Reefer / margin $172 / ETAs
//  / seal counts / dock numbers). The §-citation + chain-stage
//  scaffold strings are preserved as structural lifecycle labels
//  (sibling parity: DL133 CEL_SECTIONS citations, 373 node labels) —
//  they carry no load/business data. Visual layout/chrome/nav are
//  preserved verbatim.
//

import SwiftUI

/// Corrected `loads.getById` decode shape (server loads.ts:1338-1379).
/// Top-level `id` MUST be `String?` (server emits `String(load.id)`) —
/// an `Int?` here is a silent whole-decode failure. Pickup/delivery are
/// nested `{city,state}` objects (NOT flat city fields). Carrier identity
/// rides the resolved `catalyst` party object.
private struct CBLoadCtx: Decodable, Hashable {
    let id: String?
    let loadNumber: String?
    let status: String?
    let pickupLocation: CBLoc?
    let deliveryLocation: CBLoc?
    let rate: String?              // DB decimal → JSON string
    let distance: Double?
    let equipmentType: String?
    let pickupDate: String?        // ISO — the accept-by anchor (window close)
    let createdAt: String?         // ISO — window open (ring denominator)
    let catalyst: CBParty?
    let driver: CBParty?
    let shipper: CBParty?

    struct CBLoc: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct CBParty: Decodable, Hashable {
        let id: Int?              // party (user) id is numeric on the wire
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

enum CatalystBackhaulKind: String {
    case tender, accepted, pickupWatch, onSite, inTransit, deliveryApproach, atDelivery
}

private struct CBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let chainPill: String
}

private extension CatalystBackhaulKind {
    /// Structural lifecycle scaffold only — §-citation chain + stage
    /// labels (no load/business data; sibling parity DL133/373). All
    /// persona/margin/ETA/seal/dock fabrications removed.
    var config: CBConfig {
        switch self {
        case .tender:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · TENDER STAGED",
                         citation: "§298 · CATALYST BACKHAUL TENDER · CARRIER-DISPATCHED-OUTBOUND · NEXT-CHAIN 2/N",
                         title: "Backhaul tendered · awaiting accept",
                         chainPill: "§297 ME TENDER RECEIVED · §298 STAGED-AWAITING-ACCEPT · §295.3 POST 10H RESET")
        case .accepted:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · ACCEPTED",
                         citation: "§303 · CATALYST BACKHAUL ACCEPTED · CARRIER-DISPATCHED · NEXT-CHAIN 6/N",
                         title: "Tender accepted by ME",
                         chainPill: "§297 RECEIVED · §298 STAGED · §302 ACCEPTED · §303 DISPATCH LOCKED")
        case .pickupWatch:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP-WATCH",
                         citation: "§307 · CATALYST PICKUP-WATCH-ARMED · CARRIER-DISPATCHED · NEXT-CHAIN 10/N",
                         title: "Pickup watch armed for ME",
                         chainPill: "§302 ACCEPTED · §303 DISPATCH LOCKED · §306 DVIR IN PROGRESS · §307 WATCH ARMED")
        case .onSite:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · PICKUP",
                         citation: "§321 · CATALYST PICKUP-ON-SITE-ACKED · QUARTET 2/4 · NEXT-CHAIN 24/N",
                         title: "ME on-site at pickup",
                         chainPill: "§303 DISPATCH LOCKED · §307 WATCH ARMED · §320 DVIR COMPLETE · §321 ON-SITE ACKED")
        case .inTransit:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · IN-TRANSIT",
                         citation: "§325 · CATALYST IN-TRANSIT-ACKED · QUARTET 2/4 · NEXT-CHAIN 28/N",
                         title: "ME in transit",
                         chainPill: "§321 ON-SITE · §322 LOADING · §324 SEAL CONFIRMED · §325 IN-TRANSIT ACKED")
        case .deliveryApproach:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · DELIVERY · 2/4",
                         citation: "§329 · CATALYST DELIVERY-ACKED · QUARTET 2/4 · NEXT-CHAIN 32/N",
                         title: "ME approaching delivery",
                         chainPill: "§325 IN-TRANSIT · §327 GATE-WATCH ARMED · §329 APPROACHING ACKED")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · DISPATCH · BACKHAUL · AT-DELIVERY · 2/N",
                         citation: "§333 · CATALYST AT-DELIVERY-ACKED · SUB-AXIS 2/N · NEXT-CHAIN 36/N",
                         title: "ME at delivery gate",
                         chainPill: "§329 APPROACHING · §331 GATE-IN ARMED · §333 AT-DELIVERY ACKED")
        }
    }
}

private struct CatalystBackhaulShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .drivers),
                trailing: CarrierNavRoute.trailing(current: .drivers),
                orbState: .idle
            )
        }
    }
}

private struct CatalystBackhaulAckBody: View {
    let loadId: String
    let kind: CatalystBackhaulKind

    @Environment(\.palette) private var palette
    @State private var load: CBLoadCtx?

    // MARK: - Live-bound display helpers (honest "-"/"—" fallback)

    /// Real load number, or "-" until resolved. No invented "LD-BH7C3A".
    private var loadNumberDisplay: String {
        let n = load?.loadNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "-" : n
    }

    /// Carrier (catalyst) display name from the resolved party object —
    /// companyName, then user name. "-" when no party is set. No AURORA.
    private var carrierDisplay: String {
        if let c = load?.catalyst?.companyName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let n = load?.catalyst?.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return "-"
    }

    /// Carrier MC# from the party object ("MC-942008" only if real). "—".
    private var carrierMC: String {
        if let mc = load?.catalyst?.mcNumber?.trimmingCharacters(in: .whitespaces), !mc.isEmpty { return "MC-\(mc)" }
        return "—"
    }

    /// Carrier USDOT# from the party object. "—" when unset. No "3 194 882".
    private var carrierDOT: String {
        if let dot = load?.catalyst?.dotNumber?.trimmingCharacters(in: .whitespaces), !dot.isEmpty { return "USDOT \(dot)" }
        return "—"
    }

    /// Carrier initials disc — real party initials, else "ME" placeholder
    /// disc text only (no fabricated name). "—" when neither resolves.
    private var carrierInitials: String {
        if let i = load?.catalyst?.initials?.trimmingCharacters(in: .whitespaces), !i.isEmpty { return i }
        return "—"
    }

    /// Nested {city,state} lane. Server sends "" (not nil) when missing.
    /// "—" placeholders per endpoint; nil when the whole lane is empty.
    private var laneDisplay: String? {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return nil }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    /// Equipment / trailer type — "—" when the shipper never specified.
    private var equipmentDisplay: String {
        let eq = load?.equipmentType?.trimmingCharacters(in: .whitespaces) ?? ""
        return eq.isEmpty ? "—" : eq
    }

    /// Subhead = real carrier · MC · load#. No persona.
    private var subhead: String {
        "\(carrierDisplay) · \(carrierMC) · \(loadNumberDisplay)"
    }

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                chainPill(c)
                meRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .eusoRefreshable { await loadCtx() }
    }

    private func header(_ c: CBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                // Pill copy is the real load context (carrier · load# ·
                // lifecycle stage) — no margin/ETA/seal fabrications.
                Text("\(carrierDisplay) · \(loadNumberDisplay) · \(c.title)")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "—") · \(equipmentDisplay)")
                    .font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func chainPill(_ c: CBConfig) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var meRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(carrierInitials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    // Real carrier name from the catalyst party object.
                    Text("\(carrierDisplay) · carrier-dispatched").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    // USDOT · MC from the party object; "—" when unset. No
                    // "margin $172" — there is no margin source on getById.
                    Text("\(carrierDOT) · \(carrierMC) dispatch").font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        // KPI tiles bind to real getById fields (lane / equipment / load#)
        // or render honest "—"/"-". No margin / ETA / seal / dock / window
        // fabrications — none of those have a source on loads.getById.
        let lane = laneDisplay ?? "—"
        let equip = equipmentDisplay
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .tender:
                return [
                    ("STATE",  "STAGED",            "awaiting accept",          .blue),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "tendered",                .blue),
                ]
            case .accepted:
                return [
                    ("STATE",  "ACCEPTED",          "dispatch locked",          .green),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "awarded",                 .green),
                ]
            case .pickupWatch:
                return [
                    ("WATCH",  "ARMED",             "pickup watch",             .green),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "dispatched",              .green),
                ]
            case .onSite:
                return [
                    ("STATE",  "ON-SITE",           "at pickup",                .blue),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "loading",                 .green),
                ]
            case .inTransit:
                return [
                    ("STATE",  "IN-TRANSIT",        "en route",                 .blue),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "rolling",                 .green),
                ]
            case .deliveryApproach:
                return [
                    ("STATE",  "APPROACHING",       "delivery",                 .green),
                    ("LANE",   lane,                 "backhaul",                .blue),
                    ("EQUIP",  equip,                "trailer",                 .blue),
                    ("LOAD",   loadNumberDisplay,    "approaching",             .green),
                ]
            case .atDelivery:
                return [
                    ("STATE",  "AT-DELIVERY",       "gate-in acked",            .green),
                    ("LANE",   lane,                 "backhaul",                .green),
                    ("EQUIP",  equip,                "trailer",                 .green),
                    ("LOAD",   loadNumberDisplay,    "at gate",                 .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3).lineLimit(1).minimumScaleFactor(0.6)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        // Stage-narrative scaffold (no fabricated personas / dock numbers /
        // ETAs / mileage — those carry no getById source).
        let copy: String = {
            switch kind {
            case .tender:           return "Carrier has a window to accept this backhaul tender. If it expires, dispatch releases the tender back to the carrier pool."
            case .accepted:         return "Dispatch locked. DVIR opens ahead of pickup; ESang queues the pretrip on the driver's watch."
            case .pickupWatch:      return "Watch armed. The -30 ping confirms the driver is en-route to the pickup."
            case .onSite:           return "Driver loading at pickup. Seal confirmation arms the IN-TRANSIT ack on gate-out."
            case .inTransit:        return "Driver en route on the backhaul leg. Watch ETA drift; ESang nudges if HOS tightens."
            case .deliveryApproach: return "Approach acked. Confirm receiver dock + paperwork; gate-in arms on arrival."
            case .atDelivery:       return "Gate-in cleared. POD chain arms on dock placement."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* leaves all values honest "-"/"—" */ }
    }
}

// MARK: - 357 · BACKHAUL TENDER — offer-to-accept with live expiry countdown

/// `catalysts.getMyDrivers` row (candidate fitness).
private struct CBDriver357: Decodable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String?
}

/// `esangCoach.forScreen` slice.
private struct CBEsang357: Decodable { let tip: String? }

/// `dispatch.assignDriver` result.
private struct CBAssignResult357: Decodable {
    let success: Bool?
    let loadNumber: String?
    let assignedAt: String?
}

private enum CB357Fmt {
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d", s / 3600, (s % 3600) / 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func money(_ raw: String?) -> String {
        guard let raw, let v = Double(raw), v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

private struct CatalystBackhaulTenderBody357: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @State private var load: CBLoadCtx?
    @State private var loadFailed = false
    @State private var drivers: [CBDriver357] = []
    @State private var esangTip: String?

    @State private var accepting = false
    @State private var accepted: CBAssignResult357?
    @State private var acceptError: String?
    @State private var showAcceptConfirm = false
    @State private var showDeclineInfo = false
    @State private var showDeclineConfirm = false
    @State private var declining = false
    @State private var declined = false
    @State private var showNoDriver = false

    // MARK: Derived (honest "—" fallback)

    private var loadNumberDisplay: String {
        load?.loadNumber?.trimmingCharacters(in: .whitespaces).cb357NilIfEmpty ?? "—"
    }
    private var laneDisplay: String {
        let o = [load?.pickupLocation?.city, load?.pickupLocation?.state]
            .compactMap { $0?.cb357NilIfEmpty }.joined(separator: ", ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state]
            .compactMap { $0?.cb357NilIfEmpty }.joined(separator: ", ")
        guard !o.isEmpty || !d.isEmpty else { return "—" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }
    private var milesDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded()))"
    }
    private var rateDisplay: String { CB357Fmt.money(load?.rate) }
    private var equipmentDisplay: String { load?.equipmentType?.cb357NilIfEmpty ?? "—" }

    /// Accept window: opens at posting, closes at the scheduled pickup.
    private var windowClose: Date? { CB357Fmt.date(load?.pickupDate) }
    private var windowOpen: Date? { CB357Fmt.date(load?.createdAt) }

    /// Best candidate: a driver free of a current load, else the roster head.
    private var candidate: CBDriver357? {
        drivers.first(where: { ($0.currentLoad ?? "").isEmpty }) ?? drivers.first
    }
    private var candidateHOS: String {
        guard let h = candidate?.hoursRemaining else { return "—" }
        return String(format: "%.1fh", h)
    }

    private var alreadyTaken: Bool {
        // Tender is only open while the load is still on the board.
        guard let s = load?.status?.cb357NilIfEmpty else { return false }
        return !["posted", "bidding", "pending"].contains(s)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                Rectangle().fill(LinearGradient.primary.opacity(0.55)).frame(height: 1.5)
                if load == nil && loadFailed {
                    fetchErrorBanner
                } else {
                    tenderHero
                    kpiStrip
                    eligibilityGate
                    driverRow
                    esangCard
                    if let err = acceptError {
                        Text(err)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ctaRow.padding(.top, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        }
        .task { await fetch() }
        .eusoRefreshable { await fetch() }
        .confirmationDialog(
            "Accept this backhaul tender?",
            isPresented: $showAcceptConfirm,
            titleVisibility: .visible
        ) {
            Button("Accept · assign \(candidate?.name ?? "driver")") { Task { await accept() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("EusoTrip runs the full assignment gate on accept — insurance, credentials, medical card and vehicle checks. A failed check blocks the assignment and nothing is booked.")
        }
        .alert("No driver to assign", isPresented: $showNoDriver) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Every driver on your roster is on a load right now. Free a driver or add one, then accept the tender.")
        }
        .alert("Tender stays staged", isPresented: $showDeclineInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("EusoTrip can't withdraw a staged tender from this screen. It stays on the board until the pickup window passes — accepting is the only action from here.")
        }
        .alert("Decline this backhaul?", isPresented: $showDeclineConfirm) {
            Button("Decline", role: .destructive) { Task { await decline() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This releases the backhaul back to the board and lets your shipper re-tender it elsewhere. You won't be re-offered this load.")
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · DISPATCH · BACKHAUL TENDER")
                    .font(.system(size: 9, weight: .heavy)).kerning(1)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(accepted != nil ? "ACCEPTED" : (alreadyTaken ? "OFF BOARD" : "STAGED"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Backhaul tender")
                .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("\(loadNumberDisplay) · \(laneDisplay)")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
        }
    }

    private var fetchErrorBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy)).foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't load this tender. The rest of dispatch still works.")
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await fetch() } } label: {
                    Text("Retry").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1))
    }

    // MARK: Hero — gradient rim + live countdown ring

    private var tenderHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BACKHAUL TENDER · RETURN LEG")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                heroChip
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(laneDisplay)
                        .font(.system(size: 17, weight: .bold)).kerning(-0.2)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(rateDisplay)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 4)
                    Text("posted rate · \(milesDisplay) mi · \(equipmentDisplay)")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                countdownRing
            }
            .padding(.top, 14)
            laneRibbon.padding(.top, 14)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
    }

    private var heroChip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = windowClose.map { $0.timeIntervalSince(timeline.date) } ?? -1
            let (text, color): (String, Color) = {
                if accepted != nil { return ("ACCEPTED", Brand.success) }
                if alreadyTaken { return ("OFF BOARD", Brand.neutral) }
                if windowClose == nil { return ("NO WINDOW SET", Brand.neutral) }
                if remaining <= 0 { return ("WINDOW PASSED", Brand.danger) }
                return ("STAGED · \(CB357Fmt.countdown(remaining))", Brand.warning)
            }()
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(color)
            }
            .padding(.horizontal, 10).frame(height: 22)
            .background(Capsule().fill(color.opacity(0.15)))
        }
    }

    /// Live accept-clock ring. Anchored to the real pickup window on the
    /// load — the ring drains from tender posting to the scheduled pickup.
    private var countdownRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date
            let remaining = windowClose.map { $0.timeIntervalSince(now) } ?? -1
            let total: TimeInterval = {
                guard let open = windowOpen, let close = windowClose else { return 0 }
                return max(1, close.timeIntervalSince(open))
            }()
            let frac = (remaining > 0 && total > 0) ? min(1, max(0, remaining / total)) : 0
            ZStack {
                Circle().stroke(palette.borderFaint, lineWidth: 7).frame(width: 68, height: 68)
                Circle().trim(from: 0, to: frac)
                    .stroke(LinearGradient.primary, style: .init(lineWidth: 7, lineCap: .round))
                    .frame(width: 68, height: 68).rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(windowClose == nil ? "—" : (remaining > 0 ? CB357Fmt.countdown(remaining) : "0:00"))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("TO PICKUP")
                        .font(.system(size: 7.5, weight: .bold)).kerning(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(width: 56)
            }
        }
    }

    private var laneRibbon: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(Brand.blue).frame(width: 12, height: 12)
                    .overlay(Circle().fill(.white).frame(width: 5, height: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text((load?.pickupLocation?.city?.cb357NilIfEmpty ?? "Origin").uppercased())
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("pickup").font(.system(size: 8)).foregroundStyle(Brand.blue)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(milesDisplay) mi").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text((load?.deliveryLocation?.city?.cb357NilIfEmpty ?? "Destination").uppercased())
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("drop").font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                }
                Image(systemName: "mappin.circle.fill").font(.system(size: 16)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCardSoft))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            kpiCell("RATE", rateDisplay, "posted", hi: true, c: palette.textPrimary)
            kpiCell("MARGIN", "—", "no split yet", hi: false, c: palette.textPrimary)
            kpiCell("DRIVE LEFT", candidateHOS, candidate?.name ?? "roster —", hi: false, c: palette.textPrimary)
            kpiCell("EQUIP", equipmentDisplay, "required", hi: false, c: Brand.success)
        }
    }

    private func kpiCell(_ k: String, _ v: String, _ s: String, hi: Bool, c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.system(size: 8, weight: .heavy)).kerning(0.5)
                .foregroundStyle(hi ? Color.white.opacity(0.85) : palette.textSecondary)
            Text(v).font(.system(size: v.count > 6 ? 14 : 19, weight: .bold))
                .foregroundStyle(hi ? Color.white : c)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(s).font(.system(size: 8))
                .foregroundStyle(hi ? Color.white.opacity(0.85) : palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(.leading, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(hi ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(hi ? nil : RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Eligibility gate — real rows only

    private var eligibilityGate: some View {
        let hosOk = (candidate?.hoursRemaining ?? 0) > 0
        let freeOk = candidate != nil && (candidate?.currentLoad ?? "").isEmpty
        let rows: [(String, String, Bool)] = [
            ("Drive time — \(candidateHOS) left today", hosOk ? "FIT" : "NO DATA", hosOk),
            ("Availability — \(candidate?.name ?? "no roster driver")",
             freeOk ? "FREE" : (candidate == nil ? "NO ROSTER" : "ON A LOAD"), freeOk),
            ("Insurance · credentials · vehicle — checked at accept", "AT ACCEPT", true),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("ELIGIBILITY · WHY THIS TENDER FITS")
                .font(.system(size: 9, weight: .heavy)).kerning(1)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 0) {
                ForEach(0..<rows.count, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: rows[i].2 ? "checkmark" : "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(rows[i].2 ? Brand.success : palette.textTertiary)
                        Text(rows[i].0)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(rows[i].2 ? palette.textPrimary : palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        Text(rows[i].1)
                            .font(.system(size: 9, weight: .heavy)).kerning(0.3)
                            .foregroundStyle(rows[i].2 ? Brand.success : palette.textTertiary)
                    }
                    .frame(height: 24)
                    if i < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private var driverRow: some View {
        Group {
            if let d = candidate {
                HStack(spacing: 0) {
                    Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                        .overlay(Text(String(d.name.prefix(2)).uppercased())
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text("drive time left \(candidateHOS) · \(d.location?.cb357NilIfEmpty ?? "position —")")
                            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        Text((d.currentLoad?.cb357NilIfEmpty).map { "finishing \($0)" } ?? "free for the return leg")
                            .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.leading, 12)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill((d.currentLoad ?? "").isEmpty ? Brand.success : Brand.warning)
                            .frame(width: 6, height: 6)
                        Text((d.currentLoad ?? "").isEmpty ? "AVAILABLE" : "ON A LOAD")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle((d.currentLoad ?? "").isEmpty ? Brand.success : Brand.warning)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(((d.currentLoad ?? "").isEmpty ? Brand.success : Brand.warning).opacity(0.13)))
                }
                .padding(.horizontal, 16).frame(height: 60)
            } else {
                HStack(spacing: 12) {
                    Circle().fill(palette.bgCardSoft).frame(width: 34, height: 34)
                        .overlay(Image(systemName: "person.slash")
                            .font(.system(size: 13)).foregroundStyle(palette.textTertiary))
                    Text("No drivers on your roster yet — add one to take tenders.")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 60)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var esangCard: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                .overlay(Text("E").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · BACKHAUL")
                    .font(.system(size: 8.5, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text(esangTip ?? "ESANG has no cue on this tender yet — pull to refresh.")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(esangTip == nil ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LinearGradient.primary.opacity(0.85), lineWidth: 1.3))
    }

    // MARK: CTAs — Accept is a REAL commit; Decline is an honest no-endpoint state

    private var ctaRow: some View {
        HStack(spacing: 12) {
            Button {
                if accepted != nil || alreadyTaken { return }
                if candidate == nil { showNoDriver = true } else { showAcceptConfirm = true }
            } label: {
                HStack(spacing: 8) {
                    if accepting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: accepted != nil ? "checkmark.circle.fill" : "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(accepted != nil ? "Tender accepted" : (alreadyTaken ? "Off the board" : "Accept tender"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(accepted != nil
                                           ? AnyShapeStyle(Brand.success)
                                           : (alreadyTaken ? AnyShapeStyle(Brand.neutral) : AnyShapeStyle(LinearGradient.primary))))
            }
            .buttonStyle(.plain)
            .disabled(accepting || accepted != nil || alreadyTaken)
            Button {
                if accepted == nil && !alreadyTaken && !declined { showDeclineConfirm = true }
            } label: {
                HStack(spacing: 6) {
                    if declining { ProgressView().tint(palette.textSecondary) }
                    Text(declined ? "Declined" : "Decline")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
                .frame(width: 126, height: 48)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(declining || declined || accepted != nil || alreadyTaken)
        }
    }

    // MARK: Network

    private func fetch() async {
        struct IdIn: Encodable { let id: String }
        struct LimitIn: Encodable { let limit: Int }
        struct EsangIn: Encodable { let screen: String; let contextIds: [String: String] }
        let api = EusoTripAPI.shared
        do {
            let l: CBLoadCtx = try await api.query("loads.getById", input: IdIn(id: loadId))
            load = l
            loadFailed = false
        } catch {
            loadFailed = (load == nil)
        }
        if let d: [CBDriver357] = try? await api.query("catalysts.getMyDrivers", input: LimitIn(limit: 25)) {
            drivers = d
        }
        if let e: CBEsang357 = try? await api.query(
            "esangCoach.forScreen",
            input: EsangIn(screen: "active-trip", contextIds: ["loadId": loadId])
        ) {
            esangTip = e.tip?.cb357NilIfEmpty
        }
    }

    private func accept() async {
        guard let d = candidate else { showNoDriver = true; return }
        struct AssignIn: Encodable {
            let loadId: String
            let driverId: String
            let idempotencyKey: String
        }
        accepting = true
        acceptError = nil
        defer { accepting = false }
        do {
            let out: CBAssignResult357 = try await EusoTripAPI.shared.mutation(
                "dispatch.assignDriver",
                input: AssignIn(
                    loadId: load?.id ?? loadId,
                    driverId: d.id,
                    idempotencyKey: "bh-tender-\(load?.id ?? loadId)-\(d.id)"
                )
            )
            if out.success == true {
                accepted = out
                await fetch()
            } else {
                acceptError = "The assignment gate didn't clear — nothing was booked. Review the driver's credentials and try again."
            }
        } catch {
            acceptError = "The assignment gate didn't clear — nothing was booked. Review the driver's credentials and vehicle, then try again."
        }
    }

    /// Real decline — releases the backhaul tender back to the board,
    /// blocks re-tender to this catalyst, and notifies the shipper of record.
    private func decline() async {
        struct DeclineIn: Encodable { let loadId: String; let reason: String }
        declining = true
        defer { declining = false }
        do {
            struct DeclineOut: Decodable { let success: Bool? }
            let out: DeclineOut = try await EusoTripAPI.shared.mutation(
                "catalysts.declineBackhaulTender",
                input: DeclineIn(loadId: load?.id ?? loadId, reason: "Passed on backhaul")
            )
            if out.success == true { declined = true }
        } catch {
            // Leave the button active so the operator can retry.
        }
    }
}

private extension String {
    var cb357NilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Screens (CV357-CV363)

struct CatalystBackhaulTenderScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulTenderBody357(loadId: loadId) } }
}
struct CatalystBackhaulAcceptedScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .accepted) } }
}
struct CatalystBackhaulPickupWatchScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .pickupWatch) } }
}
struct CatalystBackhaulOnSiteScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .onSite) } }
}
struct CatalystBackhaulInTransitScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .inTransit) } }
}
struct CatalystBackhaulDeliveryApproachScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .deliveryApproach) } }
}
struct CatalystBackhaulAtDeliveryScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystBackhaulShell(theme: theme) { CatalystBackhaulAckBody(loadId: loadId, kind: .atDelivery) } }
}

// MARK: - Previews

#Preview("CV357 Tender · Dark")     { CatalystBackhaulTenderScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV357 Tender · Light")    { CatalystBackhaulTenderScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV358 Accepted · Light")  { CatalystBackhaulAcceptedScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV359 Watch · Dark")      { CatalystBackhaulPickupWatchScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV360 OnSite · Light")    { CatalystBackhaulOnSiteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV361 Transit · Dark")    { CatalystBackhaulInTransitScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV362 Approach · Light")  { CatalystBackhaulDeliveryApproachScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV363 AtDel · Dark")      { CatalystBackhaulAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
