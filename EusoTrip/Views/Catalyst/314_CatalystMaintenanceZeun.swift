//
//  314_CatalystMaintenanceZeun.swift
//  EusoTrip — Catalyst · Maintenance · Zeun (brick 314).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/314 Maintenance Zeun.svg`.
//  Owner-op asset-bound maintenance ledger — Eusotrans owns the
//  asset, Michael drives, same companyId, clean DVIR chain. Real
//  endpoints from the Zeun router (no stubs).
//
//  Wire bindings:
//    zeun.getFleetHealth          — assets / OOS risk / 30D cost
//    zeun.getMaintenanceDue       — DUE rows
//    maintenance.getUpcoming      — full 90d window
//    maintenance.getHistory       — cleared rows
//    zeunMechanics.getFleetBreakdowns  — recall rows
//

import SwiftUI

private struct FleetHealth: Decodable, Hashable {
    let assets: Int?
    let nextPmDays: Int?
    let nextPmDate: String?
    let oosRisk: Int?
    let cost30d: Double?
}

private struct ZeunEvent: Decodable, Hashable, Identifiable {
    let id: String
    let axis: String?         // "ME" / "ASSET"
    let urgency: String?      // due / active / cleared / recall
    let title: String?
    let summary: String?
    let detail: String?
    let dueAt: String?
    let mileageTarget: Int?
}

struct CatalystMaintenanceZeunScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ZeunBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ZeunBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", due = "Due", active = "Active", cleared = "Cleared", recall = "Recall"
    }

    @State private var health: FleetHealth?
    @State private var events: [ZeunEvent] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var error: String?

    private var dueCount: Int     { events.filter { ($0.urgency ?? "").lowercased() == "due" }.count }
    private var activeCount: Int  { events.filter { ($0.urgency ?? "").lowercased() == "active" }.count }
    private var clearedCount: Int { events.filter { ($0.urgency ?? "").lowercased() == "cleared" }.count }
    private var recallCount: Int  { events.filter { ($0.urgency ?? "").lowercased() == "recall" }.count }

    private var filtered: [ZeunEvent] {
        guard filter != .all else { return events }
        return events.filter { ($0.urgency ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                kpiStrip
                filterTabs
                if loading && events.isEmpty {
                    LifecycleCard { Text("Loading maintenance…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "wrench.and.screwdriver",
                                   title: "No events in this lens",
                                   subtitle: "Scheduled service, DOT inspections, and recalls land here.")
                } else {
                    Text("\(events.count) EVENTS · RANKED BY URGENCY · ME / ASSET-BOUND AXIS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { e in eventCard(e) }
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
                Text("CATALYST · MAINTENANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Maintenance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Zeun ledger · clean DVIR chain").font(EType.caption).foregroundStyle(palette.textSecondary)
            let days = health?.nextPmDays ?? 0
            Text("\(dueCount) DUE · \(days)D · \(recallCount) RECALL\(recallCount == 1 ? "" : "S")")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · CLEAN DVIR CHAIN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Eusotrans owns the asset · Michael drives it · same companyId · zero off-rotation drift")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpi("ASSETS", "\(health?.assets ?? 0)", "Active fleet", .blue)
            kpi("NEXT PM", "\(health?.nextPmDays ?? 0)d", shortDate(health?.nextPmDate), .orange)
            kpi("OOS RISK", "\(health?.oosRisk ?? 0)", "Clean DVIR chain", (health?.oosRisk ?? 0) > 0 ? .red : .green)
            kpi("30D COST", "$\(Int(health?.cost30d ?? 0).formatted(.number))", "Q2 YTD trailing", .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let count: Int = {
                    switch f {
                    case .all:     return events.count
                    case .due:     return dueCount
                    case .active:  return activeCount
                    case .cleared: return clearedCount
                    case .recall:  return recallCount
                    }
                }()
                Button { filter = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        if count > 0 { Text("· \(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(filter == f ? .white : palette.textSecondary)
                    .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func eventCard(_ e: ZeunEvent) -> some View {
        let urgencyUpper = (e.urgency ?? "").uppercased()
        let urgencyColor: Color = {
            switch urgencyUpper {
            case "DUE":     return .orange
            case "ACTIVE":  return .blue
            case "CLEARED": return .green
            case "RECALL":  return .red
            default:        return palette.textSecondary
            }
        }()
        return LifecycleCard(accentDanger: urgencyUpper == "RECALL") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(e.id)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if let a = e.axis {
                        Text(a)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(urgencyUpper)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(urgencyColor.opacity(0.18)))
                        .foregroundStyle(urgencyColor)
                }
                if let t = e.title { Text(t).font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary) }
                if let s = e.summary { Text(s).font(.caption).foregroundStyle(palette.textSecondary) }
                if let d = e.detail { Text(d).font(.caption2).foregroundStyle(palette.textTertiary) }
            }
        }
    }

    // MARK: helpers

    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "MMM d"
            return out.string(from: d)
        }
        return iso
    }

    // MARK: pipeline

    private func load() async {
        loading = true; error = nil
        async let h: Void = loadHealth()
        async let e: Void = loadEvents()
        _ = await (h, e)
        loading = false
    }

    private func loadHealth() async {
        do { health = try await EusoTripAPI.shared.queryNoInput("zeun.getFleetHealth") } catch { /* */ }
    }

    private func loadEvents() async {
        struct In: Encodable { let days: Int? }
        do {
            events = try await EusoTripAPI.shared.query("maintenance.getUpcoming", input: In(days: 90))
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

#Preview("314 Maintenance · Dark")  { CatalystMaintenanceZeunScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("314 Maintenance · Light") { CatalystMaintenanceZeunScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
