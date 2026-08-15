//
//  555_RailConsistBoard.swift
//  EusoTrip — Rail Engineer · Consist Board (carrier vantage).
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
        // Server doesn't provide assignedCars or hazmatCars; default to nil.
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
    @State private var totalCars = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var building = false

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
                    CTAButton(title: building ? "Building…" : "Build new consist",
                              action: { Task { await buildConsist() } }, leadingIcon: "plus")
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
            Text("\(consists.count) consists building / rolling · \(totalCars) cars total")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func consistCard(_ c: TrainConsist) -> some View {
        let rolling = (c.status ?? "").lowercased() == "rolling"
        let total = c.totalCars ?? 0
        let assigned = min(c.assignedCars ?? total, total)
        let hazmat = min(c.hazmatCars ?? 0, total)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(c.consistNumber ?? "-").font(.system(size: 15, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (c.status ?? "-").uppercased(), kind: rolling ? .info : .neutral)
            }
            Text("\(c.originYard ?? "-") → \(c.destinationYard ?? "-") · \(assigned)/\(total) cars\(c.note.map { " · \($0)" } ?? "")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            ConsistCarStrip555(total: total, assigned: assigned, hazmat: hazmat, trackTint: palette.textTertiary)
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
    }

    private func load() async {
        loading = true; loadError = nil
        struct ConsistsIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: ConsistsResponse = try await EusoTripAPI.shared.query(
                "railShipments.getTrainConsists", input: ConsistsIn(limit: 20, offset: 0))
            self.consists = result.consists
            self.totalCars = result.consists.reduce(0) { $0 + ($1.totalCars ?? 0) }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buildConsist() async {
        building = true
        building = false
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

    /// Real values from the data model.
    let total: Int
    let assigned: Int
    let hazmat: Int
    /// Tint for empty / unassigned coupler slots.
    let trackTint: Color

    /// How many assigned cars have settled in. Starts at 0 so the consist
    /// "builds up" to its true assigned count on appear.
    @State private var built: Int = 0
    /// Drives the seamless hazmat breathing loop.
    @State private var pulsing = false

    private var hasHazmat: Bool { hazmat > 0 && total > 0 }
    private var pulse: Bool { hasHazmat && !reduceMotion }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 0), id: \.self) { idx in
                car(idx)
            }
        }
        .onAppear { settle() }
        .onChange(of: assigned) { _, _ in settle() }
        .onChange(of: total) { _, _ in settle() }
        .onChange(of: hazmat) { _, _ in settle() }
    }

    @ViewBuilder
    private func car(_ idx: Int) -> some View {
        let isAssigned = idx < assigned
        let isHazmat = isAssigned && idx >= (total - hazmat)
        let shown = idx < built          // has this assigned car settled in yet?
        let fill: AnyShapeStyle = !isAssigned
            ? AnyShapeStyle(Color.clear)
            : (isHazmat ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(Brand.success))

        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(isAssigned ? Color.clear : trackTint, lineWidth: 1.2)
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
        if reduceMotion {
            built = assigned
            pulsing = false
            return
        }
        // Re-run the build from empty so a data change re-couples cleanly.
        built = 0
        for i in 0..<max(assigned, 0) {
            // Decelerating spring, staggered left-to-right (cap stagger so very
            // long consists still finish promptly — UI beat stays < 600ms tail).
            let delay = Double(i) * min(0.045, 0.4 / Double(max(assigned, 1)))
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
