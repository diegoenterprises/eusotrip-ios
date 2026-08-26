//
//  680_RailLocomotiveHPPerTon.swift
//  EusoTrip — Rail Engineer · Locomotive HP-per-Ton Planning.
//
//  Bespoke port of "05 Rail/Dark-SVG/680 Rail Locomotive HP-per-Ton
//  Planning.svg". ARCHETYPE = POWER-ALLOCATION CALCULATOR — an
//  achieved-vs-required hp/ton hero over a locomotive-consist roster
//  (model, UMLER spec, online status, per-unit contribution) summing to a
//  total-power + margin reconciliation row. Not 674's single value/limit
//  gate rows, not 676's matrix.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getEquipmentSpecs EXISTS:1730 {railcarNumber} →
//        UMLER {carType,tareWeight,loadLimit,capacity,aarType,…}. Each
//        locomotive unit added pulls its REAL UMLER spec + tare weight;
//        the power consist is built from what is on file.
//    HONEST GAP: UMLER equipment specs do not carry rated horsepower or
//    tractive effort, and there is no hp-per-ton compute / grade-demand
//    reconciliation procedure on disk (getPowerPlan / assignPower — STUB).
//    The hp/ton verdict + margin render an explicit PENDING state and the
//    per-unit bar shows REAL tare-weight distribution (labelled as such) —
//    never a fabricated horsepower figure. Required hp/ton holds the
//    conservative US ruling-grade rule until the grade profile feed lights.
//

import SwiftUI

private struct UMLERSpec680: Decodable {
    let railcarNumber: String?
    let carType: String?
    let capacity: Double?
    let tareWeight: Double?
    let loadLimit: Double?
    let aarType: String?
}
private struct RailcarIn680: Encodable { let railcarNumber: String }

private struct PowerUnit680: Identifiable {
    let unit: String
    let model: String?
    let tareLb: Double?
    var id: String { unit }
}

struct RailLocomotiveHPPerTonScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailLocomotiveHPPerTonBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RailLocomotiveHPPerTonBody: View {
    @Environment(\.palette) private var palette
    @State private var units: [PowerUnit680] = []
    @State private var entry = ""
    @State private var adding = false
    @State private var addError: String? = nil
    @State private var country = 0

    private let unitColors: [Color] = [Brand.blue, Color(hex: 0x7C3FFF), Brand.magenta, Brand.info, Brand.rail]
    private let regimes: [(String, String)] = [("US · FRA", "286k grade rule"),
                                               ("CA · TC RTD", "gross rail load"),
                                               ("MX · ARTF/SICT", "carga por eje")]

    private var totalTare: Double { units.compactMap { $0.tareLb }.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("HP-per-ton plan")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · power consist · ruling grade")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                powerHero
                addRow
                rosterHeader
                rosterCard
                regimeBand
                footerActions
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · POWER PLANNING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("UMLER SPECS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("hp/t pending", Brand.warning)
            chip("\(units.count) units", palette.textSecondary)
            chip(totalTare > 0 ? "\(Int((totalTare / 1000).rounded()))k lb tare" : "no units", Brand.rail)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var powerHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("POWER vs GRADE DEMAND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.warning)
                Spacer()
                Text("HP/T PENDING")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.warning)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.warning.opacity(0.14), Brand.blue.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(units.isEmpty ? "—" : "\(units.count)")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(units.isEmpty ? "add units" : "units online").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text(units.isEmpty
                     ? "Add locomotive units — each pulls its UMLER spec. Rated hp/ton binds on getPowerPlan."
                     : "req 1.00 hp/t on ruling grade · achieved hp/ton awaits the power feed")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                if !units.isEmpty {
                    // Real tare-weight distribution across units (labelled) —
                    // the honest stand-in for the hp contribution bar until the
                    // power feed provides rated horsepower.
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(units.enumerated()), id: \.element.id) { i, u in
                                let frac = totalTare > 0 ? CGFloat(u.tareLb ?? 0) / CGFloat(totalTare) : 0
                                Capsule().fill(unitColors[i % unitColors.count])
                                    .frame(width: max(geo.size.width * frac - 2, 2), height: 9)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 9)
                    Text("bar = tare-weight share · not horsepower")
                        .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                Image(systemName: "number").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
                TextField("Add locomotive unit", text: $entry)
                    .font(.system(size: 15, weight: .bold)).monospaced()
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .foregroundStyle(palette.textPrimary)
                    .onSubmit { Task { await addUnit() } }
                Button { Task { await addUnit() } } label: {
                    if adding { ProgressView().tint(.white).frame(width: 44) }
                    else {
                        Text("Add").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30).background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                }.buttonStyle(.plain).disabled(adding || entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Space.s3).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            if let e = addError { Text(e).font(EType.caption).foregroundStyle(Brand.warning) }
        }
    }

    private var rosterHeader: some View {
        HStack {
            Text("LOCOMOTIVE CONSIST · \(units.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("UMLER specs").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var rosterCard: some View {
        Group {
            if units.isEmpty {
                Text("No units assigned. Add a locomotive to build the power consist.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { i, u in
                        unitRow(u, color: unitColors[i % unitColors.count])
                        if i < units.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                    Divider().overlay(palette.borderFaint)
                    reconciliationRow
                }
                .padding(.horizontal, 16)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func unitRow(_ u: PowerUnit680, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.18)).frame(width: 26, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.5)))
            VStack(alignment: .leading, spacing: 2) {
                Text(u.unit).font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                Text(u.model ?? "spec on file").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(u.tareLb.map { "\(Int(($0 / 1000).rounded()))k lb" } ?? "no spec")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                HStack(spacing: 4) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("hp —").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
            }
            Button { units.removeAll { $0.unit == u.unit } } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(palette.textTertiary)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var reconciliationRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total power · margin").font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Grade demand · horsepower headroom · verified power plan").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("pending").font(.system(size: 15, weight: .bold)).foregroundStyle(Brand.warning)
                Text("power feed").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 12)
    }

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { country = i } }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Assign power", action: {}).frame(maxWidth: .infinity).disabled(true)
            Button { Task { await addUnit() } } label: {
                Text("Add unit").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addUnit() async {
        let num = entry.trimmingCharacters(in: .whitespaces).uppercased()
        guard !num.isEmpty, !adding else { return }
        guard !units.contains(where: { $0.unit == num }) else { addError = "\(num) already in consist."; return }
        adding = true; addError = nil; defer { adding = false }
        let spec: UMLERSpec680? = try? await EusoTripAPI.shared.query(
            "railShipments.getEquipmentSpecs", input: RailcarIn680(railcarNumber: num))
        units.append(PowerUnit680(unit: num, model: spec?.carType, tareLb: spec?.tareWeight))
        if spec == nil { addError = "\(num) added — no UMLER spec on file." }
        entry = ""
    }
}

#Preview("680 · Locomotive HP-per-Ton · Night") {
    RailLocomotiveHPPerTonScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("680 · Locomotive HP-per-Ton · Light") {
    RailLocomotiveHPPerTonScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
