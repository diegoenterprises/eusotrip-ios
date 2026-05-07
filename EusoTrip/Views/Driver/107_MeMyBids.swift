//
//  107_MeMyBids.swift
//  EusoTrip 2027 UI — brick 107 (driver · my bids)
//
//  Driver-side bid manager. Lists every bid the driver has placed on
//  broker-posted loads, with status pills, round count (counter chain
//  depth), and a swipe-to-withdraw on still-pending rows. Companion
//  to 203 ShipperBids (which lists bids RECEIVED on the shipper's
//  posted loads) — same `loadBiddingRouter` backend, different lens.
//
//  Founder anchor 2026-04-28: "put bids in driver as well as they
//  bid on loads." Drivers (and small Catalysts operating their own
//  authority) bid on the broker / shipper loadboard from the load
//  detail sheet's "Book Now" / "Counter" CTAs; this brick is the
//  inbox for those open offers + their resolution state.
//
//  Wires:
//    • `loadBidding.getMyBids(limit:)` — list.
//    • `loadBidding.withdraw(bidId:)` — drop a still-pending bid.
//

import SwiftUI

// MARK: - Store

@MainActor
final class MyBidsStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([LoadBiddingAPI.MyBid])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var statusFilter: String? = nil
    @Published private(set) var withdrawing: Set<Int> = []
    @Published var lastWithdrew: Int? = nil
    @Published var lastError: String? = nil

    static let statusFilters: [(String?, String)] = [
        (nil, "All"),
        ("pending",   "Pending"),
        ("accepted",  "Accepted"),
        ("countered", "Countered"),
        ("rejected",  "Rejected"),
        ("withdrawn", "Withdrawn"),
        ("expired",   "Expired"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let rows = try await api.loadBidding.getMyBids(limit: 100)
            let visible: [LoadBiddingAPI.MyBid]
            if let f = statusFilter {
                visible = rows.filter { $0.status.lowercased() == f }
            } else {
                visible = rows
            }
            phase = .loaded(visible)
        } catch {
            phase = .error("Couldn't reach bid service.")
        }
    }

    func withdraw(_ bid: LoadBiddingAPI.MyBid) async {
        withdrawing.insert(bid.id)
        defer { withdrawing.remove(bid.id) }
        do {
            _ = try await api.loadBidding.withdraw(bidId: bid.id)
            lastWithdrew = bid.id
            await load()
        } catch {
            lastError = "Couldn't withdraw bid."
        }
    }
}

// MARK: - Brick

struct MeMyBidsView: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = MyBidsStore()
    @State private var showWithdrawAck: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                filterRow
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.statusFilter) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
        // RealtimeService → reload my-bids the moment a load is
        // assigned/reassigned or surface refreshes (broker accept,
        // bid counter, bid expire). Keeps the bids board live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.load() }
        }
        .onChange(of: store.lastWithdrew ?? -1) { _, v in if v != -1 { showWithdrawAck = true } }
        .alert("Withdrawn", isPresented: $showWithdrawAck, actions: {
            Button("OK") { store.lastWithdrew = nil }
        }, message: {
            Text("Your bid has been withdrawn.")
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("DRIVER · MY BIDS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Open offers").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Every bid you've placed · counter chain · pull-to-refresh.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                MeAction.fire("driver.loadboard.open")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.and.arrow.backward").font(.system(size: 11, weight: .heavy))
                    Text("Eusoboards").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let rows: [LoadBiddingAPI.MyBid] = {
            if case .loaded(let r) = store.phase { return r } else { return [] }
        }()
        let pending  = rows.filter { $0.status.lowercased() == "pending" }.count
        let accepted = rows.filter { $0.status.lowercased() == "accepted" }.count
        let countered = rows.filter { $0.status.lowercased() == "countered" }.count
        return HStack(spacing: Space.s2) {
            statTile(label: "TOTAL",     value: "\(rows.count)", color: nil)
            statTile(label: "PENDING",   value: "\(pending)",    color: Brand.warning)
            statTile(label: "COUNTERED", value: "\(countered)",  color: Brand.info)
            statTile(label: "WON",       value: "\(accepted)",   color: Brand.success)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(MyBidsStore.statusFilters, id: \.1) { item in
                    chip(label: item.1, active: store.statusFilter == item.0) {
                        store.statusFilter = item.0
                    }
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
                Text("Loading bids…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let rows):
            if rows.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { bid in bidRow(bid) }
                }
            }
        }
    }

    private func bidRow(_ b: LoadBiddingAPI.MyBid) -> some View {
        let style = BidStatusStyle.from(b.status)
        let isPending = b.status.lowercased() == "pending"
        return Button {
            MeAction.fire("driver.bid.detail", userInfo: ["bidId": b.id, "loadId": b.loadId])
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill").font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Load #\(b.loadId)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        statusPill(style.label, color: style.color)
                        if let r = b.bidRound, r > 1 {
                            roundChip(r)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(amountLabel(b.bidAmount))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text(b.rateType?.capitalized ?? "Flat").font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                    HStack(spacing: 6) {
                        if let c = b.createdAt {
                            Text("Placed " + Self.relative(c)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                        if let r = b.respondedAt {
                            Text("· Responded " + Self.relative(r)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if isPending {
                    if store.withdrawing.contains(b.id) {
                        ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                    } else {
                        Button {
                            Task { await store.withdraw(b) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                                .foregroundStyle(Brand.danger.opacity(0.7))
                        }.buttonStyle(.plain)
                    }
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
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

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func roundChip(_ round: Int) -> some View {
        Text("R\(round)").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(LinearGradient.diagonal))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No bids placed yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Open Eusoboards to find broker-posted loads. Tap Book Now to bid the posted rate or Counter to start a chain.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                MeAction.fire("driver.loadboard.open")
            } label: {
                Text("Open Eusoboards").font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
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
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func amountLabel(_ raw: String?) -> String {
        guard let r = raw, let v = Double(r) else { return "$—" }
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }

    private static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }
}

// MARK: - status

private struct BidStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String) -> BidStatusStyle {
        switch raw.lowercased() {
        case "pending":         return .init(label: "Pending",   color: Brand.warning)
        case "accepted":        return .init(label: "Accepted",  color: Brand.success)
        case "auto_accepted":   return .init(label: "Auto-won",  color: Brand.success)
        case "countered":       return .init(label: "Countered", color: Brand.info)
        case "rejected":        return .init(label: "Rejected",  color: Brand.danger)
        case "withdrawn":       return .init(label: "Withdrawn", color: Brand.neutral)
        case "expired":         return .init(label: "Expired",   color: Brand.neutral)
        default:                return .init(label: raw.capitalized, color: Brand.neutral)
        }
    }
}

// MARK: - Screen wrapper

struct MeMyBidsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeMyBidsView()
        } nav: {
            BottomNav(
                leading: driverNavLeading_107(),
                trailing: driverNavTrailing_107(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_107() -> [NavSlot] {
    [NavSlot(label: "Home", systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul", systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_107() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("107 · Me · MyBids · Night") {
    MeMyBidsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("107 · Me · MyBids · Afternoon") {
    MeMyBidsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
