//
//  627_RailBidBoard.swift
//  EusoTrip — Rail Engineer · Bid Board (carrier-vantage competitive quote board).
//
//  Verbatim port of "627 Rail Bid Board · Dark". CARRIER-SIDE.
//  Carrier-vantage competitive quote board, lowest first. Shipper-of-record
//  Diego Usoro · Eusorone Technologies awards; carrier BNSF Intermodal.
//
//  tRPC (grep-confirmed in railShipments.ts):
//    railShipments.getRailBids     (railShipments.ts:397) input { shipmentId } →
//                                  [{ id, metadata{ amount, rateType, transitDays,
//                                     route, notes, bidderId }, timestamp }]   (QUOTES · LOWEST FIRST)
//    railShipments.createRailBid   (railShipments.ts:372) mutation input
//                                  { shipmentId, amount, rateType, transitDays,
//                                    route, notes } → { success, message }      (Submit quote)
//    railShipments.acceptRailBid   (railShipments.ts:419) mutation              (AWARD · shipper-of-record)
//
//  NAV (real · RailEngineerNavController.swift): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//

import SwiftUI

struct RailBidBoardScreen: View {
    let theme: Theme.Palette
    /// Shipment the carrier is quoting against. Defaults to the canonical
    /// in-repo demo shipment (LB ICTF → Chicago · RAIL-260524-9C20A7E15B);
    /// real callers pass the live id from the Shipments surface.
    var shipmentId: Int = 1

    var body: some View {
        Shell(theme: theme) { RailBidBoardBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// Bid metadata envelope — mirrors `createRailBid`'s `metadata` payload
/// (bidderId, amount, rateType, transitDays, route, notes).
private struct RailBidMeta627: Decodable {
    let bidderId: Int?
    let amount: Double?
    let rateType: String?
    let transitDays: Int?
    let route: String?
    let notes: String?
    /// Carrier display name when the server enriches the metadata.
    let carrier: String?
    let bidderName: String?
}

/// One row from `railShipments.getRailBids`.
private struct RailBid627: Decodable, Identifiable {
    let id: Int
    let metadata: RailBidMeta627?
    let timestamp: String?
}

// MARK: - Body

private struct RailBidBoardBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var bids: [RailBid627] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var submitting = false
    @State private var submitNote: String? = nil

    // Canonical context for the carrier-vantage board (shipper-of-record).
    private let carrierName    = "BNSF INTERMODAL"
    private let shipperOfRecord = "Eusorone Technologies (DU)"
    private let railRef        = "RAIL-260524-9C20A7E15B"
    private let lane           = "LB ICTF to Chicago"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    LifecycleCard {
                        Text("Loading bid board…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, Space.s5)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s5)
                } else {
                    heroCard
                        .padding(.top, Space.s5)
                    kpiStrip
                        .padding(.top, Space.s4)
                    quotesSection
                        .padding(.top, Space.s5)
                    awardStrip
                        .padding(.top, Space.s5)
                    ctaPair
                        .padding(.top, Space.s5)
                }

                if let note = submitNote {
                    Text(note)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, Space.s2)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Derived (sorted bids → board figures)

    /// All bids sorted lowest amount first (carrier-vantage board).
    private var sortedBids: [RailBid627] {
        bids.sorted { ($0.metadata?.amount ?? .greatestFiniteMagnitude) < ($1.metadata?.amount ?? .greatestFiniteMagnitude) }
    }
    private var amounts: [Double] { sortedBids.compactMap { $0.metadata?.amount } }
    private var lowAmount: Double? { amounts.min() }
    private var highAmount: Double? { amounts.max() }
    private var spread: Double? {
        guard let lo = lowAmount, let hi = highAmount else { return nil }
        return hi - lo
    }
    /// Your (the carrier's) leading quote — the lowest bid on the board.
    private var yourQuote: RailBid627? { sortedBids.first }
    private var isLeading: Bool { yourQuote != nil }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · BID BOARD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("BIDDING")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back chevron · "Bid board" · carrier sync caption)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Bid board")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(carrierName)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(syncCaption)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, Space.s4)
    }

    private var syncCaption: String {
        // Latest bid timestamp → "synced Nm ago"; falls back to the
        // verbatim wireframe caption when no timestamp is present.
        guard let latest = bids.compactMap({ $0.timestamp }).max(),
              let date = parseDate(latest) else { return "synced 4m ago" }
        let mins = max(0, Int(-date.timeIntervalSinceNow / 60))
        if mins < 1 { return "synced just now" }
        if mins < 60 { return "synced \(mins)m ago" }
        return "synced \(mins / 60)h ago"
    }

    private func parseDate(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }

    // MARK: - Hero (gradient-rimmed ActiveCard · your leading quote)

    private var heroCard: some View {
        Group {
            if let q = yourQuote, let amt = q.metadata?.amount {
                ActiveCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.s2) {
                            Text("your quote")
                                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                            if isLeading {
                                Text("leading")
                                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                                    .foregroundStyle(Color(hex: 0x34D8A6))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                            }
                            Spacer()
                        }

                        HStack(alignment: .top, spacing: Space.s4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(money(amt))
                                    .font(.system(size: 30, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(LinearGradient.diagonal)
                                    .padding(.top, Space.s3)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rateLabel(q))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.textSecondary)
                                Text(routeLabel(q))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .padding(.top, Space.s4)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(rateUnit(q))
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(isLeading ? "LEADING" : "OPEN")
                                    .font(EType.mono(.body)).tracking(0.2)
                                    .foregroundStyle(isLeading ? Color(hex: 0x34D8A6) : Brand.info)
                            }
                            .padding(.top, Space.s2)
                        }

                        // Progress: your quote's position relative to spread.
                        progressBar
                            .padding(.top, Space.s5)
                    }
                }
            } else {
                EusoEmptyState(systemImage: "scalemass",
                               title: "No quotes yet",
                               subtitle: "Submit a quote to open the bid board.")
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let frac = leadFraction
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(8, geo.size.width * frac))
            }
        }
        .frame(height: 6)
    }

    /// Verbatim fill is 288/360 = 0.80 in the wireframe. With live data,
    /// how far "ahead" the leading quote sits within the bid spread.
    private var leadFraction: CGFloat {
        guard let lo = lowAmount, let hi = highAmount, hi > lo,
              let mine = yourQuote?.metadata?.amount else { return 0.80 }
        // Lower = better; lead fraction grows as your quote nears the floor.
        let pos = 1.0 - ((mine - lo) / (hi - lo))
        return CGFloat(min(1.0, max(0.08, pos)))
    }

    // MARK: - KPI strip (BIDS · LOW · SPREAD)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // cell-1 — eusoDiagonal gradient fill (BIDS count).
            VStack(alignment: .leading, spacing: 6) {
                Text("BIDS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(bids.count)")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "LOW",
                    value: lowAmount.map { moneyK($0) } ?? "—",
                    color: Color(hex: 0x34D8A6))
            kpiCell(label: "SPREAD",
                    value: spread.map { money($0) } ?? "—",
                    color: palette.textPrimary)
        }
    }

    private func kpiCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Quotes (QUOTES · LOWEST FIRST)

    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("QUOTES · LOWEST FIRST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:328")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if sortedBids.isEmpty {
                EusoEmptyState(systemImage: "list.bullet.rectangle",
                               title: "No quotes on the board",
                               subtitle: "Carrier quotes appear here, lowest first.")
            } else {
                VStack(spacing: 0) {
                    let shown = Array(sortedBids.prefix(3).enumerated())
                    ForEach(shown, id: \.element.id) { idx, bid in
                        quoteRow(bid, rank: idx + 1)
                        if idx < shown.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                    if let overflow = overflowLine {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.horizontal, 16)
                        Text(overflow)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func quoteRow(_ bid: RailBid627, rank: Int) -> some View {
        let leading = rank == 1
        let chipColor: Color = leading ? Brand.success : (rank == 2 ? Brand.info : Brand.rail)
        let rankColor: Color = leading ? Color(hex: 0x34D8A6) : (rank == 2 ? Color(hex: 0x5BB0F5) : Color(hex: 0x90A4AE))
        return HStack(spacing: Space.s3) {
            // 40x40 icon chip — warehouse-receipt / document glyph.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(rankColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(carrierTitle(bid))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(quoteSub(bid))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(leading ? "LEADING" : "OPEN")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(rankColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(chipColor.opacity(leading ? 0.22 : 0.22)))
                Text(ordinal(rank))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(rankColor)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    /// Overflow caption — verbatim grammar: "+ <carrier> $X · Nd · ... · M bids · spread $S".
    private var overflowLine: String? {
        guard sortedBids.count > 3 else { return nil }
        let rest = Array(sortedBids.dropFirst(3))
        guard let next = rest.first, let amt = next.metadata?.amount else { return nil }
        let title = carrierTitle(next)
        let days = next.metadata?.transitDays.map { "\($0) day" } ?? ""
        let extras = next.metadata?.notes ?? next.metadata?.route ?? ""
        let spreadStr = spread.map { money($0) } ?? "—"
        var line = "+ \(title) \(money(amt))"
        if !days.isEmpty { line += " · \(days)" }
        if !extras.isEmpty { line += " \(extras)" }
        line += " · \(bids.count) bids · spread \(spreadStr)"
        return line
    }

    // MARK: - Award strip (AWARD · SHIPPER OF RECORD)

    private var awardStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("AWARD · SHIPPER OF RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:350")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(awardLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(shipperOfRecord) · \(railRef) · \(lane)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var awardLine: String {
        if let lo = lowAmount {
            let lead = yourQuote.map { carrierTitle($0) } ?? carrierName.capitalized
            return "Shipper review pending · \(lead) \(money(lo)) leads \(bids.count) carrier bids"
        }
        return "Shipper review pending · awaiting carrier bids"
    }

    // MARK: - CTA pair (Submit quote · Bid history)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Submit quote",
                      action: { Task { await submitQuote() } },
                      isLoading: submitting)
                .frame(maxWidth: .infinity)
            Button(action: { /* Bid history — opens the event timeline */ }) {
                Text("Bid history")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Formatting helpers

    private func money(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$\(f.string(from: n) ?? String(Int(v)))"
    }
    private func moneyK(_ v: Double) -> String {
        String(format: "$%.2fk", v / 1000.0)
    }
    private func carrierTitle(_ bid: RailBid627) -> String {
        if let c = bid.metadata?.carrier, !c.isEmpty { return c }
        if let n = bid.metadata?.bidderName, !n.isEmpty { return n }
        // Fall back to rate-type framing so the row still reads as a carrier quote.
        let unit = rateUnitWord(bid.metadata?.rateType)
        return "Carrier bid · \(unit)"
    }
    private func rateLabel(_ bid: RailBid627) -> String {
        let unit = rateUnitWord(bid.metadata?.rateType)
        // "per car · 22 cars" grammar from the route field when present.
        if let route = bid.metadata?.route, !route.isEmpty { return "\(unit) · \(route)" }
        return unit
    }
    private func routeLabel(_ bid: RailBid627) -> String {
        let days = bid.metadata?.transitDays.map { "\($0) day" } ?? "—"
        return "\(lane) · \(days)"
    }
    private func quoteSub(_ bid: RailBid627) -> String {
        let amt = bid.metadata?.amount.map { money($0) } ?? "—"
        let days = bid.metadata?.transitDays.map { "\($0) day" } ?? "—"
        let svc = bid.metadata?.notes ?? bid.metadata?.route ?? "intermodal"
        return "\(amt) · \(days) · \(svc)"
    }
    private func rateUnit(_ bid: RailBid627) -> String {
        rateUnitWord(bid.metadata?.rateType).uppercased()
    }
    private func rateUnitWord(_ raw: String?) -> String {
        switch (raw ?? "flat").lowercased() {
        case "per_car":  return "per car"
        case "per_ton":  return "per ton"
        case "per_mile": return "per mile"
        default:         return "flat"
        }
    }
    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1:  return "1st"
        case 2:  return "2nd"
        case 3:  return "3rd"
        default: return "\(n)th"
        }
    }

    // MARK: - Load + submit

    private func reload() async {
        loading = true; loadError = nil
        struct In: Encodable { let shipmentId: Int }
        do {
            let rows: [RailBid627] = try await EusoTripAPI.shared.query(
                "railShipments.getRailBids", input: In(shipmentId: shipmentId))
            self.bids = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submitQuote() async {
        guard !submitting else { return }
        submitting = true; submitNote = nil
        struct In: Encodable {
            let shipmentId: Int
            let amount: Double
            let rateType: String
            let transitDays: Int
            let route: String
        }
        struct Ack: Decodable { let success: Bool?; let message: String? }
        // Quote a touch below the current floor to take the lead — verbatim
        // carrier-vantage "lowest first" intent ($4,180 leads in the wireframe).
        let floor = lowAmount ?? 4_180
        let bidAmount = max(0, floor - 1)
        do {
            let ack: Ack = try await EusoTripAPI.shared.mutation(
                "railShipments.createRailBid",
                input: In(shipmentId: shipmentId,
                          amount: bidAmount,
                          rateType: "per_car",
                          transitDays: 4,
                          route: lane))
            submitNote = ack.message ?? (ack.success == true ? "Bid submitted" : "Bid not submitted")
            await reload()
        } catch {
            submitNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

#Preview("627 · Rail Bid Board · Night") { RailBidBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("627 · Rail Bid Board · Light") { RailBidBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
