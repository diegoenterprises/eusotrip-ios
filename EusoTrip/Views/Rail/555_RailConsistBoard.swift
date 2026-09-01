//
//  555_RailConsistBoard.swift
//  EusoTrip — Rail Engineer · Consist Board (carrier vantage).
//
//  VERIFIED COUNTER-PARTIES (live source, dist/ excluded)
//    railShipments.getTrainConsists   EXISTS railShipments.ts:1332  QUERY
//                                     railReadProcedure — RAIL_ENGINEER in cohort
//    railShipments.createConsist      EXISTS railShipments.ts:1454  MUTATION
//                                     railOpsWriteProcedure — RAIL_ENGINEER in cohort
//
//  WHY THIS BOARD DOES NOT CALL createConsist ITSELF
//    createConsist REQUIRES { trainId, carrierId, originYardId,
//    destinationYardId, railcarIds[] }. This screen is a read-only roster: it
//    folds the yard IDs into display strings and never resolves a railcar, so
//    it cannot supply a single field of that payload without inventing one.
//    The real cut composer is Rail688 (RailConsistBoard_688, registered
//    `.railEngineer` at ContentView.swift:2424), which sources every field
//    from decoded rows and calls createConsist for real. The primary CTA hands
//    off to that composer rather than firing a no-op.
//
//  §W OFFLINE POLICY — ONLINE_ONLY
//    Reason: a consist's car makeup and its corridor crosswind are live yard /
//    live weather state. A cached makeup is a safety claim about which cars are
//    coupled right now, and a cached gust is a speed-restriction claim; neither
//    may be replayed from disk. Honoured by construction: this screen writes no
//    cache and enqueues nothing — a failed read renders the transport error in
//    place of the roster, never a stale or defaulted one.
//

import SwiftUI

struct RailConsistBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConsistBoardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct TrainConsist: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let originYard: String?
    let destinationYard: String?
    let totalCars: Int?
    let assignedCars: Int?
    let hazmatCars: Int?
    let status: String?
    let note: String?
    /// Per-consist crosswind envelope (Wave 4-server #85). The server ships
    /// the RAW gust + corridor risk — NOT a verdict; the screen decides the
    /// display threshold. Enterprise-gated, so `available == false` /
    /// `maxWindGust == nil` today until the key lands.
    let crosswind: Crosswind?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, status
        case originYardId, destinationYardId
        case locomotiveUnits, totalWeight, totalLengthFeet, trainType
        case departureTime, arrivalTime, engineerId, conductorId, railroadId, ptcActive
        case createdAt, updatedAt
        case crosswind
    }

    /// `railShipments.getTrainConsists` → per-consist `crosswind`. Raw gust +
    /// corridor risk; never a verdict. `available`/`maxWindGust` are
    /// enterprise-gated (false/null until the key lands).
    struct Crosswind: Decodable, Hashable {
        let available: Bool?
        let maxWindGust: Double?   // mph — raw peak gust on the corridor
        let enterprise: Bool?
        let overallRisk: String?   // "low" | "moderate" | "high" | "extreme" | "unknown"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        self.totalCars = try c.decodeIfPresent(Int.self, forKey: .totalCars)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        // Server returns IDs; iOS struct expects display strings. Default to nil if ID missing.
        let originYardId = try c.decodeIfPresent(Int.self, forKey: .originYardId)
        let destYardId = try c.decodeIfPresent(Int.self, forKey: .destinationYardId)
        self.originYard = originYardId.map { "Yard #\($0)" }
        self.destinationYard = destYardId.map { "Yard #\($0)" }
        // ROOT CAUSE of the two nils below — this is NOT a decode workaround.
        // `getTrainConsists` runs a bare `db.select().from(trainConsists)`
        // (railShipments.ts:1346) and spreads only `crosswind` on top, so the
        // payload is exactly the `train_consists` row. That table
        // (drizzle/schema.ts:11250-11268) has NO `assignedCars` column and NO
        // `hazmatCars` column — the server cannot return either field today.
        //
        // Both ARE derivable server-side and simply are not derived:
        //   assignedCars = COUNT(consist_cars WHERE consistId = c.id
        //                        AND status = 'coupled')      schema.ts:11277
        //   hazmatCars   = COUNT(consist_cars JOIN rail_shipments
        //                        ON consist_cars.shipmentId = rail_shipments.id
        //                        WHERE rail_shipments.hazmatClass IS NOT NULL)
        //                                                     schema.ts:11214
        // (`railcars` itself carries no hazmat flag — hazmat lives on the
        // shipment, so the car-level answer must come through that join.)
        //
        // Until getTrainConsists computes them, nil is the only honest value.
        // The render side MUST NOT coalesce these — see `consistCard`.
        // STUB · named-gap: RAIL-GAP-555-CONSIST-AGGREGATES.
        self.assignedCars = nil
        self.hazmatCars = nil
        self.note = nil
        self.crosswind = try c.decodeIfPresent(Crosswind.self, forKey: .crosswind)
    }
}

private struct ConsistsResponse: Decodable {
    let consists: [TrainConsist]
    let total: Int
}

private struct RailConsistBoardBody: View {
    @Environment(\.palette) private var palette
    @State private var consists: [TrainConsist] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading consists…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if consists.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill", title: "No consists",
                                   subtitle: "Building and rolling consists will appear here.")
                } else {
                    VStack(spacing: Space.s2) { ForEach(consists) { consistCard($0) } }
                    buildConsistCTA
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · CONSISTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Consist board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(rosterSummary)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .accessibilityLabel(rosterSummary)
        }
    }

    /// The fleet car total is a sum of REPORTED counts only. The old
    /// `reduce(0) { $0 + ($1.totalCars ?? 0) }` folded every unreported consist
    /// in as a zero and then presented the short sum as "cars total", which
    /// under-reports the roster without saying so. When any consist withholds
    /// its count the figure is labelled as partial instead.
    private var rosterSummary: String {
        let reported = consists.compactMap { $0.totalCars }
        let unreported = consists.count - reported.count
        let head = "\(consists.count) consists on the board"
        guard !reported.isEmpty else { return "\(head) · car counts not reported" }
        let sum = reported.reduce(0, +)
        return unreported == 0
            ? "\(head) · \(sum) cars total"
            : "\(head) · \(sum) cars across \(reported.count) consists · \(unreported) not reporting a count"
    }

    private func consistCard(_ c: TrainConsist) -> some View {
        // `train_consists.status` is the enum building | ready | departed |
        // in_transit | arrived | broken_up (drizzle/schema.ts:11262). "rolling"
        // is NOT a member, so the previous `== "rolling"` test could never be
        // true — which silently killed the crosswind speed-restriction banner
        // below. Mirror the server's own ROLLING set (railShipments.ts:1370).
        let statusRaw = (c.status ?? "").lowercased()
        let rolling = statusRaw == "departed" || statusRaw == "in_transit"
        // NO `?? 0` and NO `?? total` — an unreported count stays unreported.
        let total = c.totalCars
        let assigned = c.assignedCars.map { min($0, total ?? $0) }
        let hazmat = c.hazmatCars.map { min($0, total ?? $0) }
        // The makeup line reports what the feed actually said. It never spells
        // an unreported assignment as "48/48" (fabricated 100% completion).
        let makeupText: String = {
            guard let total else { return "car count not reported" }
            guard let assigned else { return "\(total) cars · makeup not reported" }
            return "\(assigned)/\(total) cars"
        }()
        let routeText = "\(c.originYard ?? "-") → \(c.destinationYard ?? "-") · \(makeupText)\(c.note.map { " · \($0)" } ?? "")"
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(c.consistNumber ?? "-").font(.system(size: 15, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (c.status ?? "-").uppercased(), kind: rolling ? .info : .neutral)
            }
            Text(routeText)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            ConsistCarStrip555(total: total, assigned: assigned, hazmat: hazmat, trackTint: palette.textTertiary)
            // SUPPRESS THE VERDICT — hazmat is a safety judgement and the feed
            // does not carry the input. Say so in words rather than let the
            // strip paint a clean consist out of a missing count.
            if hazmat == nil {
                Text("Hazmat cars not reported — this strip cannot show which cars carry hazardous materials. Check the consist's shipping papers.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Crosswind speed-restriction banner — only on a ROLLING consist
            // with a REAL available gust. Honestly hidden otherwise (enterprise
            // gate today). The screen decides the verdict from the raw gust.
            if rolling, let cw = c.crosswind {
                CrosswindRestrictionBanner555(crosswind: cw)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Consist \(c.consistNumber ?? "unnamed"), status \(c.status ?? "not reported")")
        .accessibilityValue(
            routeText
                + (hazmat == nil
                   ? ". Hazmat cars not reported; hazardous materials cannot be shown for this consist."
                   : "")
        )
    }

    /// `railShipments.createConsist` EXISTS (railShipments.ts:1454) and the
    /// Rail Engineer is inside `railOpsWriteProcedure`'s cohort — the gap is
    /// NOT the procedure. It is that this read-only roster holds none of the
    /// five required inputs (trainId, carrierId, originYardId,
    /// destinationYardId, railcarIds[]) and may not invent them. Rail688 is
    /// the registered composer that does hold them, so the CTA stays live and
    /// hands off there instead of running the old empty body.
    private var buildConsistCTA: some View {
        CTAButton(
            title: "Build new consist",
            action: {
                NotificationCenter.default.post(
                    name: .eusoRailNavSwap, object: nil,
                    userInfo: ["screenId": "Rail688"])
            },
            leadingIcon: "plus",
            subtitle: "OPENS THE CUT COMPOSER"
        )
        .accessibilityLabel("Build new consist")
        .accessibilityHint("Opens the consist cut composer, where the yards and railcars for the new consist are selected.")
    }

    private func load() async {
        loading = true; loadError = nil
        struct ConsistsIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: ConsistsResponse = try await EusoTripAPI.shared.query(
                "railShipments.getTrainConsists", input: ConsistsIn(limit: 20, offset: 0))
            self.consists = result.consists
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Crosswind speed-restriction banner
//
// A bespoke per-consist banner that surfaces the rail crosswind hazard on a
// ROLLING consist. The server (railShipments.getTrainConsists, Wave 4) ships
// the RAW peak gust (`maxWindGust`, mph) + the corridor `overallRisk` — it is
// deliberately NOT a verdict. This screen owns the operating threshold the way
// a rail dispatcher would call it off the wind speed:
//
//   • ≥ 60 mph  → "STOP"               (high-wind stop order, danger)
//   • ≥ 40 mph  → "SPEED RESTRICTION"  (reduce-speed order, danger/warn by risk)
//   • <  40 mph → "CROSSWIND ADVISORY" (informational, no operating action)
//
// Honest empty state: the banner renders NOTHING when the feed isn't available
// (`available != true`) or there's no real gust (`maxWindGust == nil`) — which
// is the enterprise-gated reality today. It lights up the instant the key lands
// and the server starts returning a real gust. We never fabricate a gust value.
//
// Idiom: a bespoke full-width restriction strip (not the HERE capsule chip) —
// the consist card is a dense list row, so the banner reads as a leading
// rule + WeatherIcons.utility(.wind) glyph + a hard restriction verdict +
// the real "max gust" readout, tinted to the threshold/risk color. ZERO SF
// Symbols: the wind glyph is the v2 WeatherIcons utility port.
private struct CrosswindRestrictionBanner555: View {
    @Environment(\.palette) private var palette
    let crosswind: TrainConsist.Crosswind

    /// Display threshold the screen applies to the raw gust → operating verdict.
    private enum Restriction { case stop, reduce, advisory }

    var body: some View {
        // Honest gate: only when the feed says available AND a real gust exists.
        if crosswind.available == true, let gust = crosswind.maxWindGust {
            banner(gust: gust)
        }
    }

    private func restriction(gust: Double) -> Restriction {
        if gust >= 60 { return .stop }
        if gust >= 40 { return .reduce }
        return .advisory
    }

    /// Verdict color: the operating threshold sets the floor, and a worse
    /// corridor `overallRisk` can only escalate it (never soften it). Both are
    /// real signals — the gust threshold the screen owns + the server's risk.
    private func color(for r: Restriction, risk: String?) -> Color {
        let thresholdColor: Color = {
            switch r {
            case .stop:     return Brand.danger
            case .reduce:   return Brand.warning
            case .advisory: return Brand.info
            }
        }()
        let riskColor: Color? = {
            switch (risk ?? "").lowercased() {
            case "extreme", "severe", "high": return Brand.danger
            case "moderate":                  return Brand.warning
            case "low", "none", "clear":      return Brand.success
            default:                          return nil   // "unknown"/absent → no escalation
            }
        }()
        // Escalate-only: danger > warning > info/success.
        func rank(_ c: Color) -> Int {
            if c == Brand.danger { return 3 }
            if c == Brand.warning { return 2 }
            if c == Brand.info { return 1 }
            return 0
        }
        guard let rc = riskColor else { return thresholdColor }
        return rank(rc) > rank(thresholdColor) ? rc : thresholdColor
    }

    private func label(for r: Restriction) -> String {
        switch r {
        case .stop:     return "STOP · HIGH WIND"
        case .reduce:   return "SPEED RESTRICTION"
        case .advisory: return "CROSSWIND ADVISORY"
        }
    }

    private func banner(gust: Double) -> some View {
        let r = restriction(gust: gust)
        let tint = color(for: r, risk: crosswind.overallRisk)
        // Real readout only — the integer of the raw gust, never invented.
        let gustText = "Max gust \(Int(gust.rounded())) mph"
        let riskText: String? = {
            let raw = (crosswind.overallRisk ?? "").lowercased()
            guard !raw.isEmpty, raw != "unknown" else { return nil }
            return "corridor \(raw.uppercased())"
        }()
        return HStack(spacing: 8) {
            // Leading rule reads as a track-side restriction marker.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(tint)
                .frame(width: 3)
            WeatherIcons.utility(.wind, size: 15, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label(for: r))
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(tint)
                Text(riskText.map { "\(gustText) · \($0)" } ?? gustText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label(for: r)). \(gustText).\(riskText.map { " " + $0 + "." } ?? "")")
    }
}

// MARK: - Consist car strip (assigned + hazmat indicators)
//
// A horizontal strip of car tiles that reads as the consist being built. The
// strip is bound to the real data model: `assigned` of `total` cars are
// coupled (the real build/load fraction assigned/total), and the trailing
// `hazmat` cars carry the IMDG/hazmat tint.
//
// UNKNOWN IS ITS OWN STATE. `total`, `assigned` and `hazmat` are all optional
// and arrive nil whenever the server did not report them, which is the case
// for `assigned`/`hazmat` today (see the decoder's root-cause note). A nil is
// never coalesced here:
//  • hazmat nil  → NO car may paint Brand.success. Green on this strip asserts
//    "coupled and free of hazardous material"; with no count that assertion is
//    unsupported, so coupled cars paint neutral ink and the card prints the
//    missing-input line. A hazmat consist can therefore never render clean.
//  • assigned nil → no car is drawn as coupled and the empty slots take the
//    warning stroke, so the strip reads "makeup unknown" rather than "0 of 48".
//  • total nil    → the strip draws no tiles at all.
//
// Motion:
//  • Build sequence — on appear/change, the assigned cars settle in
//    left-to-right with a short per-car stagger and a decelerating spring
//    (transform/opacity only), so the row reads as cars being coupled onto
//    the consist up to the true assigned count. Unassigned slots stay as
//    dashed-empty couplers and never animate in.
//  • Hazmat attention — the hazmat cars carry a seamless ambient breathing
//    glow (autoreversing easeInOut, start == end) signalling a live safety
//    indicator. The build itself is never an indefinite loop.
//  • Reduce Motion — snaps straight to the final state: all assigned cars
//    shown at full presence, no stagger, no hazmat pulse.
private struct ConsistCarStrip555: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real values from the data model. `nil` means the server did not report
    /// the count — it is NEVER coalesced to 0 or to `total`, because either
    /// coalesce is read off this strip as a measurement.
    let total: Int?
    let assigned: Int?
    let hazmat: Int?
    /// Tint for empty / unassigned coupler slots.
    let trackTint: Color

    /// How many assigned cars have settled in. Starts at 0 so the consist
    /// "builds up" to its true assigned count on appear.
    @State private var built: Int = 0
    /// Drives the seamless hazmat breathing loop.
    @State private var pulsing = false

    /// Hazmat is only ever asserted off a REAL reported count.
    private var hasHazmat: Bool { (hazmat ?? 0) > 0 && (total ?? 0) > 0 }
    private var pulse: Bool { hasHazmat && !reduceMotion }
    /// GREEN on a car means "coupled AND reported free of hazardous material".
    /// With no hazmat count in the payload that claim cannot be made, so the
    /// green paint is withheld from every car until the count is reported.
    private var hazmatReported: Bool { hazmat != nil }

    /// The strip is pure colour, so VoiceOver gets the same three states in words.
    private var stripVoice: String {
        guard let total else { return "Car count not reported." }
        let coupled = assigned.map { "\($0) of \(total) cars coupled" }
            ?? "\(total) cars, coupled makeup not reported"
        let hazmatVoice = hazmat.map { $0 > 0 ? "\($0) hazmat cars" : "no hazmat cars reported" }
            ?? "hazmat count not reported"
        return "\(coupled). \(hazmatVoice)."
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total ?? 0, 0), id: \.self) { idx in
                car(idx)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consist car strip")
        .accessibilityValue(stripVoice)
        .onAppear { settle() }
        .onChange(of: assigned) { _, _ in settle() }
        .onChange(of: total) { _, _ in settle() }
        .onChange(of: hazmat) { _, _ in settle() }
    }

    @ViewBuilder
    private func car(_ idx: Int) -> some View {
        let isAssigned = assigned.map { idx < $0 } ?? false
        let isHazmat = hazmatReported && isAssigned && idx >= ((total ?? 0) - (hazmat ?? 0))
        let shown = idx < built          // has this assigned car settled in yet?
        // Three states, not two: coupled+clean (green) · coupled+hazmat
        // (warning) · coupled but hazmat UNREPORTED (neutral ink, never green).
        let fill: AnyShapeStyle = {
            guard isAssigned else { return AnyShapeStyle(Color.clear) }
            if isHazmat { return AnyShapeStyle(Brand.warning) }
            return hazmatReported ? AnyShapeStyle(Brand.success) : AnyShapeStyle(trackTint)
        }()
        // An unreported makeup must not read as "0 cars coupled", so its empty
        // slots carry the warning stroke rather than the plain track stroke.
        let strokeTint: Color = isAssigned
            ? Color.clear
            : (assigned == nil ? Brand.warning.opacity(0.55) : trackTint)

        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(strokeTint, lineWidth: 1.2)
            )
            .frame(width: 11, height: 14)
            // Hazmat live-safety glow — seamless autoreversing loop.
            .shadow(color: (isHazmat && pulse) ? Brand.warning.opacity(pulsing ? 0.65 : 0.0) : .clear,
                    radius: (isHazmat && pulse) ? (pulsing ? 4 : 0) : 0)
            // Build-in transform: assigned cars rise + scale into place.
            .scaleEffect(isAssigned ? (shown ? 1.0 : 0.4) : 1.0, anchor: .bottom)
            .opacity(isAssigned ? (shown ? 1.0 : 0.0) : 1.0)
    }

    private func settle() {
        // An unreported makeup animates nothing — there is no true count to
        // build up to, and a 0-length build is not a claim that 0 are coupled.
        let target = max(assigned ?? 0, 0)
        if reduceMotion {
            built = target
            pulsing = false
            return
        }
        // Re-run the build from empty so a data change re-couples cleanly.
        built = 0
        for i in 0..<target {
            // Decelerating spring, staggered left-to-right (cap stagger so very
            // long consists still finish promptly — UI beat stays < 600ms tail).
            let delay = Double(i) * min(0.045, 0.4 / Double(max(target, 1)))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(delay)) {
                built = i + 1
            }
        }
        // Ambient hazmat pulse: continuous, seamless (start == end).
        if hasHazmat {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            pulsing = false
        }
    }
}

#Preview("555 · Rail Consist Board · Night") { RailConsistBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("555 · Rail Consist Board · Light") { RailConsistBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
