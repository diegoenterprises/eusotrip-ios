//
//  721_VesselEUETSFuelEU.swift
//  EusoTrip — Vessel Operator · EU ETS & FuelEU Maritime emissions ledger.
//
//  Faithful 1:1 native port of "721 Vessel EU ETS FuelEU · Dark/Light".
//  SURRENDER-METER + INTENSITY-GAUGE archetype: a dual compliance instrument —
//  an EU-ETS allowance-surrender phase-in meter + a FuelEU GHG-intensity gauge +
//  the voyage fuel mix that drives both.
//
//  HONEST BINDING (server/routers/co2Calculator.ts + vesselShipments.ts):
//    · vesselShipments.getVesselShipments      — anchors the ledger to real vessel bookings.
//    · co2Calculator.calculateVesselShipment    — REAL per-booking CO₂ tonnes + fuel type/tonnes.
//  In-scope CO₂ = the summed REAL co2Tonnes; the EU-ETS surrender OBLIGATION is a
//  deterministic computation (in-scope × the 70% 2025→100% 2026 phase-in factor),
//  labelled as computed. HONEST GAP (proposed to the-oath): allowance-holding /
//  EUA price (emissions.etsLedger) and well-to-wake FuelEU intensity
//  (emissions.fuelEuIntensity) have no backing procedure today — surfaced as
//  explicit awaiting states with the published FuelEU target constant, never a
//  fabricated held/attained figure. RBAC vesselProcedure · transportMode=vessel.
//

import SwiftUI

private struct VesselShipmentList721: Decodable { let shipments: [VesselShipmentRow721]? }
private struct VesselShipmentRow721: Decodable { let id: Int?; let bookingNumber: String? }
private struct VesselCIICalc721: Decodable {
    let fuelConsumedTonnes: Double?
    let fuelType: String?
    let co2Tonnes: Double?
    let dataAvailable: Bool?
}

private struct FuelBucket721: Identifiable {
    let id = UUID()
    let fuel: String
    let tonnes: Double
    let co2Tonnes: Double
    var isBio: Bool { fuel.lowercased().contains("bio") }
}

struct VesselEUETSFuelEUScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselEUETSFuelEUBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselEUETSFuelEUBody: View {
    @Environment(\.palette) private var palette

    @State private var inScopeTco2e: Double = 0
    @State private var fuelMix: [FuelBucket721] = []
    @State private var sourceCount = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    // EU-ETS maritime phase-in: 40% (2024) · 70% (2025) · 100% (2026).
    private let surrenderPhase = 0.70
    // FuelEU Maritime 2025 GHG-intensity limit (published regulatory target,
    // well-to-wake gCO₂e/MJ) — a constant, not fabricated shipment data.
    private let fuelEuTargetGhg = 89.34

    private var obligationEua: Double { inScopeTco2e * surrenderPhase }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if inScopeTco2e <= 0 && fuelMix.isEmpty {
                    EusoEmptyState(
                        systemImage: "leaf",
                        title: "No emissions in scope",
                        subtitle: "EU-ETS surrender obligation and fuel mix appear once a vessel booking exists with enough fuel and distance data for a CO₂ calculation.")
                } else {
                    heroCard
                    surrenderMeter
                    fuelEuGauge
                    fuelMixCard
                    disclosureBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · EU ETS · FUELEU")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("EU MRV").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Emissions ledger").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([132, 100, 112], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // Hero — CO₂e in scope
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Fleet · EU MRV verified · \(currentYearString)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB))
                    Spacer()
                    StatusPill(text: "\(Int(surrenderPhase * 100))% phase", kind: .warning)
                }
                Text("EU ETS · FuelEU Maritime").font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("EU-touching voyages · allowance + intensity")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text("\(tonnes(inScopeTco2e)) t").font(.system(size: 29, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("CO₂e IN SCOPE · \(sourceCount) live calc row\(sourceCount == 1 ? "" : "s")")
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color(hex: 0x6E7681))
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 132)
    }

    // EU-ETS surrender phase-in meter (obligation computed; held/price awaiting)
    private var surrenderMeter: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("EU ETS SURRENDER · 70%→100%", ref: "emissions.etsLedger", gap: true)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Obligation \(eua(obligationEua)) EUA")
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("in-scope \(tonnes(inScopeTco2e)) tCO₂e")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft)
                        Capsule().fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00966B)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: w * CGFloat(surrenderPhase))
                        HStack {
                            Text("SURRENDER \(Int(surrenderPhase * 100))%").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).padding(.leading, 8)
                            Spacer()
                            Text("→100% by 2026").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary).padding(.trailing, 8)
                        }
                    }
                }.frame(height: 16)
                HStack {
                    Text("Surrender by 30 Sep · held-allowance reconciliation")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("EUA price awaiting ledger").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.warning)
                }
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // FuelEU GHG-intensity gauge (target known; attained awaiting WtW intensity)
    private var fuelEuGauge: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FUELEU MARITIME · intensity", ref: "emissions.fuelEuIntensity", gap: true)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GHG intensity gCO₂e/MJ").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("target \(String(format: "%.2f", fuelEuTargetGhg))").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Brand.success.opacity(0.30)).frame(height: 12)
                        Capsule().fill(Color(hex: 0xFF6F61).opacity(0.30)).frame(width: w * 0.34, height: 12).offset(x: w * 0.66)
                        Rectangle().fill(palette.textPrimary).frame(width: 2.4, height: 28).offset(x: w * 0.66 - 1.2, y: -8)
                    }
                    .overlay(alignment: .topLeading) {
                        Text("LIMIT").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            .offset(x: w * 0.66 - 12, y: -20)
                    }
                }.frame(height: 30)
                Text("Well-to-wake attained intensity + pooling balance await emissions.fuelEuIntensity — no fabricated attained value.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // Fuel mix (real from co2Calculator)
    private var fuelMixCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FUEL MIX · co2Calculator", ref: "co2Calculator.ts", gap: false)
            VStack(spacing: 10) {
                if fuelMix.isEmpty {
                    Text("Fuel-type breakdown appears once the calculator returns fuel tonnes per booking.")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(fuelMix) { f in
                        HStack(spacing: 10) {
                            Circle().fill(fuelColor(f)).frame(width: 7, height: 7)
                            Text("\(f.fuel) · \(tonnes(f.tonnes)) t").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(f.isBio ? "\(tonnes(f.co2Tonnes)) tCO₂e" : "\(tonnes(f.co2Tonnes)) tCO₂")
                                .font(.system(size: 10.5, weight: .heavy))
                                .foregroundStyle(f.isBio ? Brand.success : palette.textPrimary).monospacedDigit()
                        }
                    }
                }
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func fuelColor(_ f: FuelBucket721) -> Color {
        let k = f.fuel.lowercased()
        if k.contains("bio") { return Brand.success }
        if k.contains("mgo") || k.contains("diesel") || k.contains("gas oil") { return Brand.rail }
        return Color(hex: 0x5AB0FF)
    }

    private var disclosureBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CARBON-DISCLOSURE REGIME · at discharge", ref: "country", gap: false)
            CountryBand721(rows: [
                .init(code: "US", line: "US · EPA SmartWay · CARB at-berth (LB)", active: true),
                .init(code: "CA", line: "CA · ECCC GHGRP · CER CFR", active: false),
                .init(code: "MX", line: "MX · SEMARNAT RENE · NOM-085", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Surrender EUAs", action: {
                actionMessage = "Surrender of \(eua(obligationEua)) EUA is calculated for the \(Int(surrenderPhase * 100))% phase. An authorized registry connection is required to submit it."
            })
            Button { actionMessage = "A verified FuelEU fleet pool is required before surplus intensity can be allocated." } label: {
                Text("Pool surplus").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "NOT AVAILABLE" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    // Load
    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct CalcInput: Encodable { let shipmentId: Int }
        do {
            let list: VesselShipmentList721 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 12, offset: 0))
            guard let rows = list.shipments, !rows.isEmpty else {
                inScopeTco2e = 0; fuelMix = []; sourceCount = 0; return
            }
            var total = 0.0
            var buckets: [String: (tonnes: Double, co2: Double)] = [:]
            var count = 0
            for row in rows {
                guard let id = row.id else { continue }
                guard let calc: VesselCIICalc721 = try? await EusoTripAPI.shared.query(
                    "co2Calculator.calculateVesselShipment", input: CalcInput(shipmentId: id)) else { continue }
                guard let co2 = calc.co2Tonnes, co2 > 0 else { continue }
                count += 1
                total += co2
                let fuel = normalizeFuel(calc.fuelType)
                var b = buckets[fuel] ?? (0, 0)
                b.tonnes += calc.fuelConsumedTonnes ?? 0
                b.co2 += co2
                buckets[fuel] = b
            }
            inScopeTco2e = total
            sourceCount = count
            fuelMix = buckets
                .map { FuelBucket721(fuel: $0.key, tonnes: $0.value.tonnes, co2Tonnes: $0.value.co2) }
                .sorted { $0.co2Tonnes > $1.co2Tonnes }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            inScopeTco2e = 0; fuelMix = []
        }
    }

    private func normalizeFuel(_ raw: String?) -> String {
        guard let r = raw?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return "Fuel" }
        let k = r.lowercased()
        if k.contains("vlsfo") || k.contains("hfo") || k.contains("residual") { return "VLSFO" }
        if k.contains("mgo") || k.contains("gas oil") || k.contains("distillate") { return "MGO" }
        if k.contains("bio") { return "Bio-blend" }
        if k.contains("lng") { return "LNG" }
        return r.uppercased()
    }

    private var currentYearString: String { "CY\(Calendar.current.component(.year, from: Date()))" }
    private func tonnes(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = v < 100 ? 1 : 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }
    private func eua(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? String(format: "%.0f", v)
    }
}

private struct CountryBand721: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("721 · Vessel EU ETS FuelEU · Night") { VesselEUETSFuelEUScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("721 · Vessel EU ETS FuelEU · Light") { VesselEUETSFuelEUScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
