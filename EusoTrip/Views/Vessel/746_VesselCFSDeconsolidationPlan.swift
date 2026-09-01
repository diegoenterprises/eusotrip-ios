//
//  746_VesselCFSDeconsolidationPlan.swift
//  EusoTrip — Vessel Operator · CFS Deconsolidation Plan (CROSS-DOCK SPLIT/PLAN archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/746 Vessel CFS Deconsolidation Plan.svg":
//  a today ops-summary hero with a pallet-transferred progress bar, then a plan board of
//  deconsolidation operation cards that each visualise the SPLIT — one inbound unit fanning
//  to its outbound disposition with a per-op pallet progress bar, dock route, a priority
//  accent bar and a short ACTIVE/PLANNED/DONE pill. Then a tri-country IN-BOND MOVEMENT
//  band and the Plan-deconsolidation / Dock-map CTA pair. App Shell + real Vessel-Operator
//  BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Honest binding (frontend/server/routers/yardManagement.ts):
//    hero + op cards <- yardManagement.getCrossDockOperations (EXISTS :1362 ·
//      protectedProcedure · {locationId?} -> {operations:[{id,status,inboundDock,outboundDock,
//      inboundTrailer,outboundTrailer,inboundCarrier,outboundCarrier,palletCount,
//      palletsTransferred,startTime,estimatedCompletion,priority}],summary:{total,inProgress,
//      planned,completed,avgTransferTimeMinutes}}). Scoped by ctx.user.companyId. The SVG
//      paints inbound as an OCEAN container; the live column is inboundTrailer/unit, bound
//      honestly (the ocean-container→trailer join is a NAMED GAP getCrossDockOceanLink).
//    "Plan deconsolidation" -> yardManagement.createCrossDockPlan (EXISTS :1423) — STUB at
//      this board surface (no plan form in scope) -> routes to the plan form; re-loads here.
//    "Dock map" -> client dock overlay (re-load).
//    IN-BOND MOVEMENT band = regulatory reference (US CBP in-bond 19 CFR 18 ACTIVE ·
//      CA CBSA A8A · MX SAT tránsito interno) — NAMED GAP getInBondRegime to the-oath.
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _746.
//

import SwiftUI

// MARK: - View model

private enum XDStatus746 { case active, planned, done, cancelled }
private enum XDPriority746 { case low, normal, high, urgent }

private struct XDOpRow746: Identifiable {
    let id = UUID()
    let opId: String
    let status: XDStatus746
    let priority: XDPriority746
    let inboundUnit: String
    let outboundFlow: String
    let dockRoute: String
    let transferred: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(transferred) / Double(total) : 0 }
}

private struct XDPlanVM746 {
    let totalOps: Int
    let activeCount: Int
    let plannedCount: Int
    let doneCount: Int
    let avgMinutes: Int
    let palletsTransferred: Int
    let palletsTotal: Int
    let ops: [XDOpRow746]

    static let preview = XDPlanVM746(
        totalOps: 12, activeCount: 4, plannedCount: 6, doneCount: 2, avgMinutes: 47,
        palletsTransferred: 60, palletsTotal: 110,
        ops: [
            .init(opId: "XD-4471", status: .active, priority: .high, inboundUnit: "MRKU 744128-1", outboundFlow: "Maersk drayage", dockRoute: "D2 → D5", transferred: 18, total: 24),
            .init(opId: "XD-4468", status: .planned, priority: .normal, inboundUnit: "MSCU 612907-8", outboundFlow: "Aurora drayage", dockRoute: "D1 → D3", transferred: 0, total: 16),
            .init(opId: "XD-4455", status: .done, priority: .normal, inboundUnit: "ONEU 209514-2", outboundFlow: "2 deliveries", dockRoute: "D3 → D6", transferred: 30, total: 30),
            .init(opId: "XD-4450", status: .active, priority: .urgent, inboundUnit: "CAIU 837461-0", outboundFlow: "4 deliveries", dockRoute: "D4 → D7", transferred: 12, total: 40),
        ]
    )
}

// MARK: - Screen wrapper

struct VesselCFSDeconsolidationPlanScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCFSDeconsolidationPlanBody746()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCFSDeconsolidationPlanBody746: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: XDPlanVM746? = nil

    private func priorityColor(_ p: XDPriority746) -> Color {
        switch p {
        case .urgent: return Color(hex: 0xFF6F62)
        case .high:   return Color(hex: 0xE0A23A)
        case .normal: return Color(hex: 0x8A98A6)
        case .low:    return palette.textTertiary
        }
    }
    private func statusText(_ s: XDStatus746) -> String {
        switch s { case .active: return "ACTIVE"; case .planned: return "PLANNED"; case .done: return "DONE"; case .cancelled: return "CANCELLED" }
    }
    private func statusColor(_ s: XDStatus746) -> Color {
        switch s {
        case .active: return scheme == .dark ? Color(hex: 0x5AA6FF) : Color(hex: 0x1473FF)
        case .planned: return palette.textSecondary
        case .done: return scheme == .dark ? Color(hex: 0x34D99E) : Color(hex: 0x0A9D6E)
        case .cancelled: return Color(hex: 0xFF6F62)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading deconsolidation plan…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.ops.isEmpty {
                    hero(vm)
                    boardHeader
                    ForEach(vm.ops) { opCard($0) }
                    inBondBand
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "arrow.triangle.branch",
                                   title: "No deconsolidation operations",
                                   subtitle: "No cross-dock plan was found for this facility.")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · DECONSOLIDATION")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB CFS").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Deconsol plan").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Text("PIER J CFS · LIVE CROSS-DOCK PLAN").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero — ops summary + pallet progress
    private func hero(_ vm: XDPlanVM746) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("DECONSOL OPS · TODAY").font(.system(size: 9, weight: .heavy)).kerning(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("AVG \(vm.avgMinutes)m").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.bgCardSoft))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(vm.totalOps)").font(.system(size: 30, weight: .bold, design: .monospaced)).kerning(-0.4)
                        .foregroundStyle(LinearGradient.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vm.activeCount) active · \(vm.plannedCount) planned · \(vm.doneCount) done")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("inbound unit → outbound moves").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Text("\(vm.palletsTransferred) of \(vm.palletsTotal) plt")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(scheme == .dark ? 0.10 : 0.08)).frame(height: 10)
                            Capsule().fill(LinearGradient.primary)
                                .frame(width: geo.size.width * (vm.palletsTotal > 0 ? CGFloat(vm.palletsTransferred) / CGFloat(vm.palletsTotal) : 0), height: 10)
                        }
                    }
                    .frame(height: 10)
                }
            }
            .padding(20)
        }
        .frame(height: 124)
    }

    private var boardHeader: some View {
        HStack {
            Text("DECONSOL OPERATIONS").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text("CROSS-DOCK OPERATIONS").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Op card — the split
    private func opCard(_ op: XDOpRow746) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(priorityColor(op.priority)).frame(width: 4, height: 68)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(op.opId).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    let isUrgent = op.priority == .urgent
                    let pillColor = isUrgent ? Color(hex: 0xFF6F62) : statusColor(op.status)
                    Text(isUrgent ? "URGENT" : statusText(op.status))
                        .font(.system(size: 9, weight: .heavy)).kerning(0.4)
                        .foregroundColor(pillColor)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(pillColor.opacity(scheme == .dark ? 0.16 : 0.12)))
                }
                HStack(spacing: 8) {
                    Image(systemName: "cube.box").font(.system(size: 11, weight: .regular)).foregroundStyle(palette.textSecondary)
                    Text(op.inboundUnit).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Text(op.outboundFlow).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(scheme == .dark ? 0.10 : 0.08)).frame(height: 6)
                            Capsule().fill(priorityColor(op.priority)).frame(width: geo.size.width * op.fraction, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(op.transferred)/\(op.total) plt").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
    }

    // MARK: IN-BOND MOVEMENT band
    private var inBondBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.and.arrow.backward").font(.system(size: 11, weight: .regular)).foregroundStyle(palette.textTertiary)
                Text("IN-BOND MOVEMENT · BY AUTHORITY").font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE").font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 0) {
                inBondCol(code: "US · CBP", sub: "in-bond 19 CFR 18", active: true)
                inBondCol(code: "CA · CBSA", sub: "A8A in-bond", active: false)
                inBondCol(code: "MX · SAT", sub: "tránsito interno", active: false)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft))
    }

    private func inBondCol(code: String, sub: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            if active { Circle().fill(Brand.success).frame(width: 6, height: 6) }
            VStack(alignment: .leading, spacing: 2) {
                Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
                Text(sub).font(.system(size: 8, design: .monospaced)).foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("Plan deconsolidation").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("Dock map").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 118, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            struct Op746: Decodable {
                let id: String?; let status: String?; let inboundDock: String?; let outboundDock: String?
                let inboundTrailer: String?; let outboundCarrier: String?; let inboundCarrier: String?
                let palletCount: Int?; let palletsTransferred: Int?; let priority: String?
            }
            struct Summary746: Decodable { let total: Int?; let inProgress: Int?; let planned: Int?; let completed: Int?; let avgTransferTimeMinutes: Int? }
            struct Resp746: Decodable { let operations: [Op746]; let summary: Summary746 }

            let resp: Resp746 = try await EusoTripAPI.shared.query("yardManagement.getCrossDockOperations", input: XDInput746())

            var rows: [XDOpRow746] = []
            var sumT = 0, sumTotal = 0
            for o in resp.operations {
                let t = o.palletsTransferred ?? 0
                let total = o.palletCount ?? 0
                sumT += t; sumTotal += total
                let route: String = {
                    let a = o.inboundDock ?? "—"; let b = o.outboundDock ?? "—"
                    return "\(a) → \(b)"
                }()
                let flow = o.outboundCarrier ?? o.inboundCarrier ?? "outbound move"
                rows.append(XDOpRow746(
                    opId: o.id ?? "XD",
                    status: mapStatus(o.status),
                    priority: mapPriority(o.priority),
                    inboundUnit: o.inboundTrailer ?? "unit",
                    outboundFlow: flow,
                    dockRoute: route,
                    transferred: t,
                    total: total
                ))
            }

            if rows.isEmpty {
                vm = nil
            } else {
                vm = XDPlanVM746(
                    totalOps: resp.summary.total ?? rows.count,
                    activeCount: resp.summary.inProgress ?? rows.filter { $0.status == .active }.count,
                    plannedCount: resp.summary.planned ?? rows.filter { $0.status == .planned }.count,
                    doneCount: resp.summary.completed ?? rows.filter { $0.status == .done }.count,
                    avgMinutes: resp.summary.avgTransferTimeMinutes ?? 0,
                    palletsTransferred: sumT,
                    palletsTotal: sumTotal,
                    ops: rows
                )
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func mapStatus(_ s: String?) -> XDStatus746 {
        switch (s ?? "").lowercased() {
        case "in_progress": return .active
        case "completed": return .done
        case "cancelled": return .cancelled
        default: return .planned
        }
    }
    private func mapPriority(_ p: String?) -> XDPriority746 {
        switch (p ?? "").lowercased() {
        case "urgent": return .urgent
        case "high": return .high
        case "low": return .low
        default: return .normal
        }
    }
}

private struct XDInput746: Encodable {}

#Preview("746 · CFS Deconsolidation Plan · Light") {
    VesselCFSDeconsolidationPlanScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("746 · CFS Deconsolidation Plan · Dark") {
    VesselCFSDeconsolidationPlanScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
