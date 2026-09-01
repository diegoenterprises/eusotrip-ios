//
//  689_RailEquipmentSpec.swift
//  EusoTrip — Rail · Carrier/Engineer · UMLER Equipment Spec (brick 689).
//
//  Verbatim SwiftUI port of "05 Rail/689 Rail Equipment Spec" (Dark).
//  CARRIER/ENGINEER-SIDE single-car SPEC-SHEET: read one railcar's authoritative
//  UMLER mechanical record. Composition follows function — a car-identity hero
//  (reporting mark + number, AAR designator, class, a tank-car silhouette on
//  rail) over a 2-column mechanical spec grid. Distinct from 598 Equipment Specs
//  (KPI-strip detail) — this is the spec-SHEET with the silhouette + spec grid.
//
//  Web parity: app/(rail)/equipment/[carId]/page.tsx.
//
//  tRPC wiring (fully-real reads):
//    • spec   ← railShipments.getEquipmentSpecs (EXISTS railShipments.ts:1730 →
//               UMLER AAR type / dims / capacity / weights)
//    • health ← railShipments.getAssetHealth    (EXISTS railShipments.ts:1744 →
//               next inspection / condition; feeds the tank-test-due row)
//    • STUB → the-oath: equipment.getUmlerRecord (full record incl. extreme
//               height / plate / builder) + tagBadOrder; a missing dimension
//               renders '—', never a guessed value.
//
//  RBAC: railProcedure. transportMode = rail · tri-country registry band
//  US/CA AAR UMLER / MX ARTF SIID.
//  BottomNav: carrier enum HOME · SHIPMENTS · [orb] · COMPLIANCE · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailEquipmentSpecSheetScreen: View {
    let theme: Theme.Palette
    /// UMLER lookup scope. Default TILX 290185 (pressure tank car) from the
    /// wireframe; any other reporting mark + number resolves via the same shim.
    var railcarNumber: String = "TILX290185"

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { RailEquipmentSpecSheetBody(railcarNumber: railcarNumber) } nav: {
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

// MARK: - Data (mirror UMLEREquipmentSpecs / AssetHealthResult)

private struct UMLERDims689: Decodable {
    let insideLength: Double?
    let insideWidth: Double?
    let insideHeight: Double?
    let outsideLength: Double?
    let extremeHeight: Double?
    let cubicCapacity: Double?
}
private struct UMLERSpecs689: Decodable {
    let railcarNumber: String?
    let carType: String?
    let capacity: Double?
    let tareWeight: Double?
    let loadLimit: Double?
    let owner: String?
    let lessee: String?
    let dimensions: UMLERDims689?
    let buildDate: String?
    let aarType: String?
    let plateC: String?
}
private struct AssetHealth689: Decodable {
    let overallCondition: String?
    let lastInspectionDate: String?
    let nextInspectionDue: String?
}

// MARK: - Body

private struct RailEquipmentSpecSheetBody: View {
    let railcarNumber: String
    @Environment(\.palette) private var palette

    @State private var specs: UMLERSpecs689? = nil
    @State private var health: AssetHealth689? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private var reportingMark: String {
        let raw = specs?.railcarNumber ?? railcarNumber
        if raw.count > 4 {
            let idx = raw.index(raw.startIndex, offsetBy: 4)
            return "\(raw[raw.startIndex..<idx]) \(raw[idx...])"
        }
        return raw
    }
    private var aarType: String { specs?.aarType ?? "—" }
    private var isTank: Bool { aarType.uppercased().hasPrefix("T") || (specs?.carType ?? "").lowercased().contains("tank") }
    private var carClassLine: String {
        let t = specs?.carType ?? (isTank ? "pressure tank car" : "railcar")
        return "AAR \(aarType) · \(t)"
    }
    private var onFile: Bool { specs != nil }

    private func lb(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()).formatted(.number.grouping(.automatic))) lb"
    }
    private func gal(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()).formatted(.number.grouping(.automatic))) gal"
    }
    private func feet(_ v: Double?) -> String {
        guard let v else { return "—" }
        let ft = Int(v); let inch = Int((v - Double(ft)) * 12)
        return "\(ft) ft \(inch) in"
    }
    private func year(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        return String(s.prefix(4))
    }
    private func dueLabel(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        let d: Date? = ISO8601DateFormatter().date(from: s) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(s.prefix(10)))
        }()
        guard let dd = d else { return s }
        let f = DateFormatter(); f.dateFormat = "MM/yyyy"
        return "\(f.string(from: dd)) due"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Loading UMLER record…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if specs == nil {
                    EusoEmptyState(systemImage: "tram",
                                   title: "No UMLER record",
                                   subtitle: "The mechanical record for this railcar will appear here.")
                } else {
                    identityHero
                    specGrid
                    regimeRow
                    if let note = actionNote {
                        Text(note).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                EusoTripEyebrow(verbatim: "CARRIER · RAIL · EQUIPMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(reportingMark.replacingOccurrences(of: " ", with: "·"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Equipment spec")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("UMLER record · \(specs?.carType ?? (isTank ? "pressure tank car" : "railcar"))")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip(aarType, tint: Color(hex: 0x6FA8FF))
            miniChip(specs?.plateC.map { "Plate \($0)" } ?? "Plate —", tint: palette.textSecondary)
            miniChip(onFile ? "on file" : "no record", tint: onFile ? Brand.success : palette.textSecondary)
        }
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Identity hero (mark + silhouette)

    private var identityHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("UMLER RECORD · \(onFile ? "CONFIRMED" : "PENDING")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text(onFile ? "on file" : "pending")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(onFile ? Brand.success : palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill((onFile ? Brand.success : palette.textSecondary).opacity(0.14)))
            }
            Text(reportingMark)
                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            Text(carClassLine)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            tankSilhouette
                .frame(height: 40)
                .padding(.top, 4)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    /// A tank-car silhouette on rail (matches the wireframe). Rounded tank body
    /// with a dome, sitting on a rail with four wheels. Rendered from house
    /// tokens; a non-tank car would swap to a box body (isTank drives the dome).
    private var tankSilhouette: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottomLeading) {
                // rail
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: 0x2D333B))
                    .frame(width: w, height: 6)
                    .offset(y: -14)
                // tank body
                Capsule()
                    .fill(Brand.blue.opacity(0.14))
                    .overlay(Capsule().strokeBorder(Color(hex: 0x6FA8FF).opacity(0.45), lineWidth: 1.2))
                    .frame(width: w * 0.86, height: 22)
                    .offset(x: w * 0.06, y: -18)
                // dome
                if isTank {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: 0x6FA8FF).opacity(0.35))
                        .frame(width: 40, height: 8)
                        .offset(x: w * 0.44, y: -34)
                }
                // wheels
                HStack(spacing: w * 0.5 - 36) {
                    wheelPair
                    wheelPair
                }
                .offset(x: w * 0.14, y: -2)
            }
        }
    }

    private var wheelPair: some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(palette.textSecondary, lineWidth: 2).frame(width: 14, height: 14)
            Circle().strokeBorder(palette.textSecondary, lineWidth: 2).frame(width: 14, height: 14)
        }
    }

    // MARK: Spec grid (2-column)

    private var specGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MECHANICAL SPECIFICATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("RAILINC").font(.system(size: 10, weight: .regular, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                specGridRow("Load limit", lb(specs?.loadLimit), "Light weight", lb(specs?.tareWeight))
                gridDivider
                specGridRow("Capacity", gal(specs?.capacity), "Outside length", feet(specs?.dimensions?.outsideLength ?? specs?.dimensions?.insideLength))
                gridDivider
                specGridRow("Extreme height", feet(specs?.dimensions?.extremeHeight ?? specs?.dimensions?.insideHeight),
                            "Plate", specs?.plateC.map { "\($0) clearance" } ?? "—")
                gridDivider
                specGridRow("Built", builtLabel, "Tank test", dueLabel(health?.nextInspectionDue))
            }
            .padding(.vertical, 8)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private var builtLabel: String {
        let y = year(specs?.buildDate)
        if y == "—" { return "—" }
        if let owner = specs?.owner, !owner.isEmpty { return "\(y) · \(owner)" }
        return y
    }

    private var gridDivider: some View {
        Divider().padding(.horizontal, 16).overlay(palette.borderFaint)
    }

    @ViewBuilder
    private func specGridRow(_ lLabel: String, _ lValue: String, _ rLabel: String, _ rValue: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            specCell(lLabel, lValue)
            Rectangle().fill(palette.borderFaint).frame(width: 1, height: 40)
            specCell(rLabel, rValue)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder
    private func specCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9.5, weight: .bold)).tracking(0.3).foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · AAR", "UMLER", active: true)
            regimeChip("CA · TC", "UMLER", active: false)
            regimeChip("MX · ARTF", "SIID", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Brand.blue.opacity(0.12) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Add to consist",
                      action: { addTapped() },
                      trailingIcon: "plus")
            RailSecondaryActionButton(
                title: "Bad-order",
                sheetTitle: "UMLER equipment context",
                lines: [
                    "\(reportingMark) · \(carClassLine)",
                    "Load limit \(lb(specs?.loadLimit)) · light \(lb(specs?.tareWeight)) · capacity \(gal(specs?.capacity))",
                    "Owner \(specs?.owner ?? "pending") · lessee \(specs?.lessee ?? "pending")",
                    "Condition \(health?.overallCondition ?? "pending") · tank test \(dueLabel(health?.nextInspectionDue))",
                    "Bad-order tagging (equipment.tagBadOrder) is pending."
                ],
                systemImage: "wrench.and.screwdriver"
            )
        }
    }

    private func addTapped() {
        actionNote = "Add-to-consist (railConsist.addCar) is pending — the UMLER record is confirmed and ready to attach once the endpoint lands."
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct CarIn: Encodable { let railcarNumber: String }
        do {
            async let s = EusoTripAPI.shared.query(
                "railShipments.getEquipmentSpecs", input: CarIn(railcarNumber: railcarNumber)) as UMLERSpecs689?
            async let h = EusoTripAPI.shared.query(
                "railShipments.getAssetHealth", input: CarIn(railcarNumber: railcarNumber)) as AssetHealth689?
            let (sp, he) = try await (s, h)
            self.specs = sp
            self.health = he
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("689 · Rail Equipment Spec · Night") {
    RailEquipmentSpecSheetScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("689 · Rail Equipment Spec · Light") {
    RailEquipmentSpecSheetScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
