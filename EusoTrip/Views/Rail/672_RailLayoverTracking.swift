//
//  672_RailLayoverTracking.swift
//  EusoTrip — Rail Engineer · Layover Tracking (carrier-side accessorial · time-aging / money-posture).
//
//  Bespoke port of "05 Rail/Code/672_RailLayoverTracking.swift" (Light + Dark) into app convention.
//  Signature device: each layover event is a forward-AGING time-track — arrival node ->
//  neutral free-time segment -> amber→red HEAT overage -> NOW/BILLED end marker; bar length =
//  days held so the worst offender is the longest bar. A fault chip (SHPR/RCVR/CARRIER/CONTESTED)
//  attributes blame; a status word states recovery posture. Hero is numbers-first: total
//  accruing over a status-posture split bar (secured / ready-to-bill / at-risk).
//  Nav anchored to rail Engineer chrome (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data:
//    detentionAccessorials.getLayoverTracking (EXISTS detentionAccessorials.ts:970, protectedProcedure,
//      companyId-scoped) — input {dateFrom?, dateTo?, limit=25}? →
//      { layovers[{id,loadId,facilityName,startDate,endDate,days,dailyRate=350,totalCharge,status,
//                  reason,carrierName,shipperName}],
//        summary{total,totalCharges,avgDays} }
//
//  STUB · named-gap (to the-oath):
//    (1) no structured fault-party field — fault chip derived client-side from free-text `reason`.
//    (2) no per-event freeDays returned — free-time segment rendered as a fixed 1-day proxy.
//    (3) 'Bill open' CTA -> detentionAccessorials.fileClaim (bill mutation) NOT wired in this surface.
//    (4) 'Dispute' CTA -> dispute mutation (audit + WS accessorial channel) NOT wired yet.
//    Both write CTAs are inert posture controls here; flag STUB until mutation + reload() are wired.
//

import SwiftUI

// MARK: - Wrapper (Shell + rail nav · SHIPMENTS inked)

struct RailLayoverTrackingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailLayoverTrackingBody672() } nav: {
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

// MARK: - Endpoint input + wire shapes

private struct LayoverInput672: Encodable {
    var limit: Int = 25
}

private struct LayoverResp672: Decodable {
    let layovers: [LayoverRow672]
    let summary: LayoverSummary672
}

private struct LayoverRow672: Decodable, Identifiable {
    let id: Int
    let facilityName: String?
    let days: Int?
    let totalCharge: Double?
    let dailyRate: Double?
    let status: String?
    let reason: String?
    let carrierName: String?
    let shipperName: String?
}

private struct LayoverSummary672: Decodable {
    let total: Int?
    let totalCharges: Double?
    let avgDays: Double?
}

// MARK: - View model (status / fault posture)

private enum LayoverStatus672 { case billed, open, disputed
    var word: String { switch self { case .billed: "BILLED"; case .open: "OPEN"; case .disputed: "DISPUTED" } }
    var tint: Color { switch self {
        case .billed:   Color(red: 0.094, green: 0.541, blue: 0.388)   // success
        case .open:     Color(red: 0.710, green: 0.392, blue: 0.102)   // warning
        case .disputed: Color(red: 0.776, green: 0.157, blue: 0.157) } // danger
    }
    static func from(_ raw: String?) -> LayoverStatus672 {
        switch (raw ?? "").lowercased() {
        case "paid", "billed", "invoiced":               return .billed
        case "disputed", "contested", "rejected":        return .disputed
        default:                                          return .open
        }
    }
}

// Fault is derived client-side from free-text `reason` (STUB · no structured faultParty field).
private enum LayoverFault672 { case shpr, rcvr, carrier, contested
    var label: String { switch self { case .shpr: "SHPR"; case .rcvr: "RCVR"; case .carrier: "CARRIER"; case .contested: "CONTESTED" } }
    var tint: Color { switch self {
        case .shpr:      Color(red: 0.082, green: 0.396, blue: 0.753)  // info
        case .rcvr:      Color(red: 0.710, green: 0.392, blue: 0.102)  // warning
        case .carrier:   Color(red: 0.376, green: 0.490, blue: 0.545)  // rail slate
        case .contested: Color(red: 0.776, green: 0.157, blue: 0.157) } // danger
    }
    static func from(reason: String?, status: LayoverStatus672) -> LayoverFault672 {
        let r = (reason ?? "").lowercased()
        if status == .disputed || r.contains("dispute") || r.contains("contest") { return .contested }
        if r.contains("shipper") || r.contains("load")  { return .shpr }
        if r.contains("receiver") || r.contains("consignee") || r.contains("no-show") || r.contains("no show") { return .rcvr }
        if r.contains("carrier") || r.contains("power") || r.contains("reposition") || r.contains("rail") { return .carrier }
        return .carrier
    }
}

private struct LayoverEvent672: Identifiable {
    let id: Int
    let facility: String
    let mark: String
    let reason: String
    let days: Int
    let charge: String
    let status: LayoverStatus672
    let fault: LayoverFault672

    init(row: LayoverRow672) {
        self.id = row.id
        self.facility = row.facilityName ?? "-"
        self.days = max(0, row.days ?? 0)
        let status = LayoverStatus672.from(row.status)
        self.status = status
        self.fault = LayoverFault672.from(reason: row.reason, status: status)
        self.reason = (row.reason?.isEmpty == false ? row.reason! : "shipper/receiver delay")
        self.charge = Self.usd(row.totalCharge ?? Double(self.days) * (row.dailyRate ?? 350))
        self.mark = "Load #\(row.id)"
    }

    // Local-preview seed initializer.
    init(id: Int, facility: String, mark: String, reason: String, days: Int, charge: String, status: LayoverStatus672, fault: LayoverFault672) {
        self.id = id; self.facility = facility; self.mark = mark; self.reason = reason
        self.days = days; self.charge = charge; self.status = status; self.fault = fault
    }

    static func usd(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: n) ?? "0")
    }
}

// MARK: - Body

private struct RailLayoverTrackingBody672: View {
    @Environment(\.palette) private var palette

    @State private var events: [LayoverEvent672] = []
    @State private var summary: LayoverSummary672? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // posture gradients / tints (local — mirrors the canonical port stops)
    private let heat = LinearGradient(
        colors: [Color(red: 1.0, green: 0.718, blue: 0.302),
                 Color(red: 0.984, green: 0.549, blue: 0.0),
                 Color(red: 0.956, green: 0.263, blue: 0.212)],
        startPoint: .leading, endPoint: .trailing)
    private let secured = Color(red: 0.0, green: 0.698, blue: 0.478)
    private let ready   = Color(red: 1.0, green: 0.655, blue: 0.149)
    private let atRisk  = Color(red: 0.937, green: 0.325, blue: 0.314)

    // Derived posture splits (honest — bound to live status buckets).
    private var totalAccruing: Double {
        events.reduce(0) { $0 + chargeValue($1.charge) }
    }
    private var securedAmt: Double { events.filter { $0.status == .billed }.reduce(0) { $0 + chargeValue($1.charge) } }
    private var readyAmt: Double   { events.filter { $0.status == .open    }.reduce(0) { $0 + chargeValue($1.charge) } }
    private var atRiskAmt: Double  { events.filter { $0.status == .disputed }.reduce(0) { $0 + chargeValue($1.charge) } }
    private var idleCars: Int      { events.reduce(0) { $0 + $1.days } }

    private func chargeValue(_ s: String) -> Double {
        Double(s.filter { $0.isNumber }) ?? 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                if loading {
                    LifecycleCard { Text("Loading layover aging…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if events.isEmpty {
                    EusoEmptyState(systemImage: "clock.badge.checkmark",
                                   title: "No open layovers",
                                   subtitle: "No layover accessorials are aging on this corridor.")
                } else {
                    hero
                    agingLane
                    esangRow
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: TopBar
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · ACCESSORIAL")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("LAYOVER").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Layover aging").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BNSF INTERMODAL").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    Text("$350 / car-day").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    // MARK: Hero — numbers-first + status-posture split bar
    private var hero: some View {
        let eventsCount = summary?.total ?? events.count
        let avg = summary?.avgDays ?? 0
        let total = summary?.totalCharges ?? totalAccruing
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCRUING ACROSS \(idleCars) IDLE CAR-DAYS").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textSecondary)
                    Text(LayoverEvent672.usd(total)).font(.system(size: 34, weight: .bold)).kerning(-0.6).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(eventsCount) events · 90-day").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text(String(format: "avg %.1f days held", avg)).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }.padding(.top, 14)
            }
            postureBar(total: total)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func postureBar(total: Double) -> some View {
        let denom = max(total, securedAmt + readyAmt + atRiskAmt, 1)
        let fSecured = securedAmt / denom
        let fReady   = readyAmt / denom
        return VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    Capsule().fill(secured).frame(width: max(0, w * fSecured))
                    Rectangle().fill(ready).frame(width: max(0, w * fReady))
                    Capsule().fill(atRisk)
                }
            }.frame(height: 10)
            HStack(spacing: 0) {
                legendDot(secured, LayoverEvent672.usd(securedAmt), "secured");  Spacer()
                legendDot(ready,   LayoverEvent672.usd(readyAmt),   "ready to bill"); Spacer()
                legendDot(atRisk,  LayoverEvent672.usd(atRiskAmt),  "at risk")
            }
        }
    }

    private func legendDot(_ c: Color, _ amt: String, _ cap: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(amt).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(cap).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Aging lane (the signature)
    private var agingLane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LAYOVER AGING · WORST FIRST").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textSecondary)
                Spacer()
                Text("showing \(events.count) of \(summary?.total ?? events.count)").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(sortedEvents.enumerated()), id: \.element.id) { idx, e in
                    eventRow(e)
                    if idx < sortedEvents.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderFaint))
        }
    }

    private var sortedEvents: [LayoverEvent672] { events.sorted { $0.days > $1.days } }

    private func eventRow(_ e: LayoverEvent672) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(e.fault.label).font(.system(size: 10, weight: .heavy)).kerning(0.4).foregroundStyle(e.fault.tint)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(e.fault.tint.opacity(0.16)))
                Text(e.facility).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(e.charge).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(e.status.word).font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(e.status.tint)
                }
            }
            Text("\(e.mark) · \(e.days) days held · \(e.reason)").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            agingTrack(days: e.days, billed: e.status == .billed, endTint: e.status.tint)
        }
        .padding(16)
    }

    // forward-aging track: arrival node -> free segment -> heat overage -> end marker
    private func agingTrack(days: Int, billed: Bool, endTint: Color) -> some View {
        let dayW: CGFloat = 56
        let span = max(1, days)
        return HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.05)).frame(width: dayW * CGFloat(span), height: 9)
                Capsule().fill(palette.textPrimary.opacity(0.13)).frame(width: dayW, height: 9)               // free-time (1-day proxy · STUB)
                Capsule().fill(heat).frame(width: dayW * CGFloat(max(0, span - 1)), height: 9).offset(x: dayW) // overage
                Circle().fill(palette.textSecondary).frame(width: 8, height: 8)                                // arrival node
                Rectangle().fill(palette.textSecondary).frame(width: 1, height: 15).offset(x: dayW)            // free-time divider
            }
            ZStack {
                Circle().fill(endTint.opacity(0.18)).frame(width: 16, height: 16)
                Circle().fill(endTint).frame(width: 9, height: 9)
            }
            Text(billed ? "BILLED" : "NOW").font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textSecondary)
            Spacer()
        }
    }

    // MARK: ESang — calm expert
    private var esangRow: some View {
        let lead = sortedEvents.first
        return HStack(spacing: 14) {
            OrbeSang(state: .idle, diameter: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.diagonal)
                if let lead, lead.status == .disputed {
                    Text("File the \(lead.facility) dispute now.").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(lead.charge) leaves BNSF\u{2019}s rebill window soon.").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                } else if let lead {
                    Text("\(lead.facility) is your worst offender.").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(lead.days) days held · \(lead.charge) accruing.").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                } else {
                    Text("No layover aging to escalate.").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text("Corridor is clear of open accessorials.").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    // MARK: CTA pair — both inert posture controls in this surface (STUB · no mutation wired)
    private var ctaRow: some View {
        HStack(spacing: 8) {
            // STUB: 'Bill open' → detentionAccessorials.fileClaim — not wired here; reload() on success.
            Button { } label: {
                Text("Bill open · \(LayoverEvent672.usd(readyAmt))").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            // STUB: 'Dispute' → dispute mutation (audit + WS accessorial) — not wired yet.
            Button { } label: {
                Text("Dispute").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load
    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: LayoverResp672 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getLayoverTracking", input: LayoverInput672())
            self.events = resp.layovers.map(LayoverEvent672.init(row:))
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Preview seed (lives ONLY here)

private extension RailLayoverTrackingBody672 {
    static var previewSeed: [LayoverEvent672] {
        [
            .init(id: 238104, facility: "Logistics Park IL", mark: "BNSF 238104", reason: "contract dispute",    days: 4, charge: "$1,400", status: .disputed, fault: .contested),
            .init(id: 221904, facility: "Cicero Ramp IL",    mark: "EMHU 221904", reason: "shipper load delay",  days: 3, charge: "$1,050", status: .billed,   fault: .shpr),
            .init(id: 401755, facility: "Alliance TX",       mark: "BNSF 401755", reason: "receiver no-show",    days: 2, charge: "$700",   status: .open,     fault: .rcvr),
            .init(id: 81220,  facility: "Joliet IL",         mark: "TTPX 81220",  reason: "power reposition",    days: 2, charge: "$700",   status: .open,     fault: .carrier)
        ]
    }
}

#Preview("672 · Layover aging · Light") {
    RailLayoverTrackingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("672 · Layover aging · Night") {
    RailLayoverTrackingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
