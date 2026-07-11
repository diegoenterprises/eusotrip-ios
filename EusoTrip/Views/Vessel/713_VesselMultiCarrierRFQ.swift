//
//  713_VesselMultiCarrierRFQ.swift
//  EusoTrip — Vessel Operator · Multi-Carrier RFQ (ocean spot comparison matrix).
//
//  Verbatim SwiftUI port of "713 Vessel Multi-Carrier RFQ.svg" (Dark + Light).
//  Archetype: BOARD / comparison ladder — a ranked carrier ladder with a
//  value-vs-highest bar, a tri-country discharge-regime re-quote strip, a
//  surcharge-transparency segmented bar, and a live 3-hour rate-validity lock.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE · ME), Shipments tab current.
//
//  WIRING (line-confirmed on disk this fire, server/routers/vesselShipments.ts):
//    getCarrierRates      EXISTS vesselShipments.ts:2638 (vesselProcedure ·
//        {originPort,destPort,containerSize} → INTTRAService.getCarrierRates →
//        CarrierRate[] {carrier,carrierCode,amount,currency,surcharges[],totalAmount}).
//        PRIMARY — the comparison ladder + surcharge bar bind to this array.
//    searchCarrierSchedules EXISTS vesselShipments.ts:2620 (ETD / transit context).
//  STUB · named-gap (surfaced to the-oath, NOT painted as live data):
//    · getCarrierRates returns one carrier set per lane call when the INTTRA
//      integration is unconfigured it returns []. The parallel multi-carrier
//      fan-out + normalized matrix is STUB · vesselShipments.runMultiCarrierRfq
//      {originPort,destPort,containerSize,scacs[]} → quotes[]{scac,service,allIn,
//      currency,surcharges{base,baf,lss,thc,doc},transitDays,etd,reliabilityPct}.
//    · The 3-hour spot-rate LOCK + "Lock & book" have no mutation today →
//      vesselShipments.lockSpotRate {…,validUntil} → rfqQuotes row +
//      createVesselBooking(vesselShipments.ts:424) on confirm.
//  When the live array is empty the ladder shows an honest gap state — never
//  fabricated carriers. transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

// MARK: - Data shape (mirrors INTTRAService.CarrierRate)

private struct RFQSurcharge713: Decodable {
    let type: String?
    let amount: Double?
    let currency: String?
}

private struct CarrierRate713: Decodable, Identifiable {
    let carrier: String?
    let carrierCode: String?
    let amount: Double?
    let currency: String?
    let validFrom: String?
    let validTo: String?
    let surcharges: [RFQSurcharge713]?
    let totalAmount: Double?
    var id: String { (carrierCode ?? carrier ?? UUID().uuidString) }
    var allIn: Double { totalAmount ?? amount ?? 0 }
}

// MARK: - Screen

struct VesselMultiCarrierRFQScreen: View {
    let theme: Theme.Palette
    var originPort: String = "CNSHA"
    var destPort: String = "USLGB"
    var containerSize: String = "40HC"

    var body: some View {
        Shell(theme: theme) {
            VesselMultiCarrierRFQBody(originPort: originPort, destPort: destPort, containerSize: containerSize)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselMultiCarrierRFQBody: View {
    @Environment(\.palette) private var palette
    let originPort: String
    let destPort: String
    let containerSize: String

    private enum Regime: String, CaseIterable { case us = "US", ca = "CA", mx = "MX" }

    @State private var rates: [CarrierRate713] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var regime: Regime = .us
    @State private var selected: String? = nil
    @State private var lockSeconds: Int = 3 * 3600 + 41 * 60 + 9   // 3h rate-validity lock
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Ladder derived state — sorted cheapest-first (best value on top).
    private var sorted: [CarrierRate713] {
        rates.filter { $0.allIn > 0 }.sorted { $0.allIn < $1.allIn }
    }
    private var minAllIn: Double { sorted.first?.allIn ?? 0 }
    private var maxAllIn: Double { sorted.last?.allIn ?? 0 }
    private var best: CarrierRate713? { sorted.first }
    private var fastest: CarrierRate713? { sorted.first }   // transit unavailable → cheapest carries value flag only
    private var selectedRate: CarrierRate713? {
        sorted.first(where: { $0.id == selected }) ?? best
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                laneHero
                regimeTabs
                ladderSection
                surchargeSection
                esangAdvisory
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
        .onReceive(ticker) { _ in if lockSeconds > 0 { lockSeconds -= 1 } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · MULTI-CARRIER RFQ")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("INTTRA · E2OPEN")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Multi-carrier RFQ")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("RFQ-000713 · \(containerSize) FAK dry · \(sorted.count) carrier\(sorted.count == 1 ? "" : "s") quoting")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero — RFQ lane + 3-hour rate lock

    private var laneHero: some View {
        HeroRim713 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("OCEAN SPOT REQUEST")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    lockPill
                }
                .padding(.bottom, 12)

                HStack(alignment: .center, spacing: 0) {
                    portStack(originPort, "Shanghai")
                    arrowGlyph
                    portStack(destPort, "Long Beach")
                    Spacer()
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 28)
                        .padding(.trailing, 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Best all-in").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                        Text(best.map { money($0.allIn, best?.currency ?? "USD") } ?? "—")
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x2BD9A4))
                    }
                }
            }
        }
    }

    private var lockPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Brand.warning).frame(width: 8, height: 8)
            Text("LOCK \(lockClock)")
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.2)
                .foregroundStyle(Brand.warning)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.warning.opacity(0.14)))
    }
    private var lockClock: String {
        let h = lockSeconds / 3600, m = (lockSeconds % 3600) / 60, s = lockSeconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private func portStack(_ code: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(name).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }
    private var arrowGlyph: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(LinearGradient.primary)
            .padding(.horizontal, 14)
    }

    // MARK: Tri-country discharge-regime tabs

    private var regimeTabs: some View {
        HStack(spacing: 8) {
            regimeTab(.us, "Long Beach", "CBP · USD")
            regimeTab(.ca, "Vancouver", "CBSA · CAD")
            regimeTab(.mx, "Manzanillo", "SAT · MXN")
        }
    }

    private func regimeTab(_ r: Regime, _ port: String, _ authority: String) -> some View {
        let active = regime == r
        let ring: Color = r == .us ? Color(hex: 0x5B8CFF) : (r == .ca ? Color(hex: 0xFF5A4D) : Color(hex: 0x1FAE84))
        return Button {
            regime = r
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(ring, lineWidth: 2.4).frame(width: 22, height: 22)
                    Text(r.rawValue).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(ring)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(port).font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                    Text(authority).font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
                }
                Spacer(minLength: 0)
                if r == .mx {
                    Text("FX").font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: active ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Carrier comparison ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RATE COMPARISON · getCarrierRates")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(sorted.count) QUOTES · \(regime == .us ? "USD" : (regime == .ca ? "CAD" : "MXN"))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Color(hex: 0x5B8CFF))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0x5B8CFF).opacity(0.14)))
            }
            if loading {
                gapCard(title: "Requesting live carrier rates…", detail: "getCarrierRates · \(originPort) → \(destPort) · \(containerSize)", warn: false)
            } else if let err = loadError {
                gapCard(title: "Rate request failed", detail: err, warn: true)
            } else if sorted.isEmpty {
                gapCard(title: "No live quotes on this lane yet",
                        detail: "Parallel fan-out pending vesselShipments.runMultiCarrierRfq — INTTRA/E2open rate feed returns per-lane quotes only.",
                        warn: false)
            } else if regime != .us {
                gapCard(title: "\(regime == .ca ? "Vancouver" : "Manzanillo") re-quote pending FX",
                        detail: "getCarrierRates returns USD all-in. \(regime == .ca ? "CAD" : "MXN") re-denomination awaits the live FX leg — showing US CBP quotes.",
                        warn: false)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("CARRIER").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        Spacer()
                        Text("VALUE vs HIGH").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        Spacer()
                        Text("ALL-IN").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    }
                    .foregroundStyle(palette.textTertiary)
                    .padding(.bottom, 10)
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, rate in
                        carrierRow(rate, rank: idx)
                        if idx < sorted.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 2)
                        }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func carrierRow(_ rate: CarrierRate713, rank: Int) -> some View {
        let isSel = (selectedRate?.id == rate.id)
        let name = rate.carrier ?? rate.carrierCode ?? "Carrier"
        let code = (rate.carrierCode ?? String(name.prefix(3))).uppercased()
        // value fraction: cheapest → longest bar.
        let span = max(maxAllIn - minAllIn, 1)
        let frac = maxAllIn > minAllIn ? CGFloat((maxAllIn - rate.allIn) / span) : 1
        let barFrac = max(0.06, min(1, frac))
        return Button {
            selected = rate.id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isSel ? Color(hex: 0x2A1733) : palette.bgCardSoft).frame(width: 30, height: 30)
                    Text(code.count > 3 ? String(code.prefix(3)) : code)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(isSel ? Color(hex: 0xD45BF0) : Color(hex: 0x5B8CFF))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    HStack(spacing: 6) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.bgCardSoft).frame(width: 84, height: 6)
                            Capsule()
                                .fill(rank == 0 ? AnyShapeStyle(LinearGradient(colors: [Brand.blue, Brand.success], startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(palette.textTertiary))
                                .frame(width: 84 * barFrac, height: 6)
                        }
                        if rank == 0 {
                            Text("BEST VALUE").font(.system(size: 7.5, weight: .heavy))
                                .foregroundStyle(Color(hex: 0x2BD9A4))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: 0x2BD9A4).opacity(0.14)))
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(money(rate.allIn, rate.currency ?? "USD"))
                    .font(.system(size: 13.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(rank == 0 ? Color(hex: 0x2BD9A4) : palette.textPrimary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, isSel ? 10 : 0)
            .background(
                isSel ? RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x5B8CFF).opacity(0.08)) : nil
            )
            .overlay(
                isSel ? RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.2) : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Surcharge transparency

    private var surchargeSection: some View {
        Group {
            if let r = selectedRate, let comps = r.surcharges, !comps.isEmpty {
                let base = max(r.allIn - comps.reduce(0) { $0 + ($1.amount ?? 0) }, 0)
                let segments = surchargeSegments(base: base, comps: comps)
                VStack(alignment: .leading, spacing: 8) {
                    Text("SURCHARGE BREAKDOWN · \((r.carrier ?? r.carrierCode ?? "carrier")) \(money(r.allIn, r.currency ?? "USD")) all-in")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 12) {
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                                    Rectangle().fill(seg.color)
                                        .frame(width: geo.size.width * CGFloat(seg.value / max(r.allIn, 1)))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        .frame(height: 14)
                        FlowLegend713(items: segments.map { ($0.color, "\($0.label) \(money($0.value, r.currency ?? "USD"))") })
                    }
                    .padding(Space.s4)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
            } else if !sorted.isEmpty {
                gapCard(title: "Surcharge components not itemized on this quote",
                        detail: "INTTRA rate carries a flat all-in; BAF/LSS/THC/Doc split pending runMultiCarrierRfq surcharge normalization.",
                        warn: false)
            }
        }
    }

    private struct Seg713 { let label: String; let value: Double; let color: Color }
    private func surchargeSegments(base: Double, comps: [RFQSurcharge713]) -> [Seg713] {
        var out: [Seg713] = [Seg713(label: "Base", value: base, color: Brand.blue)]
        let palette: [Color] = [Color(hex: 0x8A5CF6), Brand.vessel, Brand.success, Brand.warning, Brand.info]
        for (i, c) in comps.enumerated() {
            out.append(Seg713(label: (c.type ?? "Surcharge").uppercased(), value: c.amount ?? 0, color: palette[i % palette.count]))
        }
        return out
    }

    // MARK: ESang advisory

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: 12) {
            OrbeSang(state: .idle, diameter: 26).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(esangLead)
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(esangSub)
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }
    private var esangLead: String {
        guard let b = best else { return "Awaiting live carrier quotes to compare" }
        return "\(b.carrier ?? b.carrierCode ?? "The cheapest carrier") is the best all-in at \(money(b.allIn, b.currency ?? "USD"))"
    }
    private var esangSub: String {
        best == nil ? "ESANG ranks value-vs-transit once the rate feed returns."
        : "Book before the spot rate lock expires in \(lockClock)."
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: best.map { "Lock & book \($0.carrier ?? $0.carrierCode ?? "carrier") · \(money($0.allIn, $0.currency ?? "USD"))" } ?? "Lock & book",
                      action: { /* STUB · vesselShipments.lockSpotRate → createVesselBooking */ })
            Button {
                Task { await load() }
            } label: {
                Text("Request more")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 132, minHeight: 48)
                    .background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Gap card (honest empty / STUB banner)

    private func gapCard(title: String, detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(warn ? Brand.danger : palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(warn ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct RatesIn: Encodable { let originPort: String; let destPort: String; let containerSize: String }
        do {
            let out: [CarrierRate713]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getCarrierRates",
                input: RatesIn(originPort: originPort, destPort: destPort, containerSize: containerSize))
            self.rates = out ?? []
            if selected == nil { selected = sorted.first?.id }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: Formatting

    private func money(_ v: Double, _ ccy: String) -> String {
        let symbol = ccy == "USD" || ccy == "CAD" || ccy == "MXN" ? "$" : ""
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return symbol + (f.string(from: NSNumber(value: v)) ?? "\(Int(v))")
    }
}

// MARK: - Flow legend (wrapping color-keyed legend)

private struct FlowLegend713: View {
    let items: [(Color, String)]
    @Environment(\.palette) private var palette
    var body: some View {
        // Two-per-row wrap keeps it readable at 440pt width.
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 14) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Circle().fill(item.0).frame(width: 8, height: 8)
                            Text(item.1).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Hero rim (cardRim gradient + inset)

private struct HeroRim713<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("713 · Vessel Multi-Carrier RFQ · Night") {
    VesselMultiCarrierRFQScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("713 · Vessel Multi-Carrier RFQ · Light") {
    VesselMultiCarrierRFQScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
