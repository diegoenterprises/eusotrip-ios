//
//  401_BrokerLoadBoard.swift
//  EusoTrip — Broker · Load board (shipper-posted loads available to broker).
//
//  Cross-role chain: shipper posts → broker board surfaces → broker
//  vets carrier (402) → broker tenders to carrier (403) → carrier
//  accepts → settlement layer splits commission to broker (404).
//

import SwiftUI

struct BrokerLoadBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadBoardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct BoardLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let shipperName: String?
    let lane: String?
    let cargoType: String?
    let postedRate: Double?
    let mileage: Int?
    let pickupISO: String?
    let estimatedMargin: Double?
    // 2026-05-17 — Multi-modal payload (optional on the wire so older
    // server builds decode cleanly; UI defaults to truck when nil).
    let transportMode: String?
    let multiVehicleCount: Int?
}

private enum BrokerKanbanColumn: String, CaseIterable, Identifiable {
    case available = "Available"
    case tendered  = "Tendered"
    case recent    = "Recent"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .available: return "shippingbox.fill"
        case .tendered:  return "paperplane.fill"
        case .recent:    return "checkmark.seal.fill"
        }
    }
}

private struct LoadBoardBody: View {
    @Environment(\.palette) private var palette

    @State private var available: [BoardLoad] = []
    @State private var tendered: [BrokerAPI.OpenTender] = []
    @State private var recent: [BrokerAPI.RecentLoad] = []
    @State private var availableLoading = true
    @State private var tenderedLoading  = true
    @State private var recentLoading    = true
    @State private var availableError: String? = nil
    @State private var tenderedError:  String? = nil
    @State private var recentError:    String? = nil
    @State private var selectedColumn  = BrokerKanbanColumn.available

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            columnScrubber.padding(.bottom, 6)
            columnPager
        }
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · LOAD BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                let total = available.count + tendered.count + recent.count
                if total > 0 {
                    Text("\(total) LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(palette.bgCard).clipShape(Capsule())
                }
            }
            Text("Load board")
                .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Track loads from first sight to settlement.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Column scrubber

    private var columnScrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BrokerKanbanColumn.allCases) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selectedColumn = col }
                    } label: {
                        let count = colCount(col)
                        let on = selectedColumn == col
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text(count.map { "\($0)" } ?? "—")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private func colCount(_ col: BrokerKanbanColumn) -> Int? {
        switch col {
        case .available: return availableLoading ? nil : available.count
        case .tendered:  return tenderedLoading  ? nil : tendered.count
        case .recent:    return recentLoading    ? nil : recent.count
        }
    }

    // MARK: - Column pager

    private var columnPager: some View {
        TabView(selection: $selectedColumn) {
            ForEach(BrokerKanbanColumn.allCases) { col in
                columnView(col).tag(col)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    @ViewBuilder
    private func columnView(_ col: BrokerKanbanColumn) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: 6) {
                    Text(col.rawValue.uppercased())
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(colCount(col) ?? 0)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                }
                switch col {
                case .available: availableContent
                case .tendered:  tenderedContent
                case .recent:    recentContent
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    // MARK: - Available column

    @ViewBuilder
    private var availableContent: some View {
        if availableLoading {
            columnSkeleton
        } else if let err = availableError {
            columnError(err)
        } else if available.isEmpty {
            EusoEmptyState(systemImage: "shippingbox", title: "No loads on the board",
                           subtitle: "Loads in BIDDING status from shippers in your network surface here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(available) { ld in
                    Button {
                        NotificationCenter.default.post(
                            name: .eusoBrokerNavSwap, object: nil,
                            userInfo: ["screenId": "402", "loadId": ld.id]
                        )
                    } label: {
                        LifecycleCard(accentGradient: (ld.estimatedMargin ?? 0) > 200) {
                            HStack(spacing: 8) {
                                LifecycleSection(label: ld.loadNumber.uppercased(), icon: "doc.text")
                                Spacer(minLength: 0)
                                LoadModeBadge(modeRaw: ld.transportMode,
                                              multiVehicleCount: ld.multiVehicleCount,
                                              compact: true)
                            }
                            LifecycleRow(label: "Shipper",     value: dashIfEmpty(ld.shipperName))
                            LifecycleRow(label: "Lane",        value: dashIfEmpty(ld.lane))
                            LifecycleRow(label: "Cargo",       value: dashIfEmpty(ld.cargoType))
                            LifecycleRow(label: "Rate",        value: usd(ld.postedRate))
                            LifecycleRow(label: "Mileage",     value: ld.mileage.map { "\($0) mi" } ?? "—")
                            LifecycleRow(label: "Est. margin", value: usd(ld.estimatedMargin))
                            LifecycleRow(label: "Pickup",      value: humanISO(ld.pickupISO))
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tendered column

    @ViewBuilder
    private var tenderedContent: some View {
        if tenderedLoading {
            columnSkeleton
        } else if let err = tenderedError {
            columnError(err)
        } else if tendered.isEmpty {
            EusoEmptyState(systemImage: "paperplane", title: "No open tenders",
                           subtitle: "Tenders you've posted to carriers surface here while they're still in flight.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(tendered, id: \.id) { t in
                    LifecycleCard(accentGradient: t.respondingCarriers > 0) {
                        LifecycleSection(label: t.loadNumber.uppercased(), icon: "paperplane.fill")
                        LifecycleRow(label: "Shipper",    value: t.shipper.isEmpty ? "—" : t.shipper)
                        LifecycleRow(label: "Lane",       value: "\(t.origin) → \(t.destination)")
                        LifecycleRow(label: "Target",     value: usd(t.targetRate))
                        LifecycleRow(label: "Responding", value: "\(t.respondingCarriers) carrier\(t.respondingCarriers == 1 ? "" : "s")")
                        LifecycleRow(label: "Posted",     value: humanISO(t.postedAt))
                    }
                }
            }
        }
    }

    // MARK: - Recent column

    @ViewBuilder
    private var recentContent: some View {
        if recentLoading {
            columnSkeleton
        } else if let err = recentError {
            columnError(err)
        } else if recent.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal", title: "No recent loads",
                           subtitle: "Settled loads you brokered appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(recent, id: \.id) { r in
                    LifecycleCard(accentGradient: r.netMargin > 0) {
                        LifecycleSection(label: r.loadNumber.uppercased(), icon: "checkmark.seal.fill")
                        LifecycleRow(label: "Status",     value: r.status.uppercased())
                        LifecycleRow(label: "Lane",       value: "\(r.origin) → \(r.destination)")
                        LifecycleRow(label: "Delivered",  value: humanISO(r.deliveredAt))
                        LifecycleRow(label: "Net margin", value: usd(r.netMargin))
                    }
                }
            }
        }
    }

    // MARK: - Skeleton / error helpers

    private var columnSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .opacity(0.6)
            }
        }
    }

    private func columnError(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    // MARK: - Fetches

    private func loadAll() async {
        async let a: Void = fetchAvailable()
        async let b: Void = fetchTendered()
        async let c: Void = fetchRecent()
        _ = await (a, b, c)
    }

    private func fetchAvailable() async {
        availableLoading = true; availableError = nil
        do {
            let r: [BoardLoad] = try await EusoTripAPI.shared.queryNoInput("brokers.getLoadBoard")
            available = r
        } catch {
            availableError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        availableLoading = false
    }

    private func fetchTendered() async {
        tenderedLoading = true; tenderedError = nil
        do {
            tendered = try await EusoTripAPI.shared.broker.getOpenTenders()
        } catch {
            tenderedError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        tenderedLoading = false
    }

    private func fetchRecent() async {
        recentLoading = true; recentError = nil
        do {
            recent = try await EusoTripAPI.shared.broker.getRecentLoads()
        } catch {
            recentError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        recentLoading = false
    }
}

#Preview("401 · Broker board · Night") { BrokerLoadBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("401 · Broker board · Afternoon") { BrokerLoadBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
