//
//  771_VesselConsolidationSuggestions.swift
//  EusoTrip — Vessel Operator · Consolidation Suggestions (LCL → FEU).
//
//  Verbatim port of wireframe 771 (06 Vessel · Dark) — a purpose-built
//  MERGE-RECOMMENDATION surface: each recommended group is drawn as a
//  merge graph (N loose LCL source chips converging into one consolidated
//  FEU) with the dollars saved, fill %, and compatibility score — NOT a
//  flat chip-list. The hero is a portfolio-savings band, not an ActiveCard
//  detail. Answers "which loose LCL bookings should I combine into one FEU
//  on the same sailing to split the freight bill and raise margin."
//
//  Endpoints (server/routers/loadConsolidation.ts):
//    getDashboard  (:112 · protectedProcedure · query → ConsolidationDashboard)
//    acceptGroup   (:119 · {groupId} mutation)  — "Build group" / "Apply"
//    rejectGroup   (:190 · {groupId, reason} mutation) — "Dismiss"
//  Honest gap (surfaced to the-oath): getDashboard scores corridors off the
//  loads table; the LCL→FEU container-fill + ocean-sailing-window scoring is
//  a vessel-specific extension — propose getVesselConsolidationGroups()
//  returning the same ConsolidationGroup shape keyed off shippingContainers
//  + sailing eta (reuses accept/reject, no new write).
//

import SwiftUI

struct VesselConsolidationSuggestionsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselConsolidationSuggestionsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (loadConsolidation.getDashboard)

private struct ConsolidationDashboard771: Decodable {
    let totalGroups: Int
    let totalShipments: Int
    let totalSavings: Double
    let avgSavingsPct: Double
    let avgCapacityUtil: Double
    let groups: [ConsolidationGroup771]
    let topCorridors: [TopCorridor771]

    private enum CodingKeys: String, CodingKey {
        case totalGroups, totalShipments, totalSavings, avgSavingsPct, avgCapacityUtil, groups, topCorridors
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        totalGroups     = (try? c.decode(Int.self, forKey: .totalGroups)) ?? 0
        totalShipments  = (try? c.decode(Int.self, forKey: .totalShipments)) ?? 0
        totalSavings    = Decode771.double(c, .totalSavings)
        avgSavingsPct   = Decode771.double(c, .avgSavingsPct)
        avgCapacityUtil = Decode771.double(c, .avgCapacityUtil)
        groups          = (try? c.decode([ConsolidationGroup771].self, forKey: .groups)) ?? []
        topCorridors    = (try? c.decode([TopCorridor771].self, forKey: .topCorridors)) ?? []
    }
}

private struct TopCorridor771: Decodable, Identifiable {
    var id: String { corridor }
    let corridor: String
    let opportunities: Int
    let potentialSavings: Double
    private enum CodingKeys: String, CodingKey { case corridor, opportunities, potentialSavings }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        corridor        = (try? c.decode(String.self, forKey: .corridor)) ?? "—"
        opportunities   = (try? c.decode(Int.self, forKey: .opportunities)) ?? 0
        potentialSavings = Decode771.double(c, .potentialSavings)
    }
}

private struct ConsolidationGroup771: Decodable, Identifiable {
    var id: String { groupId }
    let groupId: String
    let corridor: String
    let shipments: [ShipmentCandidate771]
    let consolidatedRate: Double
    let soloTotalRate: Double
    let savings: Double
    let savingsPct: Double
    let capacityUtilization: Double
    let distanceSaved: Double
    let status: String
    let compatibilityScore: Double
    let compatibilityIssues: [String]

    private enum CodingKeys: String, CodingKey {
        case groupId, corridor, shipments, consolidatedRate, soloTotalRate
        case savings, savingsPct, capacityUtilization, distanceSaved, status, compatibility
    }
    private enum CompatKeys: String, CodingKey { case score, issues }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        groupId             = (try? c.decode(String.self, forKey: .groupId)) ?? UUID().uuidString
        corridor            = (try? c.decode(String.self, forKey: .corridor)) ?? "—"
        shipments           = (try? c.decode([ShipmentCandidate771].self, forKey: .shipments)) ?? []
        consolidatedRate    = Decode771.double(c, .consolidatedRate)
        soloTotalRate       = Decode771.double(c, .soloTotalRate)
        savings             = Decode771.double(c, .savings)
        savingsPct          = Decode771.double(c, .savingsPct)
        capacityUtilization = Decode771.double(c, .capacityUtilization)
        distanceSaved       = Decode771.double(c, .distanceSaved)
        status              = (try? c.decode(String.self, forKey: .status)) ?? "proposed"
        if let cc = try? c.nestedContainer(keyedBy: CompatKeys.self, forKey: .compatibility) {
            compatibilityScore  = (try? cc.decode(Double.self, forKey: .score)) ?? 0
            compatibilityIssues = (try? cc.decode([String].self, forKey: .issues)) ?? []
        } else {
            compatibilityScore = 0; compatibilityIssues = []
        }
    }
    var totalPallets: Int { shipments.reduce(0) { $0 + $1.pallets } }
    var shipperCount: Int { Set(shipments.map { $0.shipperId }).count }
}

private struct ShipmentCandidate771: Decodable, Identifiable {
    var id: String { loadId }
    let loadId: String
    let shipperId: String
    let pallets: Int
    let hazmat: Bool
    private enum CodingKeys: String, CodingKey { case loadId, shipperId, pallets, hazmat }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        loadId    = (try? c.decode(String.self, forKey: .loadId)) ?? UUID().uuidString
        shipperId = (try? c.decode(String.self, forKey: .shipperId)) ?? "—"
        pallets   = (try? c.decode(Int.self, forKey: .pallets)) ?? 0
        hazmat    = (try? c.decode(Bool.self, forKey: .hazmat)) ?? false
    }
}

private enum Decode771 {
    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Double {
        if let d = try? c.decode(Double.self, forKey: k) { return d }
        if let s = try? c.decode(String.self, forKey: k), let d = Double(s) { return d }
        return 0
    }
}

// MARK: - Body

private struct VesselConsolidationSuggestionsBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: ConsolidationDashboard771? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actingGroupId: String? = nil
    @State private var toast: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · CONSOLIDATION",
                caption: "LCL → FEU",
                title: "Consolidation",
                idText: "VES-260524-B920E5"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else if let dash {
                    savingsBand(dash)
                    if let t = toast { VesselToastRow(text: t) }
                    groupsSection(dash)
                    esangAdvisory(dash)
                    ctaPair(dash)
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Portfolio savings summary band (cardRim + inset)
    private func savingsBand(_ d: ConsolidationDashboard771) -> some View {
        ActiveCard {
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt771.money(d.totalSavings))
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("potential savings · \(d.totalGroups) group\(d.totalGroups == 1 ? "" : "s") · \(d.totalShipments) LCL bookings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(topCorridorLine(d))
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AVG SAVE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(Int(d.avgSavingsPct.rounded()))%")
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Brand.success)
                    Text("vs solo LCL").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func topCorridorLine(_ d: ConsolidationDashboard771) -> String {
        if let top = d.topCorridors.first {
            return "top corridor \(top.corridor) · avg fill \(Int(d.avgCapacityUtil.rounded()))%"
        }
        return "avg fill \(Int(d.avgCapacityUtil.rounded()))%"
    }

    @ViewBuilder
    private func groupsSection(_ d: ConsolidationDashboard771) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel771(text: "RECOMMENDED GROUPS", endpoint: "getDashboard")
            if d.groups.isEmpty {
                EusoEmptyState(
                    systemImage: "square.stack.3d.up",
                    title: "No consolidation opportunities",
                    subtitle: "Loose LCL bookings that share a sailing window will surface here for one-tap FEU grouping."
                )
            } else {
                ForEach(d.groups) { g in mergeCard(g) }
            }
        }
    }

    // Merge-graph card: source LCL chips → 1× FEU + savings + fill + compat.
    private func mergeCard(_ g: ConsolidationGroup771) -> some View {
        let acting = actingGroupId == g.groupId
        let compatOK = g.compatibilityScore >= 0.9 && g.compatibilityIssues.isEmpty
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.corridor).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(g.groupId) · \(g.shipments.count) LCL bookings")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                statusPill(g.status, compatOK: compatOK)
            }

            HStack(alignment: .center, spacing: Space.s3) {
                // Source LCL chips
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(g.shipments.prefix(3)) { s in
                        Text("LCL · \(s.pallets)plt")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x90A4AE))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Brand.rail.opacity(0.14)))
                    }
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                // Consolidated FEU node
                VStack(spacing: 1) {
                    Text("1× FEU").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Text("\(g.totalPallets) plt").font(.system(size: 9)).foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: 62, height: 42)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient.diagonal))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("SAVES").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(Fmt771.money(g.savings))
                        .font(.system(size: 20, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // Fill + compat bar
            let fill = max(0, min(1, g.capacityUtilization / 100))
            VStack(spacing: 6) {
                HStack {
                    Text("FILL \(Int(g.capacityUtilization.rounded()))%")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(String(format: "COMPAT %.2f", g.compatibilityScore))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderFaint).frame(height: 6)
                        Capsule()
                            .fill(compatOK ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
                            .frame(width: geo.size.width * fill, height: 6)
                    }
                }
                .frame(height: 6)
            }

            Divider().overlay(palette.borderFaint)

            HStack(alignment: .center, spacing: 8) {
                Text(footerLine(g))
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Button {
                    Task { await accept(g) }
                } label: {
                    Group {
                        if acting { ProgressView().controlSize(.mini).tint(.white) }
                        else { Text(compatOK ? "Apply" : "Review").font(.system(size: 11, weight: .bold)) }
                    }
                    .foregroundStyle(compatOK ? Color.white : palette.textPrimary)
                    .frame(width: 74, height: 26)
                    .background(
                        Capsule().fill(compatOK
                                       ? AnyShapeStyle(LinearGradient.primary)
                                       : AnyShapeStyle(palette.bgCardSoft))
                    )
                    .overlay(Capsule().strokeBorder(compatOK ? Color.clear : palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(acting)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func footerLine(_ g: ConsolidationGroup771) -> String {
        var parts: [String] = ["\(g.shipperCount) shipper\(g.shipperCount == 1 ? "" : "s") · proportional split"]
        if g.distanceSaved > 0 { parts.append("\(Int(g.distanceSaved.rounded())) mi drayage saved") }
        if let issue = g.compatibilityIssues.first { parts = ["\(g.shipperCount) shippers · \(issue)"] }
        return parts.joined(separator: " · ")
    }

    private func statusPill(_ status: String, compatOK: Bool) -> some View {
        let up = status.uppercased()
        let kind: StatusPill.Kind = up.contains("ACCEPT") ? .success
            : up.contains("REJECT") ? .neutral
            : compatOK ? .info : .warning
        let label = up.contains("ACCEPT") ? "ACCEPTED"
            : up.contains("REJECT") ? "DISMISSED"
            : compatOK ? "PROPOSED" : "REVIEW COO"
        return StatusPill(text: label, kind: kind)
    }

    private func esangAdvisory(_ d: ConsolidationDashboard771) -> some View {
        let best = d.groups.max(by: { $0.savings < $1.savings })
        return EsangAdvisory771(
            title: best.map { "Apply \($0.groupId) before the sailing cutoff" }
                ?? "No open groups to lock right now",
            message: best.map { "Locks the \(Fmt771.money($0.savings)) split — \(Int($0.capacityUtilization.rounded()))% fill" }
                ?? "New LCL bookings on a shared sailing will appear here."
        )
    }

    private func ctaPair(_ d: ConsolidationDashboard771) -> some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Build group", action: {
                if let g = d.groups.max(by: { $0.savings < $1.savings }) { Task { await accept(g) } }
            })
            Button {
                if let g = d.groups.first { Task { await dismissGroup(g) } }
            } label: {
                Text("Dismiss").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 84)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 178)
            }
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil
        do {
            let d: ConsolidationDashboard771 = try await EusoTripAPI.shared.queryNoInput(
                "loadConsolidation.getDashboard")
            self.dash = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func accept(_ g: ConsolidationGroup771) async {
        actingGroupId = g.groupId
        struct In: Encodable { let groupId: String }
        do {
            let _: AcceptResult771 = try await EusoTripAPI.shared.mutation(
                "loadConsolidation.acceptGroup", input: In(groupId: g.groupId))
            toast = "Group \(g.groupId) built — \(Fmt771.money(g.savings)) locked"
            await load()
        } catch {
            toast = (error as? EusoTripAPIError)?.errorDescription ?? "Could not build group"
        }
        actingGroupId = nil
    }

    private func dismissGroup(_ g: ConsolidationGroup771) async {
        actingGroupId = g.groupId
        struct In: Encodable { let groupId: String; let reason: String }
        do {
            let _: AcceptResult771 = try await EusoTripAPI.shared.mutation(
                "loadConsolidation.rejectGroup", input: In(groupId: g.groupId, reason: "operator_dismissed"))
            toast = "Dismissed \(g.groupId)"
            await load()
        } catch {
            toast = (error as? EusoTripAPIError)?.errorDescription ?? "Could not dismiss group"
        }
        actingGroupId = nil
    }
}

private struct AcceptResult771: Decodable {
    let groupId: String?
    let status: String?
    private enum CodingKeys: String, CodingKey { case groupId, status }
    init(from d: Decoder) throws {
        let c = try? d.container(keyedBy: CodingKeys.self)
        groupId = try? c?.decode(String.self, forKey: .groupId)
        status  = try? c?.decode(String.self, forKey: .status)
    }
}

private enum Fmt771 {
    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
    }
}

// MARK: - Shared small views (file-private)

private struct SectionLabel771: View {
    @Environment(\.palette) private var palette
    let text: String
    var endpoint: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            if let endpoint {
                Text(endpoint).font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

private struct EsangAdvisory771: View {
    @Environment(\.palette) private var palette
    let title: String
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(message).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("771 · Consolidation · Night") { VesselConsolidationSuggestionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("771 · Consolidation · Light") { VesselConsolidationSuggestionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
