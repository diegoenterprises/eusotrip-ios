//
//  704_VesselBayPlan.swift
//  EusoTrip — Vessel Operator · Bay Plan (CARRIER-SIDE · GRID/STOWAGE class).
//
//  PURPOSE-BUILT: the source wireframe "704 Vessel Bay Plan.svg" ships EMPTY in
//  the catalog (0 bytes, Dark + Light), so this screen is composed to the golden
//  bar from the real vesselShipments router blueprint + design authority. A
//  STOWAGE CROSS-SECTION grid — an on-deck / under-deck bay of container slots
//  coloured by cargo state, over a slot legend and a container roster. A stow
//  grid, distinct from a timeline (666), a move ledger (707) or a stat card.
//
//  Web parity: ContainerPositions.tsx (`/vessel/bay-plan`).
//
//  DATA (endpoints confirmed on disk this fire):
//    vesselShipments.getContainerPositions {status?, limit}
//        → { containers[{ id, containerNumber, sizeType, status, currentPortId }], total }
//        (vesselProcedure · server/routers/vesselShipments.ts:2143)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • shipping_containers carries NO bay / row / tier stow-coordinate columns —
//      so the cross-section is an explicit SCHEMATIC stow (roster packed into
//      slots in order), NOT a claim of real bay/row/tier positions. Propose
//      vessel.getBayPlan {bay, row, tier, aboveDeck} for a true stow plan. The
//      on-deck / under-deck split here is derived from container status, labelled
//      as a schematic, never a fabricated slot address.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · ISO 6346. PERSONA Vessel Operator · Aurora Ocean Division.
//

import SwiftUI

struct VesselBayPlanScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselBayPlanBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct BayContainer: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let sizeType: String?
    let status: String?
    let currentPortId: Int?
}
private struct ContainerPositionsResponse: Decodable {
    let containers: [BayContainer]
    let total: Int
}

private enum SlotState {
    case reefer, laden, empty, atPort, unknown
    var color: Color {
        switch self {
        case .reefer: return Brand.info
        case .laden:  return Brand.blue
        case .empty:  return Brand.neutral
        case .atPort: return Brand.success
        case .unknown: return Brand.magenta
        }
    }
    var label: String {
        switch self {
        case .reefer: return "Reefer"; case .laden: return "Laden"; case .empty: return "Empty"
        case .atPort: return "At port"; case .unknown: return "Other"
        }
    }
}

// MARK: - Body

private struct VesselBayPlanBody: View {
    @Environment(\.palette) private var palette

    @State private var response: ContainerPositionsResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let columns = 8
    private let maxSlots = 48

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    stowSummaryHero
                    bayGridCard
                    legend
                    rosterCard
                    gapNote
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var containers: [BayContainer] { response?.containers ?? [] }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · BAY PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(response?.total ?? 0) BOXES")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Bay plan")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Stow summary hero

    private var stowSummaryHero: some View {
        HStack(spacing: 0) {
            heroStat("\(containers.count)", "STOWED")
            divider
            heroStat("\(reeferCount)", "REEFER")
            divider
            heroStat("\(ladenCount)", "LADEN")
            divider
            heroStat("\(emptyCount)", "EMPTY")
        }
        .padding(.vertical, Space.s4).padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func heroStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.22)).frame(width: 1, height: 30) }

    private var reeferCount: Int { containers.filter { slotState($0) == .reefer }.count }
    private var ladenCount: Int { containers.filter { slotState($0) == .laden }.count }
    private var emptyCount: Int { containers.filter { slotState($0) == .empty }.count }

    // MARK: Bay grid

    private var bayGridCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("STOW CROSS-SECTION · getContainerPositions")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)

            if loading {
                LifecycleCard { Text("Loading stow plan…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            } else if containers.isEmpty {
                EusoEmptyState(icon: Image(systemName: "square.grid.3x3"),
                               title: "No containers to stow",
                               subtitle: "The bay cross-section fills as containers are assigned in the position feed.")
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("ON DECK").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    slotGrid(Array(displaySlots.prefix(columns * 2)))
                    Rectangle().fill(LinearGradient.iridescentHairlineDark).frame(height: 1).padding(.vertical, 2)
                    Text("UNDER DECK").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    slotGrid(Array(displaySlots.dropFirst(columns * 2)))
                    if containers.count > maxSlots {
                        Text("+\(containers.count - maxSlots) more boxes in the roster")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary).padding(.top, 2)
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.xl)
            }
        }
    }

    private var displaySlots: [BayContainer] { Array(containers.prefix(maxSlots)) }

    private func slotGrid(_ slots: [BayContainer]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: columns)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(slots) { c in
                let st = slotState(c)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(st.color.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(st.color, lineWidth: 0.8))
                    .frame(height: 20)
                    .overlay(
                        Group {
                            if st == .reefer {
                                Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                    )
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: Space.s4) {
            ForEach([SlotState.reefer, .laden, .empty, .atPort], id: \.label) { st in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(st.color.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(st.color, lineWidth: 0.8))
                        .frame(width: 12, height: 12)
                    Text(st.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Roster

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONTAINER ROSTER · ISO 6346")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if containers.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(containers.prefix(8).enumerated()), id: \.element.id) { idx, c in
                        rosterRow(c)
                        if idx < min(containers.count, 8) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s1)
                        }
                    }
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    private func rosterRow(_ c: BayContainer) -> some View {
        let st = slotState(c)
        return HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 8).fill(st.color.opacity(0.18)).frame(width: 36, height: 36)
                .overlay(Image(systemName: st == .reefer ? "thermometer.snowflake" : "shippingbox")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(st.color))
            VStack(alignment: .leading, spacing: 3) {
                Text(c.containerNumber ?? "BOX #\(c.id)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(humanSize(c.sizeType))\(c.currentPortId.map { " · port \($0)" } ?? "")")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            StatusPill(text: st.label, kind: pillKind(st))
        }
    }

    private var gapNote: some View {
        Text("Slot positions are a schematic stow — shipping_containers carries no bay/row/tier columns yet (pending vessel.getBayPlan).")
            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit = 100 }
        do {
            let res: ContainerPositionsResponse = try await EusoTripAPI.shared.query("vesselShipments.getContainerPositions", input: In())
            self.response = res
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: helpers

    private func slotState(_ c: BayContainer) -> SlotState {
        let size = (c.sizeType ?? "").lowercased()
        if size.contains("reefer") { return .reefer }
        switch (c.status ?? "").lowercased() {
        case "empty": return .empty
        case "at_port", "at_depot", "discharged": return .atPort
        case "loaded", "in_transit", "laden", "assigned": return .laden
        case "": return .unknown
        default: return .laden
        }
    }
    private func humanSize(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "40ft_hc": return "40HC dry"
        case "40ft": return "40ft dry"
        case "20ft": return "20ft dry"
        case "45ft": return "45ft dry"
        case "40ft_reefer": return "40ft reefer"
        case "20ft_reefer": return "20ft reefer"
        case "": return "container"
        default: return (raw ?? "container").replacingOccurrences(of: "_", with: " ")
        }
    }
    private func pillKind(_ st: SlotState) -> StatusPill.Kind {
        switch st {
        case .reefer: return .info
        case .laden: return .info
        case .empty: return .neutral
        case .atPort: return .success
        case .unknown: return .neutral
        }
    }
}

#Preview("704 · Vessel Bay Plan · Night") {
    VesselBayPlanScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("704 · Vessel Bay Plan · Light") {
    VesselBayPlanScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
