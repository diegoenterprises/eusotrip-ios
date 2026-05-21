//
//  242_ShipperAwardedConfirmation.swift
//  EusoTrip — Shipper · Awarded Confirmation (brick 242).
//
//  Pixel-match to `02 Shipper/Dark-SVG/242 Shipper Awarded Confirmation.svg`.
//  Post-accept forward-flip — counter accepted, ME assigned, booked.
//
//  Wire bindings:
//    loads.getById(loadId)           — load context post-award
//    loadBidding.getBidChain(loadId) — final accepted bid
//

import SwiftUI

private struct AwardedLoad: Decodable, Hashable {
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
    let pickupDate: String?
    let assignedDriverName: String?
    let carrierName: String?
    let acceptedAt: String?
}

private struct AcceptedBid: Decodable, Hashable {
    let amount: String?
    let carrierName: String?
    let carrierContactName: String?
    let dotNumber: String?
    let mcNumber: String?
    let acceptedAt: String?
}

struct ShipperAwardedConfirmationScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { AwardedBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Post",  systemImage: "plus.rectangle",   isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AwardedBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: AwardedLoad?
    @State private var bid: AcceptedBid?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading award…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    contextBanner
                    if let b = bid { carrierCard(b) }
                    kpiGrid
                    timelineRow
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
                Text("SHIPPER · LOADS · AWARDED · CONFIRMATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Counter accepted").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load, let b = bid {
                Text("AWARDED $\(b.amount ?? l.rate ?? "—") · ETA \(etaText) · BOOKED \(timeAgo(b.acceptedAt ?? l.acceptedAt))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var contextBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§11.4 AWARDED · POST-ACCEPT FORWARD FLIP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—") · ACCEPTED")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func carrierCard(_ b: AcceptedBid) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(b.carrierContactName)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.carrierName ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let n = b.carrierContactName { Text(n).font(.caption).foregroundStyle(palette.textSecondary) }
                    if let dot = b.dotNumber, let mc = b.mcNumber {
                        Text("USDOT \(dot) · MC-\(mc)").font(.caption.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                Text("AWARDED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundStyle(Color.green)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let rpm: String = {
            guard let amt = Double(bid?.amount ?? load?.rate ?? "0"), amt > 0,
                  let mi = load?.distance, mi > 0 else { return "—" }
            return String(format: "$%.2f", amt / mi)
        }()
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("AWARDED",    "$\(bid?.amount ?? load?.rate ?? "—")", "to carrier", .green)
            kpi("ETA-PICKUP", etaText, "pickup window", .blue)
            kpi("BOOKED",     timeAgo(bid?.acceptedAt ?? load?.acceptedAt), "ago · NET-30", .green)
            kpi("RPM",        rpm, "per mile", .blue)
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

    private var timelineRow: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("FORWARD FLIP · NEXT STAGES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Pickup → Loading → BOL signing → In transit → Delivery → POD → Settlement")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var etaText: String {
        guard let pd = load?.pickupDate, let date = ISO8601DateFormatter().date(from: pd) else { return "—" }
        let mins = Int(date.timeIntervalSinceNow / 60)
        if mins < 0 { return "in window" }
        let h = mins / 60
        return "\(h)h \(mins % 60)m"
    }

    private func timeAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        if mins < 1 { return "0:01" }
        return "0:\(String(format: "%02d", mins))"
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    private func loadAll() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let b: Void = loadBid()
        _ = await (l, b)
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadBid() async {
        struct In: Encodable { let loadId: String }
        struct Env: Decodable { let bids: [AcceptedBid]? }
        do {
            let r: Env = try await EusoTripAPI.shared.query("loadBidding.getBidChain", input: In(loadId: loadId))
            bid = r.bids?.last
        } catch { /* */ }
    }
}

#Preview("242 · Dark")  { ShipperAwardedConfirmationScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("242 · Light") { ShipperAwardedConfirmationScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
