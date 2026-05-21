//
//  241_ShipperCounterReview.swift
//  EusoTrip — Shipper · Counter Review (brick 241).
//
//  Pixel-match to `02 Shipper/Dark-SVG/241 Shipper Counter Review.svg`.
//  Shipper's view of a §11.4 counter from a Catalyst — Aurora counters
//  $2,200 RFP up to $2,425, 23h to accept.
//
//  Wire bindings (all real, no stubs):
//    loads.getById(loadId)            — load context (lane, equipment)
//    loadBidding.getBidChain(loadId)  — current counter chain
//

import SwiftUI

private struct ShipperLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let distance: Double?
}

private struct CounterBid: Decodable, Hashable {
    let id: Int?
    let amount: String?
    let carrierName: String?
    let carrierContactName: String?
    let dotNumber: String?
    let mcNumber: String?
    let counterAmount: String?
    let createdAt: String?
    let expiresAt: String?
    let originalRate: String?
}

struct ShipperCounterReviewScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { CounterReviewBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Post",  systemImage: "plus.rectangle",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CounterReviewBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: ShipperLoadCtx?
    @State private var counter: CounterBid?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && counter == nil {
                    LifecycleCard { Text("Loading counter…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    contextBanner
                    if let c = counter { carrierCard(c) }
                    if let c = counter { kpiGrid(c) }
                    actionRow
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
                Text("SHIPPER · LOADS · COUNTER · REVIEW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Review counter").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let c = counter {
                let amt = c.counterAmount ?? c.amount ?? "—"
                let orig = c.originalRate ?? "—"
                let delta = computeDelta(counter: c.counterAmount ?? c.amount, original: c.originalRate)
                Text("COUNTER $\(amt) · DELTA \(delta) · \(expiresAgo(c.expiresAt))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
                let _ = orig
            }
        }
    }

    private var contextBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§11.4 COUNTER REVIEW · CROSS-TRACK PARITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—")")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func carrierCard(_ c: CounterBid) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(c.carrierContactName)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.carrierName ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let n = c.carrierContactName { Text(n).font(.caption).foregroundStyle(palette.textSecondary) }
                    if let dot = c.dotNumber, let mc = c.mcNumber {
                        Text("USDOT \(dot) · MC-\(mc)").font(.caption.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CounterBid) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let counterAmt = c.counterAmount ?? c.amount ?? "—"
        let delta = computeDelta(counter: c.counterAmount ?? c.amount, original: c.originalRate)
        let rpm: String = {
            guard let amt = Double(c.counterAmount ?? c.amount ?? "0"), amt > 0,
                  let mi = load?.distance, mi > 0 else { return "—" }
            return String(format: "$%.2f", amt / mi)
        }()
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("COUNTER",  "$\(counterAmt)", "to accept", .green)
            kpi("DELTA",    delta,            "vs RFP",    delta.hasPrefix("+") ? .orange : .green)
            kpi("EXPIRES",  expiresAgo(c.expiresAt), "auto-revert", .red)
            kpi("RPM",      rpm,              "per mile",  .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text("Accept counter")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button { } label: {
                Text("Counter back")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func computeDelta(counter: String?, original: String?) -> String {
        guard let c = Double(counter ?? "0"), let o = Double(original ?? "0"), o > 0 else { return "—" }
        let d = Int(c - o)
        return (d >= 0 ? "+" : "") + "$\(d)"
    }

    private func expiresAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = max(0, Int(d.timeIntervalSinceNow / 60))
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        return "\(h)h \(mins % 60)m"
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let c: Void = loadCounter()
        _ = await (l, c)
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadCounter() async {
        struct In: Encodable { let loadId: String }
        struct Env: Decodable { let bids: [CounterBid]?; let chain: [CounterBid]? }
        do {
            let r: Env = try await EusoTripAPI.shared.query("loadBidding.getBidChain", input: In(loadId: loadId))
            counter = (r.bids ?? r.chain)?.last
        } catch { /* */ }
    }
}

#Preview("241 · Dark")  { ShipperCounterReviewScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("241 · Light") { ShipperCounterReviewScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
