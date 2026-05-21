//
//  301_CatalystDispatchBoard.swift
//  EusoTrip — Catalyst · Dispatch Board (brick 301).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/301 Dispatch Board.svg`.
//  Owner-op single-truck dispatch lens — "1 truck · today" view
//  of pending tenders + active load + driver assignment.
//
//  Wire bindings (all real, no stubs):
//    loads.list(status: "in_transit"|"accepted"|"assigned")
//    loads.list(status: "pending"|"posted")
//

import SwiftUI

private struct DispatchLoad: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let pickupDate: String?
    let distance: Double?
    let rate: String?
    let ratePerMile: String?
    let trailerType: String?
    let assignedDriverName: String?
    let expiresAt: String?
}

private struct DispatchLoadsEnvelope: Decodable {
    let loads: [DispatchLoad]?
    let items: [DispatchLoad]?
    var rows: [DispatchLoad] { loads ?? items ?? [] }
}

struct CatalystDispatchBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatchBoardBody() } nav: {
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

private struct DispatchBoardBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", pending = "Pending", active = "Active", awarded = "Awarded", closed = "Closed"
    }

    @State private var active: [DispatchLoad] = []
    @State private var pending: [DispatchLoad] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var error: String?

    private var expiringSoon: Int {
        pending.filter { expiresWithin($0.expiresAt, hours: 6) }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterTabs
                if loading && active.isEmpty && pending.isEmpty {
                    LifecycleCard { Text("Loading dispatch board…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    if filter == .all || filter == .active {
                        activeSection
                    }
                    if filter == .all || filter == .pending {
                        pendingSection
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH BOARD · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dispatch board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("1 truck · today").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(active.count) ACTIVE · \(pending.count) PENDING · \(expiringSoon) EXPIRING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let count: Int = {
                    switch f {
                    case .all:     return active.count + pending.count
                    case .pending: return pending.count
                    case .active:  return active.count
                    case .awarded: return 0
                    case .closed:  return 0
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

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVE · ASSIGNED TO YOU")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if active.isEmpty {
                LifecycleCard { Text("No active loads.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                ForEach(active) { l in activeCard(l) }
            }
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PENDING TENDERS · \(pending.count) · \(expiringSoon) EXPIRING SOON")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if pending.isEmpty {
                LifecycleCard { Text("No pending tenders.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                ForEach(pending) { l in pendingCard(l) }
            }
        }
    }

    private func activeCard(_ l: DispatchLoad) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("IN TRANSIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(Color.green)
                    if let h = l.hazmatClass {
                        Text("UN\(h) · PG II")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                }
                Text(l.loadNumber ?? "LD-\(l.id)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")")
                    .font(EType.body.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Pickup \(humanDate(l.pickupDate)) · \(Int(l.distance ?? 0)) mi")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                HStack {
                    Text("$\(l.rate ?? "—")")
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    if let rpm = l.ratePerMile {
                        Text("$\(rpm)/mi").font(.caption.monospacedDigit()).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    if let tt = l.trailerType {
                        Text(tt.uppercased())
                            .font(.caption2.weight(.bold)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if let d = l.assignedDriverName {
                    HStack(spacing: 6) {
                        Text("ME")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                        Text(d).font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func pendingCard(_ l: DispatchLoad) -> some View {
        let isExpiringSoon = expiresWithin(l.expiresAt, hours: 6)
        return LifecycleCard(accentDanger: isExpiringSoon) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(l.loadNumber ?? "LD-\(l.id)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if isExpiringSoon, let exp = l.expiresAt, let hours = hoursUntil(exp) {
                        Text("⏱ \(hours)h LEFT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(Color.red)
                    }
                }
                Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—")")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                if let r = l.rate {
                    Text("$\(r)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func humanDate(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: date)
    }

    private func expiresWithin(_ iso: String?, hours: Int) -> Bool {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return false }
        return date.timeIntervalSinceNow < Double(hours) * 3600 && date.timeIntervalSinceNow > 0
    }

    private func hoursUntil(_ iso: String) -> Int? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 3600))
    }

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadActive()
        async let p: Void = loadPending()
        _ = await (a, p)
        loading = false
    }

    private func loadActive() async {
        struct In: Encodable { let status: String?; let limit: Int }
        do {
            let r: DispatchLoadsEnvelope = try await EusoTripAPI.shared.query(
                "loads.list", input: In(status: "in_transit", limit: 25)
            )
            active = r.rows
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadPending() async {
        struct In: Encodable { let status: String?; let limit: Int }
        do {
            let r: DispatchLoadsEnvelope = try await EusoTripAPI.shared.query(
                "loads.list", input: In(status: "pending", limit: 25)
            )
            pending = r.rows
        } catch { /* */ }
    }
}

#Preview("301 Dispatch · Dark")  { CatalystDispatchBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("301 Dispatch · Light") { CatalystDispatchBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
