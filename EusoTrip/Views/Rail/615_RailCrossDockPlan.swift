//
//  615_RailCrossDockPlan.swift
//  EusoTrip — Rail · Rail Engineer · Cross-Dock Plan (brick 615).
//
//  Verbatim SwiftUI port of "05 Rail/615 Rail Cross-Dock Plan · Dark" at the
//  golden design-authority bar. CARRIER (Rail Engineer) vantage on a transload
//  facility's door-to-door flow: a bespoke BIPARTITE DOOR-FLOW hero (inbound rail
//  doors on the left, outbound dray doors on the right, joined by colour-coded
//  flow lines), a 3-cell KPI strip, an assignments card, an ESANG row, and an
//  Auto-plan / Commit-plan CTA pair. NOT a stat grid, NOT a timeline.
//
//  Nav: REAL Rail Engineer enum HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode = rail · US (Corwith transload CHI). Persona Owen Trask (OT).
//
//  WIRING (web parity rail/transload/[facility]/cross-dock):
//    orders → multiModal.getTransloading  EXISTS · multiModal.ts:1140
//      ({page,limit,status?}) → { orders[{orderNumber,status,inboundMode,
//      outboundMode,inboundContainer,outboundTrailers[],facility,commodity,
//      weight,palletCount,scheduledDate}], total, page, totalPages } — the real
//      transloadOrders ledger. Each order = one inbound→outbound cross-dock move.
//    Auto-plan   → LOCAL optimizer (re-sequences to surface/clear the conflict).
//    Commit plan → STUB · named-gap crossDockPlan.commit (no door-slot column on
//      transloadOrders/intermodalTransfers; door-assignment persistence handed to
//      the-oath). Surfaced honestly — never faked. Nearest real write is
//      intermodal.recordTransfer (cross_dock facilityType) once segment ids exist.
//  Door labels are a display convenience over the REAL orders (commodity/status/
//  trailers are real). RBAC protectedProcedure (company-scoped).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (mirror multiModal.getTransloading)

private struct TransloadOrder615: Decodable, Identifiable {
    let id: String
    let orderNumber: String?
    let status: String?              // scheduled | in_progress | completed | cancelled
    let inboundMode: String?
    let outboundMode: String?
    let inboundContainer: String?
    let outboundTrailers: [String]?
    let facility: String?
    let commodity: String?
    let weight: Double?
    let palletCount: Int?
    let scheduledDate: String?
}
private struct TransloadResult615: Decodable {
    let orders: [TransloadOrder615]?
    let total: Int?
}

// MARK: - Screen wrapper

struct RailCrossDockPlanScreen: View {
    let theme: Theme.Palette
    var facility: String = "Corwith · CHI"

    var body: some View {
        Shell(theme: theme) { RailCrossDockPlanBody(facility: facility) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",  isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailCrossDockPlanBody: View {
    @Environment(\.palette) private var palette
    let facility: String

    @State private var orders: [TransloadOrder615] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var autoPlanned = false

    @State private var actionBanner: String? = nil
    @State private var actionIsError = false
    @State private var committing = false

    private var planned: [TransloadOrder615] {
        // Auto-plan re-sequences so conflicts surface to the top for resolution.
        guard autoPlanned else { return orders }
        return orders.sorted { rank($0.status) < rank($1.status) }
    }
    private func rank(_ s: String?) -> Int {
        switch (s ?? "").lowercased() { case "cancelled": return 0; case "in_progress": return 1; case "scheduled": return 2; default: return 3 }
    }

    private var assignedCount: Int { orders.filter { !($0.outboundTrailers?.isEmpty ?? true) }.count }
    private var conflictCount: Int { orders.filter { ($0.status ?? "").lowercased() == "cancelled" }.count }
    private var doorCount: Int { max(orders.count * 2, orders.count) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleRow
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else {
                    doorFlowHero.padding(.top, Space.s4)
                    kpiStrip.padding(.top, Space.s4)
                    assignmentsCard.padding(.top, Space.s4)
                    esangRow.padding(.top, Space.s4)
                    if let banner = actionBanner { actionBannerView(banner).padding(.top, Space.s3) }
                    ctaPair.padding(.top, Space.s4)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("✦ RAIL ENGINEER · CROSS-DOCK PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text((orders.first?.facility ?? facility).uppercased())
                .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack {
            Text("Cross-dock plan").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer(minLength: Space.s2)
            HStack(spacing: 5) {
                Circle().fill(conflictCount > 0 ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                Text(conflictCount > 0 ? "\(conflictCount) CONFLICT" : "CLEAR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(conflictCount > 0 ? Brand.warning : Brand.success)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill((conflictCount > 0 ? Brand.warning : Brand.success).opacity(0.14)))
        }
        .padding(.top, Space.s3)
    }

    // MARK: Door-flow hero

    private var doorFlowHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DOCK FLOOR · \((orders.first?.facility ?? facility).uppercased())")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if orders.isEmpty {
                Text("No transload orders on the floor.").font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                CrossDockFloor615(orders: Array(planned.prefix(4)), palette: palette)
                    .frame(height: 150)
                // legend
                HStack(spacing: Space.s4) {
                    legend(Brand.success, "assigned"); legend(Brand.warning, "conflict"); legendLine("planned")
                    Spacer()
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 7, height: 7); Text(t).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary) }
    }
    private func legendLine(_ t: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0x607D8B)).frame(width: 10, height: 3); Text(t).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary) }
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("DOORS", "\(doorCount)", highlight: false, color: palette.textPrimary)
            kpiCell("ASSIGNED", "\(assignedCount) / \(orders.count)", highlight: true, color: .white)
            kpiCell("CONFLICTS", "\(conflictCount)", highlight: false, color: conflictCount > 0 ? Brand.warning : palette.textPrimary)
        }
    }
    private func kpiCell(_ label: String, _ value: String, highlight: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(highlight ? .white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Assignments card

    private var assignmentsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ASSIGNMENTS · IN → OUT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if orders.isEmpty {
                EusoEmptyState(systemImage: "arrow.left.arrow.right.square",
                               title: "No assignments",
                               subtitle: "Transload orders appear as inbound→outbound moves.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(planned.enumerated()), id: \.element.id) { idx, o in
                        assignmentRow(o, index: idx)
                        if idx < planned.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func assignmentRow(_ o: TransloadOrder615, index: Int) -> some View {
        let st = flowState(o.status)
        let inbound = "D\(index + 1)"
        let outbound = (o.outboundTrailers?.isEmpty ?? true) ? "open" : o.outboundTrailers!.prefix(2).joined(separator: " / ")
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(st.color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(st.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(inbound) → \(outbound)").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(assignSub(o)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(st.label).font(.system(size: 9.5, weight: .heavy)).tracking(0.3).foregroundStyle(st.color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(st.color.opacity(0.14)))
        }
        .padding(Space.s4)
    }

    private func assignSub(_ o: TransloadOrder615) -> String {
        let cargo = o.commodity ?? "cargo"
        let flow = "\((o.inboundMode ?? "rail")) → \((o.outboundMode ?? "dray"))"
        return "\(cargo) · \(flow)"
    }

    private func flowState(_ s: String?) -> (label: String, color: Color) {
        switch (s ?? "").lowercased() {
        case "completed", "in_progress": return ("routed", Brand.success)
        case "cancelled":                return ("conflict", Brand.warning)
        case "scheduled":                return ("planned", Color(hex: 0x607D8B))
        default:                         return ("open", palette.textSecondary)
        }
    }

    // MARK: ESang row

    private var esangRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(esangHead).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
                Text(esangSub).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var esangHead: String {
        conflictCount > 0 ? "ESang: \(conflictCount) door conflict — re-route to clear" : "ESang: floor is routed clean"
    }
    private var esangSub: String { "\(assignedCount) of \(orders.count) orders routed · commit to lock the door plan" }

    // MARK: Action banner + CTA

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button(action: autoPlan) {
                HStack(spacing: 6) { Image(systemName: "list.bullet.indent"); Text("Auto-plan") }
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 150, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }.buttonStyle(.plain)
            CTAButton(title: committing ? "Committing…" : "Commit plan",
                      action: { Task { await commit() } }, trailingIcon: "checkmark", isLoading: committing)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct PageIn: Encodable { let page: Int; let limit: Int }
        do {
            let r: TransloadResult615 = try await EusoTripAPI.shared.query("multiModal.getTransloading", input: PageIn(page: 1, limit: 20))
            self.orders = r.orders ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func autoPlan() {
        autoPlanned.toggle()
        actionIsError = false
        actionBanner = autoPlanned ? "Auto-planned · conflicts surfaced to the top" : "Restored order sequence"
    }

    private func commit() async {
        guard !committing else { return }
        committing = true; actionBanner = nil
        // PORT-GAP: crossDockPlan.commit is a named-gap STUB — transloadOrders has
        // no door-slot column, so door-assignment persistence has no backing yet.
        // Propose multiModal.commitCrossDockPlan({facility,assignments[]}) → the-oath.
        struct CommitIn: Encodable { let facility: String; let assignmentCount: Int }
        struct CommitOut: Decodable { let committed: Int? }
        do {
            let out: CommitOut = try await EusoTripAPI.shared.mutation("multiModal.commitCrossDockPlan",
                input: CommitIn(facility: facility, assignmentCount: orders.count))
            actionIsError = false
            actionBanner = "Door plan committed · \(out.committed ?? orders.count) assignment\(orders.count == 1 ? "" : "s")"
        } catch {
            actionIsError = true
            actionBanner = "Door-plan commit not yet wired (named gap). "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        committing = false
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 68)
        }
    }
    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Cross-dock floor (bipartite door flow)

private struct CrossDockFloor615: View {
    let orders: [TransloadOrder615]
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(orders.count, 1)
            let rowH = h / CGFloat(n)
            ZStack {
                // header labels
                VStack {
                    HStack {
                        Text("INBOUND · RAIL").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.info)
                        Spacer()
                        Text("OUTBOUND · DRAY").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                    Spacer()
                }
                // flow lines + doors
                ForEach(Array(orders.enumerated()), id: \.element.id) { idx, o in
                    let y = rowH * (CGFloat(idx) + 0.5) + 8
                    let color = lineColor(o.status)
                    Path { p in
                        p.move(to: CGPoint(x: 0.30 * w, y: y))
                        p.addCurve(to: CGPoint(x: 0.70 * w, y: y),
                                   control1: CGPoint(x: 0.50 * w, y: y),
                                   control2: CGPoint(x: 0.50 * w, y: y))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round,
                                                      dash: (o.status ?? "") == "scheduled" ? [4, 5] : []))
                    // inbound door (left)
                    doorChip("D\(idx + 1)", sub: shortCargo(o.commodity), tint: Brand.escort)
                        .position(x: 0.16 * w, y: y)
                    // outbound door (right)
                    doorChip(outLabel(o, idx), sub: outSub(o), tint: Brand.success)
                        .position(x: 0.84 * w, y: y)
                }
            }
        }
    }

    private func doorChip(_ label: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(width: 92, alignment: .leading)
        .background(tint.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(0.9), lineWidth: 1.2))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    private func outLabel(_ o: TransloadOrder615, _ idx: Int) -> String {
        (o.outboundTrailers?.first).map { String($0.prefix(6)) } ?? "D\(idx + 9)"
    }
    private func outSub(_ o: TransloadOrder615) -> String { (o.outboundMode ?? "dray") }
    private func shortCargo(_ c: String?) -> String { c.map { String($0.prefix(12)) } ?? "cargo" }
    private func lineColor(_ s: String?) -> Color {
        switch (s ?? "").lowercased() { case "cancelled": return Brand.warning; case "scheduled": return Color(hex: 0x607D8B); default: return Brand.success }
    }
}

// MARK: - Previews

#Preview("615 · Rail Cross-Dock Plan · Night") {
    RailCrossDockPlanScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("615 · Rail Cross-Dock Plan · Light") {
    RailCrossDockPlanScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
