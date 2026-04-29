//
//  701_DispatchDriverBoard.swift
//  EusoTrip — Dispatch · Live driver board (HOS + load + status grid).
//

import SwiftUI

struct DispatchDriverBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DriverBoardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DriverRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let load: String?
    let location: String?
    let hoursRemaining: Double?
}

private struct DriverBoardBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [DriverRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filter: String = "all"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                segmented
                content
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
                Image(systemName: "person.3.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · DRIVER BOARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Live driver board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Statuses, loads, HOS — refreshing on pull-down.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var segmented: some View {
        HStack(spacing: 8) {
            ForEach([("all","ALL"),("driving","DRIVING"),("available","AVAILABLE")], id: \.0) { code, label in
                Button { filter = code } label: {
                    Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(filter == code ? .white : palette.textSecondary)
                        .background(filter == code ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.surface))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading drivers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if filtered.isEmpty {
            EusoEmptyState(systemImage: "person.3", title: "No drivers in this lens", subtitle: "Try a different filter or refresh the board.")
        } else {
            ForEach(filtered) { d in
                LifecycleCard(accentGradient: d.status == "driving") {
                    LifecycleSection(label: d.name.uppercased(), icon: "person.fill")
                    LifecycleRow(label: "Status",   value: d.status.uppercased())
                    LifecycleRow(label: "Load",     value: dashIfEmpty(d.load))
                    LifecycleRow(label: "Location", value: dashIfEmpty(d.location))
                    LifecycleRow(label: "HOS left", value: d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "—")
                }
            }
        }
    }

    private var filtered: [DriverRow] {
        switch filter {
        case "driving":   return rows.filter { $0.status == "driving" }
        case "available": return rows.filter { $0.status == "available" }
        default:          return rows
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int; let filter: String? }
        do {
            let r: [DriverRow] = try await EusoTripAPI.shared.api.query("dispatch.getDriverStatuses", input: In(limit: 100, filter: nil))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("701 · Driver board · Night") { DispatchDriverBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("701 · Driver board · Afternoon") { DispatchDriverBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
