//
//  108_MeLoadBoard.swift
//  EusoTrip 2027 UI — brick 108 (driver · loadboard browse + bid)
//
//  The discovery surface drivers were missing — broker-/shipper-
//  posted loads filtered by lane, equipment, hazmat, and rate. Each
//  row surfaces the market rate AND the lane-contract rate (when
//  the shipper has a contract on this lane) so the driver knows
//  whether they're bidding spot or contracted before they tap.
//
//  Founder anchor 2026-04-28: "put bids in driver as well as they
//  bid on loads." 107 MeMyBids inboxes already-placed bids; 108
//  MeLoadBoard is the entry point — without this, MyBids stays
//  empty.
//
//  Wires:
//    • `loadBoard.search(originState:destState:equipmentType:hazmat:
//      sortBy:limit:offset:)` — already added to LoadBoardAPI this
//      firing.
//    • Tap row → `MeAction.fire("driver.load.detail", userInfo:
//      ["loadId":])` — chrome routes to the existing iOS load-detail
//      sheet which already exposes Book-Now / Counter via
//      `LoadBiddingAPI.submit / .counter`.
//

import SwiftUI

// MARK: - Store

@MainActor
final class MeLoadBoardStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(LoadBoardAPI.SearchResponse)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var originState: String = ""
    @Published var destState: String = ""
    @Published var equipmentType: String? = nil
    @Published var hazmatOnly: Bool = false
    @Published var sortBy: String = "posted_date"

    static let equipmentChips: [(String?, String)] = [
        (nil, "All"),
        ("dry_van", "Dry van"),
        ("reefer", "Reefer"),
        ("flatbed", "Flatbed"),
        ("tanker", "Tanker"),
        ("step_deck", "Step deck"),
    ]
    static let sortChips: [(String, String)] = [
        ("posted_date", "Newest"),
        ("rate", "$ Rate"),
        ("distance", "Distance"),
        ("pickup_date", "Pickup"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func search() async {
        phase = .loading
        do {
            let r = try await api.loadBoard.search(
                originState: originState.isEmpty ? nil : originState.uppercased(),
                destState:   destState.isEmpty   ? nil : destState.uppercased(),
                equipmentType: equipmentType,
                hazmat: hazmatOnly ? true : nil,
                sortBy: sortBy,
                limit: 50,
                offset: 0
            )
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't reach loadboard.")
        }
    }
}

// MARK: - Brick

struct MeLoadBoardView: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = MeLoadBoardStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                marketHero
                laneInputCard
                equipmentRow
                sortRow
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.search() }
        .onChange(of: store.equipmentType) { _, _ in Task { await store.search() } }
        .onChange(of: store.hazmatOnly) { _, _ in Task { await store.search() } }
        .onChange(of: store.sortBy) { _, _ in Task { await store.search() } }
        .refreshable { await store.search() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shippingbox.and.arrow.backward.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("DRIVER · LOADBOARD").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Open loads").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Filter by lane · equipment · hazmat · sort by rate / distance / pickup. Tap row to bid.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.top, 4)
    }

    @ViewBuilder
    private var marketHero: some View {
        if case .loaded(let r) = store.phase {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("MARKET PULSE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(r.total) loads").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "$%.2f", r.marketStats.avgRate))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text("/ mi avg").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                }
                if r.marketStats.loadToTruckRatio > 0 {
                    HStack(spacing: 6) {
                        Text("LOAD:TRUCK").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(String(format: "%.2f", r.marketStats.loadToTruckRatio))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var laneInputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                stateField(label: "ORIGIN", text: $store.originState)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                stateField(label: "DEST", text: $store.destState)
            }
            HStack(spacing: 8) {
                Toggle(isOn: $store.hazmatOnly) {
                    Text("Hazmat only")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: Brand.danger))
                Spacer()
                Button {
                    Task { await store.search() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .heavy))
                        Text("Search").font(.system(size: 12, weight: .heavy))
                    }.foregroundStyle(.white)
                    .padding(.horizontal, Space.s3).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func stateField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            TextField("XX", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .onChange(of: text.wrappedValue) { _, v in
                    if v.count > 2 { text.wrappedValue = String(v.prefix(2)) }
                }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var equipmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MeLoadBoardStore.equipmentChips, id: \.1) { item in
                    chip(label: item.1, active: store.equipmentType == item.0) {
                        store.equipmentType = item.0
                    }
                }
            }
        }
    }

    private var sortRow: some View {
        HStack(spacing: 6) {
            Text("SORT").font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            ForEach(MeLoadBoardStore.sortChips, id: \.0) { item in
                chip(label: item.1, active: store.sortBy == item.0) {
                    store.sortBy = item.0
                }
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Searching loadboard…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let r):
            if r.loads.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(r.loads) { row in loadRow(row) }
                }
            }
        }
    }

    private func loadRow(_ l: LoadBoardAPI.SearchRow) -> some View {
        let perMile: Double = (l.distance > 0) ? l.rate / l.distance : 0
        let isContract = l.isLaneContract == true
        return Button {
            MeAction.fire("driver.load.detail", userInfo: ["loadId": l.id])
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(l.loadNumber ?? "Load #\(l.id)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    if isContract {
                        contractBadge
                    }
                    if l.hazmat == true {
                        hazmatBadge(class: l.hazmatClass)
                    }
                    Spacer(minLength: 0)
                    Text(rateLabel(l.rate)).font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                }
                Text("\(l.origin.display) → \(l.destination.display)")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    if l.distance > 0 {
                        miniPill("\(Int(l.distance.rounded())) mi")
                    }
                    if perMile > 0 {
                        miniPill(String(format: "$%.2f/mi", perMile))
                    }
                    if let eq = l.equipmentType, !eq.isEmpty {
                        miniPill(eq.replacingOccurrences(of: "_", with: " ").uppercased())
                    }
                    if let cargo = l.cargoType, !cargo.isEmpty, l.hazmat != true {
                        miniPill(cargo.uppercased())
                    }
                    if let weight = l.weight, weight > 0 {
                        miniPill(String(format: "%.0f lb", weight))
                    }
                }
                if isContract, let contractRate = l.laneContractRate {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.success)
                        Text("Lane contract: ").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text(String(format: "$%.2f", contractRate))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.success)
                        if let rt = l.laneContractRateType {
                            Text(rt).font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                if let pd = l.pickupDate {
                    Text("Pickup " + Self.relative(pd))
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var contractBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 8, weight: .heavy))
            Text("CONTRACT").font(.system(size: 8, weight: .heavy)).tracking(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(LinearGradient.diagonal))
    }

    private func hazmatBadge(class hzc: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8, weight: .heavy))
            Text(hzc.flatMap { $0.isEmpty ? nil : "HAZ \($0)" } ?? "HAZMAT")
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
        }
        .foregroundStyle(Brand.danger)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(Brand.danger.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.5)))
    }

    private func miniPill(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.4)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No loads match").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Try a wider lane, drop the hazmat filter, or change equipment. The whole national feed is one search away.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.search() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func rateLabel(_ r: Double) -> String {
        if r >= 10_000 { return String(format: "$%.0fK", r / 1000) }
        if r >= 1_000  { return String(format: "$%.1fK", r / 1000) }
        return String(format: "$%.0f", r)
    }

    private static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = d.timeIntervalSinceNow
        if s > 0 {
            if s < 3600 { return "in \(Int(s/60))m" }
            if s < 86400 { return "in \(Int(s/3600))h" }
            return "in \(Int(s/86400))d"
        } else {
            let abs = -s
            if abs < 3600 { return "\(Int(abs/60))m ago" }
            if abs < 86400 { return "\(Int(abs/3600))h ago" }
            return "\(Int(abs/86400))d ago"
        }
    }
}

// MARK: - Screen wrapper

struct MeLoadBoardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeLoadBoardView()
        } nav: {
            BottomNav(
                leading: driverNavLeading_108(),
                trailing: driverNavTrailing_108(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_108() -> [NavSlot] {
    [NavSlot(label: "Home", systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul", systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_108() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("108 · Me · LoadBoard · Night") {
    MeLoadBoardScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("108 · Me · LoadBoard · Afternoon") {
    MeLoadBoardScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
