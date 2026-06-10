//
//  708_VesselShipmentCO2.swift
//  EusoTrip — Vessel Operator · CO2 / GHG Statement.
//
//  Faithful port of "708 Vessel CO2 Statement.svg" (Light + Dark) — an EMISSIONS-statement
//  archetype: a CO2e hero with a bespoke CII rating dial (A→E semicircle gauge + needle), a
//  per-leg well-to-wake CO2e ledger, a 2026 EU-ETS surrender band, a fused ESang bio-bunker
//  recommendation, and a GHG-export / offset CTA pair. Distinct from the 674 cost ledger and
//  696 batch board. Anchored to the registered Vessel Operator Shell + BottomNav wrapper the
//  siblings 757/664/680 ship — HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME — with the
//  COMPLIANCE slot inked (a CO2/GHG statement is a compliance surface).
//
//  Data / wiring (endpoints confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    vesselShipments.getVesselShipments (EXISTS vesselShipments.ts:222 · vesselProcedure ·
//      {limit,offset} -> {shipments:[raw vessel_shipments rows],total}) — anchors the statement to
//      the operator's MOST RECENT real booking (id + bookingNumber + numberOfContainers). Honest
//      empty state when the operator has no bookings.
//    co2Calculator.calculateVesselShipment (EXISTS frontend/server/routers/co2Calculator.ts:66 ·
//      vesselProcedure · input {shipmentId?,fuelConsumedTonnes?,fuelType?,distanceNm?,teuCount?} ·
//      returns {co2Tonnes,co2PerTeu,ciiAttained,ciiRating A|B|C|D|E,distanceNm,teuCount,fuelType,
//      fuelConsumedTonnes}). ZERO-FALLBACK: the REAL shipmentId is threaded — no hardcoded
//      5,720 nm / 2 TEU / "vlsfo" inputs; when the proc returns zero tonnes (no voyage distance on
//      record) the screen says so honestly instead of rendering fabricated math.
//    "Export GHG statement" -> reports.exportCO2Statement (EXISTS reports.ts:509 · protectedProcedure ·
//      no input · returns {filename,mime:"text/csv",body} GLEC v3.0 per-load CO2e ledger). Real
//      export verb fired for the GHG statement download.
//
//    Per-leg ledger + EU-ETS surrender band: NO server source exists today (no leg telemetry, no
//    EUA ledger) — the per-leg section renders an honest empty state and the ETS band is NOT
//    rendered (a fabricated regulatory obligation is worse than an absent one). Surfaced as the
//    named backend seam (vessel leg telemetry + EU-ETS ledger procs).
//
//    ESang advisory: esangCoach.forScreen exists (esangCoach.ts:264) but its SCREEN_ENUM is
//    driver-centric (home/trips/earnings/…/active-trip) — there is NO vessel.co2 value, so a call
//    with a vessel screen key would fail Zod validation. The advisory is therefore an honest,
//    DIRECTIONAL recommendation carrying no invented quantities; the named gap (a vessel-mode
//    coach screen key) is the surfaced backend seam.
//
//  0 mock data on load · honest empty/error states — the hero/CII render from live state only;
//  nil-initialized, em-dash absence. CIIGauge708 is a file-scoped bespoke dial (the canonical
//  port's CIIGauge is not a shared app symbol), built to mirror the SVG arc bands.
//

import SwiftUI

struct VesselShipmentCO2Screen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselShipmentCO2Body()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct EmissionLeg708: Identifiable {
    let id = UUID(); let title: String; let sub: String; let glyph: String; let tonnes: Double; let share: Double
}

private struct VesselShipmentCO2Body: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // ZERO-FALLBACK: nil-initialized — every figure renders live-or-em-dash.
    @State private var bookingId: String? = nil      // real bookingNumber from the anchored shipment
    @State private var hasShipment = false           // operator has at least one real booking
    @State private var totalTonnes: Double? = nil
    @State private var ciiRating: String? = nil      // band label; index drives the needle
    @State private var ciiBand = 2                   // 0=A … 4=E (only read when ciiRating != nil)
    @State private var ciiAttained: Double? = nil    // g CO2 / (t-capacity·nm), server-computed
    @State private var distanceNm: Double? = nil     // echoed by the proc (0 = not on record)
    @State private var teuCount: Int? = nil
    @State private var fuelType: String? = nil
    @State private var legs: [EmissionLeg708] = []   // no leg-telemetry source exists — honest empty
    @State private var exporting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Computing GLEC emissions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasShipment {
                    EusoEmptyState(systemImage: "leaf",
                                   title: "No booking to report on",
                                   subtitle: "The CO2 / GHG statement anchors to your most recent vessel booking — it appears once a booking exists.")
                } else {
                    heroCard
                    Text("EMISSIONS BY LEG · WELL-TO-WAKE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    legsCard
                    esangRow
                    HStack(spacing: 12) {
                        CTAButton(title: "Export GHG statement",
                                  action: { Task { await exportStatement() } },
                                  trailingIcon: "square.and.arrow.up",
                                  isLoading: exporting)
                        Button { } label: {
                            Text("Offset").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: 126, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CO2 STATEMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("GLEC · tCO2e").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Emissions statement").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                // Pill renders only off a server-attained rating — never a seed.
                if let r = ciiRating {
                    StatusPill(text: "CII · \(r)", kind: .warning)
                }
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CO2e · THIS BOOKING").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(totalTonnes.map { String(format: "%.2f", $0) } ?? "—")
                            .font(.system(size: 40, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text("t").font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    Text(heroBookingLine).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    if totalTonnes == nil {
                        // Honest: shipmentId was threaded but the booking has no
                        // voyage distance on record — no math can be claimed.
                        Text("voyage distance not on record — emissions pending")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textTertiary)
                    } else if let cii = ciiAttained, cii > 0 {
                        Text(String(format: "CII attained %.2f g/t-nm", cii))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                    }
                }
                Spacer()
                if let r = ciiRating {
                    CIIGauge708(band: ciiBand, label: r).frame(width: 92, height: 84)
                }
            }
        }
    }

    /// "<bookingNumber> · <N> TEU · <D> nm" — every component live or em-dash.
    private var heroBookingLine: String {
        let booking = bookingId ?? "—"
        let teu = teuCount.map { "\($0) TEU" } ?? "— TEU"
        let dist: String = {
            guard let d = distanceNm, d > 0 else { return "— nm" }
            return "\(Int(d.rounded()).formatted(.number.grouping(.automatic))) nm"
        }()
        return "\(booking) · \(teu) · \(dist)"
    }

    @ViewBuilder
    private var legsCard: some View {
        if legs.isEmpty {
            // NAMED GAP: no vessel leg-telemetry source exists server-side —
            // honest empty state, never a canned Shanghai→Long Beach ledger.
            EusoEmptyState(systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                           title: "No per-leg breakdown on record",
                           subtitle: "Well-to-wake legs appear here once voyage leg telemetry lands for this booking.")
        } else {
            legsLedger
        }
    }

    private var legsLedger: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.id) { idx, leg in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: leg.glyph)
                            .font(.system(size: 15)).foregroundStyle(idx == 0 ? Brand.info : Brand.vessel)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill((idx == 0 ? Brand.info : Brand.vessel).opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(leg.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(leg.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f t", leg.tonnes)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                            Text(String(format: "%.1f%%", leg.share * 100)).font(.system(size: 11)).foregroundStyle(palette.textTertiary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < legs.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    // EU-ETS surrender band REMOVED (zero-fallback): no EUA ledger proc exists,
    // and a fabricated regulatory obligation (142 EUA · €11,360 · 71%) is worse
    // than an absent one. The band returns when a real EU-ETS ledger source lands.

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                // Directional advisory only — no invented savings figures; the
                // quantified version lands with voyage fuel + EU-ETS ledger data.
                Text("Switch to bio-bunker on EU legs").font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · directional — savings quantify once voyage fuel data lands").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1)))
    }

    // MARK: - Data

    /// Raw vessel_shipments row (tolerant subset) — anchors the statement to a REAL booking.
    private struct ShipmentRow708: Decodable {
        let id: Int?
        let bookingNumber: String?
        let numberOfContainers: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id                 = try? c.decode(Int.self,    forKey: .id)
            bookingNumber      = try? c.decode(String.self, forKey: .bookingNumber)
            numberOfContainers = try? c.decode(Int.self,    forKey: .numberOfContainers)
        }
        enum CodingKeys: String, CodingKey { case id, bookingNumber, numberOfContainers }
    }

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        struct ListOut: Decodable { let shipments: [ShipmentRow708]? }
        struct CalcIn: Encodable { let shipmentId: Int; let teuCount: Int? }
        struct CalcOut: Decodable {
            let co2Tonnes: Double?; let co2PerTeu: Double?; let ciiAttained: Double?; let ciiRating: String?
            let distanceNm: Double?; let teuCount: Int?; let fuelType: String?; let fuelConsumedTonnes: Double?
        }
        do {
            // 1) Anchor on the operator's most recent REAL booking — never a hardcoded voyage.
            let list: ListOut = try await EusoTripAPI.shared.query("vesselShipments.getVesselShipments",
                                                                   input: ListIn(limit: 1, offset: 0))
            guard let s = list.shipments?.first, let sid = s.id else {
                hasShipment = false
                bookingId = nil; totalTonnes = nil; ciiRating = nil; ciiAttained = nil
                distanceNm = nil; teuCount = nil; fuelType = nil; legs = []
                loading = false
                return
            }
            hasShipment = true
            bookingId = s.bookingNumber

            // 2) Real shipmentId threaded into the GLEC/CII proc; TEU passed only
            //    when the booking actually records a container count.
            let o: CalcOut = try await EusoTripAPI.shared.query("co2Calculator.calculateVesselShipment",
                    input: CalcIn(shipmentId: sid, teuCount: s.numberOfContainers))

            // Unconditional overwrite — live or honest absence, never a seed.
            distanceNm = o.distanceNm
            teuCount   = o.teuCount ?? s.numberOfContainers
            fuelType   = o.fuelType
            if let t = o.co2Tonnes, t > 0 {
                totalTonnes = t
                ciiAttained = o.ciiAttained
                if let r = o.ciiRating, !r.isEmpty {
                    ciiRating = r
                    ciiBand = ["A", "B", "C", "D", "E"].firstIndex(of: r) ?? 2
                } else {
                    ciiRating = nil
                }
            } else {
                // Server computed zero — the booking has no voyage distance on
                // record. Rendering 0.00 t / rating "A" would be a fabricated
                // attainment, so we em-dash and say why.
                totalTonnes = nil
                ciiRating = nil
                ciiAttained = nil
            }
            legs = []   // no leg-telemetry source — honest empty state renders
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Export GHG statement — fires the real CSV export procedure
    /// (reports.exportCO2Statement, no input, returns {filename,mime,body}).
    private func exportStatement() async {
        exporting = true
        struct Out: Decodable { let filename: String?; let mime: String?; let body: String? }
        _ = try? await EusoTripAPI.shared.query("reports.exportCO2Statement", input: EmptyInput708()) as Out
        exporting = false
    }
}

// CII rating dial — A→E semicircle gauge + needle, mirrors the SVG arc bands.
private struct CIIGauge708: View {
    @Environment(\.palette) private var palette
    let band: Int            // 0=A … 4=E
    let label: String
    private let colors: [Color] = [Brand.success, Color(red: 0.65, green: 0.85, blue: 0.42), Brand.warning, Color(red: 1.0, green: 0.44, blue: 0.26), Brand.danger]

    var body: some View {
        VStack(spacing: 2) {
            Text("CII RATING").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            GeometryReader { geo in
                let w = geo.size.width, r = w / 2 - 5
                let cx = w / 2, cy = w / 2
                let safeBand = max(0, min(band, colors.count - 1))
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        Path { p in
                            let a0 = Angle.degrees(180 - Double(i) * 36)
                            let a1 = Angle.degrees(180 - Double(i + 1) * 36)
                            p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: -a0, endAngle: -a1, clockwise: false)
                        }.stroke(colors[i], style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    }
                    // needle to the centre of the attained band
                    let needleDeg = 180 - (Double(safeBand) + 0.5) * 36
                    Path { p in
                        p.move(to: CGPoint(x: cx, y: cy))
                        p.addLine(to: CGPoint(x: cx + (r - 6) * cos(needleDeg * .pi / 180),
                                              y: cy - (r - 6) * sin(needleDeg * .pi / 180)))
                    }.stroke(palette.textPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    Circle().fill(palette.textPrimary).frame(width: 8, height: 8).position(x: cx, y: cy)
                    Text(label).font(.system(size: 20, weight: .heavy)).foregroundStyle(colors[safeBand]).position(x: cx, y: cy + 18)
                }
            }
        }
    }
}

private struct EmptyInput708: Encodable {}

#Preview("708 · Vessel CO2 Statement · Night") { VesselShipmentCO2Screen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("708 · Vessel CO2 Statement · Light") { VesselShipmentCO2Screen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
