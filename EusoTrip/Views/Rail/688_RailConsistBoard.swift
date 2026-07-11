//
//  688_RailConsistBoard.swift
//  EusoTrip — Rail · Carrier/Engineer · Consist Board (brick 688).
//
//  Verbatim SwiftUI port of "05 Rail/688 Rail Consist Board" (Dark).
//  CARRIER/ENGINEER-SIDE assembling-CUT BOARD: assemble and verify a train
//  consist with live specs before departure. Composition follows function — a
//  tonnage/brake summary hero (gross t, car count, hazmat, HPT, length) over a
//  cut list. Distinct from 555 (rolling-consist cards) — this is the assembly
//  board with the summary band + per-cut order rows.
//
//  Web parity: app/(rail)/consist/[trainId]/page.tsx.
//
//  tRPC wiring (honest binding — consist summary is real, per-car assembly is a
//  logged STUB the-oath owns):
//    • consist cuts + summary ← railShipments.getTrainConsists (EXISTS
//      railShipments.ts:1071 — totalCars, totalWeight, totalLengthFeet, status)
//    • per-car UMLER ← railShipments.getEquipmentSpecs (EXISTS railShipments.ts:1730)
//    • STUB → the-oath: railConsist.getConsist + addCar (the car-order
//      head→rear assembly with per-car reporting mark / lading / net tons /
//      UMLER state; today the board shows real consist-level cuts and flags the
//      per-car assembly as pending — no fabricated car rows).
//
//  RBAC: railProcedure (engineer/carrier). transportMode = rail · tri-country
//  weight-rating band US AAR 286k / CA TC 286k / MX ARTF Plate B.
//  BottomNav: carrier enum HOME · SHIPMENTS · [orb] · COMPLIANCE · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailConsistBoardAssemblyScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { RailConsistBoardAssemblyBody() } nav: {
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

// MARK: - Data (mirror getTrainConsists rows)

/// Decodes a numeric field that may serialize as a JSON number OR a string
/// (drizzle decimal columns come back as strings).
private struct FlexNum688: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

private struct Consist688: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let totalCars: Int?
    let hazmatCars: Int?
    let status: String?
    let locomotiveUnits: Int?
    let trainType: String?
    let totalWeight: FlexNum688?
    let totalLengthFeet: FlexNum688?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, hazmatCars, status, locomotiveUnits, trainType, totalWeight, totalLengthFeet
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        totalCars = try c.decodeIfPresent(Int.self, forKey: .totalCars)
        hazmatCars = try c.decodeIfPresent(Int.self, forKey: .hazmatCars)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        locomotiveUnits = try c.decodeIfPresent(Int.self, forKey: .locomotiveUnits)
        trainType = try c.decodeIfPresent(String.self, forKey: .trainType)
        totalWeight = try c.decodeIfPresent(FlexNum688.self, forKey: .totalWeight)
        totalLengthFeet = try c.decodeIfPresent(FlexNum688.self, forKey: .totalLengthFeet)
    }
}

private struct ConsistsResponse688: Decodable {
    let consists: [Consist688]
    let total: Int
}

// MARK: - Body

private struct RailConsistBoardAssemblyBody: View {
    @Environment(\.palette) private var palette

    @State private var consists: [Consist688] = []
    @State private var selectedId: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private var selected: Consist688? {
        consists.first(where: { $0.id == selectedId }) ?? consists.first
    }

    private func tons(_ f: FlexNum688?) -> String {
        guard let v = f?.value else { return "—" }
        return Int(v.rounded()).formatted(.number.grouping(.automatic))
    }
    private func lengthLabel(_ f: FlexNum688?) -> String {
        guard let v = f?.value else { return "—" }
        return v >= 1000 ? "\(String(format: "%.1f", v / 1000))k" : "\(Int(v.rounded()))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Loading consists…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if consists.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill",
                                   title: "No consists",
                                   subtitle: "Building and rolling consists appear here as cuts are assembled.")
                } else {
                    summaryHero
                    cutSection
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
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ CARRIER · RAIL · CONSIST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(selected?.consistNumber.map { "\($0)" } ?? "MANIFEST")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Consist board")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text(subtitleLine)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var subtitleLine: String {
        guard let c = selected else { return "Assembling · UMLER live" }
        let cars = c.totalCars.map { "\($0) cars" } ?? "cars pending"
        return "\(c.consistNumber ?? "Consist") · \(cars) · \((c.status ?? "assembling").replacingOccurrences(of: "_", with: " "))"
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip("\(selected?.totalCars ?? 0) cars", tint: palette.textSecondary)
            miniChip("\(tons(selected?.totalWeight)) t", tint: Color(hex: 0x6FA8FF))
            miniChip("\(selected?.hazmatCars ?? 0) hazmat", tint: Color(hex: 0xF0A742))
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

    // MARK: Summary hero

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x6FA8FF))
                Text("CONSIST · \((selected?.status ?? "assembling").uppercased().replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x6FA8FF))
                Spacer(minLength: 4)
                Text("UMLER live").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: 0x6FA8FF))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.blue.opacity(0.12)))
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tons(selected?.totalWeight))
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("t gross").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                    }
                    Text("\(selected?.totalCars ?? 0) cars · \(selected?.hazmatCars ?? 0) hazmat · brake continuity per road test")
                        .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    metricStack("HPT", value: hptLabel, tint: Brand.success)
                    metricStack("LENGTH", value: lengthLabel(selected?.totalLengthFeet), tint: palette.textPrimary)
                }
            }
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // HPT needs locomotive horsepower (not on the consist row) → honest em-dash.
    private var hptLabel: String { "—" }

    @ViewBuilder
    private func metricStack(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 17, weight: .heavy, design: .monospaced)).foregroundStyle(tint)
        }
    }

    // MARK: Cut list

    private var cutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONSIST CUTS · \(consists.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("tap a cut").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                ForEach(Array(consists.enumerated()), id: \.element.id) { idx, c in
                    cutRow(c, position: idx + 1)
                    if idx < consists.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            Text("Car order (head → rear) with per-car reporting mark + UMLER state lands with railConsist.getConsist — assembling the individual cut is pending; no fabricated car rows.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func cutRow(_ c: Consist688, position: Int) -> some View {
        Button {
            selectedId = c.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(hex: 0x05060A))
                        .overlay(Circle().strokeBorder(cutTint(c).opacity(0.5), lineWidth: 1.5))
                        .frame(width: 30, height: 30)
                    Text("\(position)").font(.system(size: 11, weight: .heavy)).foregroundStyle(cutTint(c))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.consistNumber ?? "Consist #\(c.id)")
                        .font(.system(size: 13.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text(cutSub(c)).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(tons(c.totalWeight)) t")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text(cutStatusLabel(c))
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(cutTint(c))
                }
            }
            .padding(16)
            .background(c.id == selected?.id ? Brand.blue.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func cutSub(_ c: Consist688) -> String {
        let type = c.trainType.map { $0.replacingOccurrences(of: "_", with: " ") } ?? "manifest"
        return "\(type) · \(c.totalCars ?? 0) cars · \(c.hazmatCars ?? 0) hazmat"
    }
    private func cutStatusLabel(_ c: Consist688) -> String {
        (c.status ?? "ASSEMBLING").uppercased().replacingOccurrences(of: "_", with: " ")
    }
    private func cutTint(_ c: Consist688) -> Color {
        switch (c.status ?? "").lowercased() {
        case "departed", "in_transit": return Brand.success
        case "cancelled", "bad_order": return Color(hex: 0xFF6B5E)
        default:                       return (c.hazmatCars ?? 0) > 0 ? Color(hex: 0xF0A742) : Color(hex: 0x6FA8FF)
        }
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · AAR", "286k GRL", active: true)
            regimeChip("CA · TC", "286k GRL", active: false)
            regimeChip("MX · ARTF", "Plate B", active: false)
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
            CTAButton(title: "Build train",
                      action: { buildTapped() },
                      trailingIcon: "hammer")
            RailSecondaryActionButton(
                title: "Add car",
                sheetTitle: "Consist assembly context",
                lines: [
                    selected.map { "\($0.consistNumber ?? "Consist") · \($0.totalCars ?? 0) cars · \(tons($0.totalWeight)) t gross" } ?? "No consist selected",
                    selected.map { "Length \(lengthLabel($0.totalLengthFeet)) ft · \($0.hazmatCars ?? 0) hazmat cars" } ?? "",
                    "Per-car UMLER assembly (railConsist.getConsist / addCar) is pending.",
                    "Gross tonnage evaluates against the selected GRL regime (US AAR 286k)."
                ],
                systemImage: "plus.rectangle.on.rectangle"
            )
        }
    }

    private func buildTapped() {
        actionNote = "Consist build (railConsist.assembleConsist) is pending — the board shows real consist-level cuts; per-car ordering lands with getConsist."
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct ConsistIn: Encodable { let limit: Int; let offset: Int }
        do {
            let out = try await EusoTripAPI.shared.query(
                "railShipments.getTrainConsists",
                input: ConsistIn(limit: 20, offset: 0)) as ConsistsResponse688
            self.consists = out.consists
            if selectedId == nil { selectedId = out.consists.first?.id }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("688 · Rail Consist Board · Night") {
    RailConsistBoardAssemblyScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("688 · Rail Consist Board · Light") {
    RailConsistBoardAssemblyScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
