//
//  109_MeBidDetail.swift
//  EusoTrip 2027 UI — brick 109 (driver · bid detail / chain)
//
//  Multi-round counter-chain view. Reached by tapping a row in 107
//  MeMyBids or a `BID_COUNTERED` push notification. Renders the full
//  bid thread (round 1 → round N) with status pills, amounts, and
//  conditions; the bottom CTA bar resolves the LATEST unresolved row
//  and offers Accept / Counter / Withdraw based on whose turn it is.
//
//  Wires:
//    • `loadBidding.getBidChain(loadId:rootBidId:)` — fetch chain.
//    • `loadBidding.accept(bidId:)`                 — driver accepts
//      the shipper's counter.
//    • `loadBidding.counter(parentBidId:loadId:counterAmount:)` —
//      driver counters the shipper's counter.
//    • `loadBidding.withdraw(bidId:)`               — driver drops
//      their own pending bid.
//

import SwiftUI

// MARK: - Store

@MainActor
final class MeBidDetailStore: ObservableObject {
    enum Phase {
        case loading
        case loaded([LoadBiddingAPI.ChainRow])
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var working: Bool = false
    @Published var lastAck: String? = nil
    @Published var lastError: String? = nil
    @Published var counterAmount: String = ""

    let loadId: Int
    private let api: EusoTripAPI

    init(loadId: Int, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            let chain = try await api.loadBidding.getBidChain(loadId: loadId)
            phase = .loaded(chain)
        } catch {
            phase = .error("Couldn't load bid chain.")
        }
    }

    func accept(bidId: Int) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.loadBidding.accept(bidId: bidId)
            lastAck = "Bid accepted — load assigned."
            await load()
        } catch {
            lastError = "Couldn't accept. Compliance gate may have rejected (FMCSA / authority)."
        }
    }

    func counter(parentBidId: Int, amount: Double) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.loadBidding.counter(parentBidId: parentBidId, loadId: loadId, counterAmount: amount)
            lastAck = "Counter sent."
            counterAmount = ""
            await load()
        } catch {
            lastError = "Couldn't counter."
        }
    }

    func withdraw(bidId: Int) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.loadBidding.withdraw(bidId: bidId)
            lastAck = "Bid withdrawn."
            await load()
        } catch {
            lastError = "Couldn't withdraw."
        }
    }
}

// MARK: - Brick

struct MeBidDetailView: View {
    let loadId: Int
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: MeBidDetailStore
    @State private var showCounterSheet: Bool = false
    @State private var showAck: Bool = false

    init(loadId: Int) {
        self.loadId = loadId
        _store = StateObject(wrappedValue: MeBidDetailStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $showCounterSheet) { counterSheet }
        .onChange(of: store.lastAck ?? "") { _, v in if !v.isEmpty { showAck = true } }
        .alert("Done", isPresented: $showAck, actions: {
            Button("OK") { store.lastAck = nil }
        }, message: {
            if let s = store.lastAck { Text(s) }
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("DRIVER · BID THREAD").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("Counter chain").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text("Load #\(loadId) · all rounds in order. Latest pending row drives the CTA bar.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            HStack {
                ProgressView()
                Text("Loading thread…").font(EType.caption).foregroundStyle(palette.textSecondary)
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
                threadList(rows)
                ctaBar(rows)
            }
        }
    }

    private func threadList(_ rows: [LoadBiddingAPI.ChainRow]) -> some View {
        VStack(spacing: 8) {
            ForEach(rows) { row in chainRow(row) }
        }
    }

    private func chainRow(_ r: LoadBiddingAPI.ChainRow) -> some View {
        let style = ChainStatusStyle.from(r.status)
        let role = (r.bidderRole ?? "").lowercased()
        let isMine = role == "driver" || role == "catalyst"
        return HStack(alignment: .top, spacing: 10) {
            roundBadge(r.bidRound ?? 1, isMine: isMine)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(roleLabel(r.bidderRole)).font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(isMine ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                    statusPill(style.label, color: style.color)
                    if r.isAutoAccepted == true {
                        miniPill("AUTO", color: Brand.success)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(amountLabel(r.bidAmount))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text(r.rateType?.replacingOccurrences(of: "_", with: " ") ?? "flat")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                if let c = r.conditions, !c.isEmpty {
                    Text(c).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if let eq = r.equipmentType, !eq.isEmpty {
                        miniPill(eq.replacingOccurrences(of: "_", with: " ").uppercased(), color: nil)
                    }
                    if let t = r.transitTimeDays, t > 0 {
                        miniPill("\(t)d transit", color: nil)
                    }
                    if r.fuelSurchargeIncluded == true {
                        miniPill("FSC INCL", color: Brand.success)
                    }
                }
                HStack(spacing: 6) {
                    if let cAt = r.createdAt {
                        Text(Self.relative(cAt)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    if let exp = r.expiresAt {
                        Image(systemName: "clock").font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text("Expires " + Self.relative(exp)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMine ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(palette.bgCardSoft.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func roundBadge(_ round: Int, isMine: Bool) -> some View {
        VStack(spacing: 0) {
            Text("R\(round)").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(isMine ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }

    private func roleLabel(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "driver":   return "You (Driver)"
        case "catalyst": return "You (Catalyst)"
        case "broker":   return "Broker"
        case "escort":   return "Escort"
        default:         return (raw ?? "Counterparty").capitalized
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func miniPill(_ s: String, color: Color?) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundStyle(color ?? palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill((color ?? palette.textTertiary).opacity(0.15)))
            .overlay(Capsule().strokeBorder((color ?? palette.borderFaint).opacity(0.5)))
    }

    @ViewBuilder
    private func ctaBar(_ rows: [LoadBiddingAPI.ChainRow]) -> some View {
        if let resolution = resolution(for: rows) {
            VStack(spacing: 10) {
                switch resolution {
                case .driverPending(let bidId):
                    primaryDangerButton("Withdraw bid", systemImage: "xmark.circle.fill") {
                        Task { await store.withdraw(bidId: bidId) }
                    }
                case .shipperCountered(let bidId, _):
                    primaryGradientButton("Accept counter", systemImage: "checkmark.seal.fill") {
                        Task { await store.accept(bidId: bidId) }
                    }
                    secondaryButton("Counter back", systemImage: "arrow.uturn.backward") {
                        showCounterSheet = true
                    }
                    secondaryButton("Withdraw thread", systemImage: "xmark.circle") {
                        Task { await store.withdraw(bidId: bidId) }
                    }
                case .terminal(let label, let color):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(color)
                        Text("Thread closed · \(label.uppercased())")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(color.opacity(0.4)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                if let e = store.lastError {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }
            }
            .padding(.top, Space.s2)
        }
    }

    private func primaryGradientButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if store.working {
                    ProgressView().scaleEffect(0.6).tint(.white)
                } else {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .heavy))
                }
                Text(store.working ? "Working…" : label).font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.working)
    }

    private func primaryDangerButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if store.working {
                    ProgressView().scaleEffect(0.6).tint(Brand.danger)
                } else {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .heavy))
                }
                Text(store.working ? "Working…" : label).font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(Brand.danger).background(palette.bgCard)
            .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.6)))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.working)
    }

    private func secondaryButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .heavy))
                Text(label).font(.system(size: 12, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundStyle(palette.textPrimary).background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.working)
    }

    @ViewBuilder
    private var counterSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("COUNTER OFFER").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Your counter").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text("Push back on the shipper's counter with your number. Server inserts a new round in the chain and notifies the other party.")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("AMOUNT (USD)").font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                    TextField("e.g. 2150", text: $store.counterAmount)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                Button {
                    if let v = Double(store.counterAmount), v > 0,
                       case .loaded(let rows) = store.phase,
                       let parent = rows.last(where: { ($0.status ?? "").lowercased() == "pending" }) {
                        Task {
                            await store.counter(parentBidId: parent.id, amount: v)
                            showCounterSheet = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.working {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .heavy))
                        }
                        Text(store.working ? "Sending…" : "Send counter").font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.working || (Double(store.counterAmount) ?? 0) <= 0)
            }
            .padding(.horizontal, 14).padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    // MARK: - resolution

    enum Resolution {
        case driverPending(bidId: Int)
        case shipperCountered(bidId: Int, amount: String?)
        case terminal(label: String, color: Color)
    }

    private func resolution(for rows: [LoadBiddingAPI.ChainRow]) -> Resolution? {
        // Find the LATEST row whose status is pending. Whoever placed
        // it owns the next move.
        guard let latest = rows.last(where: { ($0.status ?? "").lowercased() == "pending" }) else {
            // Chain is closed — pick the terminal row's status for display.
            if let last = rows.last {
                let s = (last.status ?? "").lowercased()
                if s == "accepted" || s == "auto_accepted" { return .terminal(label: "Accepted", color: Brand.success) }
                if s == "rejected"  { return .terminal(label: "Rejected", color: Brand.danger) }
                if s == "withdrawn" { return .terminal(label: "Withdrawn", color: Brand.neutral) }
                if s == "expired"   { return .terminal(label: "Expired", color: Brand.neutral) }
                if s == "countered" { return .terminal(label: "Countered (out)", color: Brand.info) }
            }
            return nil
        }
        let role = (latest.bidderRole ?? "").lowercased()
        if role == "driver" || role == "catalyst" {
            // The driver's own bid is still pending — the OTHER side
            // owes a response. Driver can withdraw.
            return .driverPending(bidId: latest.id)
        } else {
            // The shipper / broker has the pending move on the
            // counter offer — driver decides Accept / Counter /
            // Withdraw.
            return .shipperCountered(bidId: latest.id, amount: latest.bidAmount)
        }
    }

    // MARK: - empty / error

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No bids on this load").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Place the first bid from the load detail sheet to start a chain.")
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
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - helpers

    private func amountLabel(_ raw: String?) -> String {
        guard let r = raw, let v = Double(r) else { return "$—" }
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
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
            if abs < 60 { return "just now" }
            if abs < 3600 { return "\(Int(abs/60))m ago" }
            if abs < 86400 { return "\(Int(abs/3600))h ago" }
            return "\(Int(abs/86400))d ago"
        }
    }
}

// MARK: - status

private struct ChainStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> ChainStatusStyle {
        switch (raw ?? "").lowercased() {
        case "pending":         return .init(label: "Pending",   color: Brand.warning)
        case "accepted":        return .init(label: "Accepted",  color: Brand.success)
        case "auto_accepted":   return .init(label: "Auto-won",  color: Brand.success)
        case "countered":       return .init(label: "Countered", color: Brand.info)
        case "rejected":        return .init(label: "Rejected",  color: Brand.danger)
        case "withdrawn":       return .init(label: "Withdrawn", color: Brand.neutral)
        case "expired":         return .init(label: "Expired",   color: Brand.neutral)
        default:                return .init(label: (raw ?? "?").capitalized, color: Brand.neutral)
        }
    }
}

// MARK: - Screen wrapper

struct MeBidDetailScreen: View {
    let theme: Theme.Palette
    let loadId: Int

    init(theme: Theme.Palette, loadId: Int = 0) {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            MeBidDetailView(loadId: loadId)
        } nav: {
            BottomNav(
                leading: driverNavLeading_109(),
                trailing: driverNavTrailing_109(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_109() -> [NavSlot] {
    [NavSlot(label: "Home", systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul", systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_109() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("109 · Me · Bid Detail · Night") {
    MeBidDetailScreen(theme: Theme.dark, loadId: 0)
        .preferredColorScheme(.dark)
}

#Preview("109 · Me · Bid Detail · Afternoon") {
    MeBidDetailScreen(theme: Theme.light, loadId: 0)
        .preferredColorScheme(.light)
}
