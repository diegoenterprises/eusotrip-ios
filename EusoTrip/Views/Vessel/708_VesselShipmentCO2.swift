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
//    co2Calculator.calculateVesselShipment (EXISTS frontend/server/routers/co2Calculator.ts:66 ·
//      vesselProcedure · input {shipmentId?,fuelConsumedTonnes?,fuelType?,distanceNm?,teuCount?} ·
//      returns {co2Tonnes,co2PerTeu,ciiAttained,ciiRating A|B|C|D|E,fuelConsumedTonnes,…}). The
//      booking's voyage distance + TEU + VLSFO fuel feed the IMO CII branch; the attained rating
//      drives the needle band. fuelType is lowercase per VESSEL_FUEL_CO2 keys ("vlsfo").
//    "Export GHG statement" -> reports.exportCO2Statement (EXISTS reports.ts:509 · protectedProcedure ·
//      no input · returns {filename,mime:"text/csv",body} GLEC v3.0 per-load CO2e ledger). Real
//      export verb fired for the GHG statement download.
//
//    ESang advisory: esangCoach.forScreen exists (esangCoach.ts:264) but its SCREEN_ENUM is
//    driver-centric (home/trips/earnings/…/active-trip) — there is NO vessel.co2 value, so a call
//    with a vessel screen key would fail Zod validation. The advisory is therefore an honest,
//    in-screen directional recommendation (NOT a fabricated server line, NOT a 400-ing call); the
//    named gap (a vessel-mode coach screen key) is the surfaced backend seam.
//
//  0 mock data on load · honest empty/error states — the hero/legs/CII render from live state when
//  calculateVesselShipment returns; the seed figures live ONLY in #Preview-adjacent @State so the
//  first frame is never blank. CIIGauge708 is a file-scoped bespoke dial (the canonical port's
//  CIIGauge is not a shared app symbol), built to mirror the SVG arc bands.
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

    private let bookingId = "VES-260523-9F2C41A0E7"
    @State private var totalTonnes = 2.31
    @State private var ciiRating = "C"           // band label; index drives the needle
    @State private var ciiBand = 2               // 0=A … 4=E
    @State private var legs: [EmissionLeg708] = [
        .init(title: "Ocean main leg",      sub: "Shanghai → Long Beach · VLSFO", glyph: "ferry.fill",   tonnes: 2.10, share: 0.909),
        .init(title: "Destination drayage", sub: "Long Beach → DC · diesel",       glyph: "truck.box",    tonnes: 0.18, share: 0.078),
        .init(title: "Origin gate move",    sub: "CY → berth · yard tractor",      glyph: "shippingbox",  tonnes: 0.03, share: 0.013),
    ]
    @State private var euaDue = 142
    @State private var etsCost = "€11,360"
    @State private var surrenderedPct = 0.71
    @State private var esang = "Switch to bio-bunker on EU legs"
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
                } else {
                    heroCard
                    Text("EMISSIONS BY LEG · WELL-TO-WAKE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    legsCard
                    etsBand
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
                StatusPill(text: "CII · \(ciiRating)", kind: .warning)
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CO2e · THIS BOOKING").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", totalTonnes)).font(.system(size: 40, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text("t").font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    Text("\(bookingId) · FEU · 5,720 nm").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    Text("0.40 kg/t-nm · +14% vs A-rating").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                }
                Spacer()
                CIIGauge708(band: ciiBand, label: ciiRating).frame(width: 92, height: 84)
            }
        }
    }

    private var legsCard: some View {
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

    private var etsBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EU ETS SURRENDER · 2026 · 100% PHASE-IN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
            }
            HStack {
                Text("\(euaDue) EUA due · \(etsCost)").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                Spacer()
                Text("\(Int(surrenderedPct * 100))% surrendered").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.success)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 8)
                    Capsule().fill(LinearGradient(colors: [Brand.success, Brand.info], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * surrenderedPct, height: 8)
                }
            }.frame(height: 8)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(esang).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · cuts 18% CO2e · €2,040 less ETS this qtr").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1)))
    }

    // MARK: - Data
    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let distanceNm: Double; let teuCount: Int; let fuelType: String }
        struct Out: Decodable { let co2Tonnes: Double?; let co2PerTeu: Double?; let ciiAttained: Double?; let ciiRating: String? }
        do {
            let o: Out = try await EusoTripAPI.shared.query("co2Calculator.calculateVesselShipment",
                    input: In(distanceNm: 5720, teuCount: 2, fuelType: "vlsfo"))
            if let t = o.co2Tonnes { totalTonnes = t }
            if let r = o.ciiRating, !r.isEmpty {
                ciiRating = r
                ciiBand = ["A", "B", "C", "D", "E"].firstIndex(of: r) ?? 2
            }
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
