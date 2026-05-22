//
//  300_CatalystHome.swift
//  EusoTrip — Catalyst · owner-op Home (wireframe slot 300).
//
//  Twin of the wireframe at 03 Catalyst/Light-SVG/300 Catalyst Home.svg
//  + Dark-SVG counterpart. Sister surface to the dispatch/SpectraMatch
//  operator Home at slot 500 (CatalystHome) — this brick targets the
//  single-truck owner-op flow: one carrier, one driver, multiple
//  pending tenders, Drive-mode toggle so the same user can flip
//  between the dispatcher chrome (this surface) and the driver
//  chrome on the same assigned load.
//
//  Doctrine: every visible value binds to a real tRPC proc. No
//  scenario literals — the wireframe ships "Michael Eusorone /
//  Eusotrans LLC / Houston→Dallas / $1,900" to illustrate the
//  moment; production substitutes whichever profile + loads the
//  bound user owns and shows "—" while data resolves.
//
//  tRPC procs consumed (all real, verified against
//  frontend/server/routers/catalysts.ts):
//    · catalysts.getProfile        — company / fleet / DOT context
//    · catalysts.getDashboardStats — KPI rollup
//    · catalysts.getActiveLoads    — active haul card source
//    · catalysts.getAvailableLoads — pending tender queue source
//    · catalysts.submitBid         — Accept-tender commit verb
//

import SwiftUI

// MARK: - tRPC decode shapes

private struct CHProfile: Decodable, Hashable {
    let companyName: String?
    let dotNumber: String?
    let mcNumber: String?
    let tier: String?
    let fleetSize: Int?
}

private struct CHStats: Decodable, Hashable {
    let activeMatches: Int?
    let matchedThisWeek: Int?
    let deliveredThisWeek: Int?
    let onTimeRate: Double?
    let gmvThisWeek: Double?
    let avgFitScore: Double?
}

private struct CHLoad: Decodable, Hashable, Identifiable {
    let id: Int
    let loadNumber: String?
    let status: String?
    let rate: Double?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let pickupLocation: CHCityState?
    let deliveryLocation: CHCityState?
    let pickupDate: String?
    let hazmatClass: String?
    let unNumber: String?
    struct CHCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct CatalystOwnerOpHome: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CHBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                 isCurrent: true),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.stack.fill",  isCurrent: false)],
                trailing: [NavSlot(label: "Wallet",  systemImage: "creditcard.fill",       isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CHBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var profile: CHProfile?
    @State private var stats: CHStats?
    @State private var activeLoads: [CHLoad] = []
    @State private var availableLoads: [CHLoad] = []
    @State private var driveModeOn: Bool = false

    @State private var bidInFlight: Int?     // loadId of in-flight accept
    @State private var bidAck: String?
    @State private var bidErr: String?

    private var displayName: String {
        if let name = session.user?.name, !name.isEmpty { return name }
        return "—"
    }
    private var displayCompany: String { profile?.companyName ?? "—" }
    private var displayDot: String {
        let d = profile?.dotNumber ?? "—"
        let m = profile?.mcNumber
        if let m, !m.isEmpty { return "USDOT \(d) · MC-\(m)" }
        return "USDOT \(d)"
    }
    private var displayFleet: String {
        guard let n = profile?.fleetSize else { return "— truck" }
        return "\(n) truck\(n == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                driveModeRow
                kpiGrid
                activeHaulCard
                tenderQueueSection
                if let ack = bidAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = bidErr {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: header / drive-mode

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · HOME · \(displayCompany.uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Good morning, \(displayName)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("\(displayCompany) · \(displayDot) · \(displayFleet)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
        }
    }

    private var driveModeRow: some View {
        LifecycleCard(accentGradient: driveModeOn) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DRIVE MODE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(driveModeOn
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textTertiary))
                    Text(driveModeOn
                         ? "Driver chrome active · trips + ELD primary"
                         : "Dispatcher chrome · matches + tenders primary")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { driveModeOn.toggle() }
                } label: {
                    ZStack(alignment: driveModeOn ? .trailing : .leading) {
                        Capsule()
                            .fill(driveModeOn
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.bgCard))
                            .overlay(
                                Capsule().strokeBorder(driveModeOn ? Color.clear : palette.textTertiary.opacity(0.3), lineWidth: 1)
                            )
                            .frame(width: 52, height: 30)
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .padding(.horizontal, 3)
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: KPIs from getDashboardStats

    private var kpiGrid: some View {
        let active = stats?.activeMatches.map(String.init) ?? "—"
        let matched = stats?.matchedThisWeek.map(String.init) ?? "—"
        let onTime = stats?.onTimeRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
        let gmv = stats?.gmvThisWeek.map { Self.currency($0) } ?? "—"
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("ACTIVE",    active,  "matches running",   .blue),
            ("MATCHED",   matched, "this week",         .green),
            ("ON-TIME",   onTime,  "delivery rate",     .green),
            ("GMV",       gmv,     "this week",         .green),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    // MARK: Active haul (first row from getActiveLoads)

    private var activeHaulCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVE HAUL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 2)
            if let l = activeLoads.first {
                loadCard(l, role: .active)
            } else {
                LifecycleCard {
                    Text("No active haul — pick one from the tender queue below.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Tender queue (getAvailableLoads, top 3)

    private var tenderQueueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PENDING TENDERS · \(availableLoads.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 2)
            if availableLoads.isEmpty {
                LifecycleCard {
                    Text("No pending tenders — pull to refresh.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(availableLoads.prefix(3))) { l in
                        loadCard(l, role: .tender)
                    }
                }
            }
        }
    }

    // MARK: load card — used by both active + tender

    private enum LoadCardRole { case active, tender }

    private func loadCard(_ l: CHLoad, role: LoadCardRole) -> some View {
        LifecycleCard(accentGradient: role == .active) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(l.loadNumber ?? "LD-\(l.id)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(role == .active
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textPrimary))
                    if let haz = l.hazmatClass, !haz.isEmpty {
                        cargoChip(label: "HAZMAT · \(haz)", tint: .orange)
                    } else if let cargo = l.cargoType, !cargo.isEmpty {
                        cargoChip(label: cargo.uppercased(), tint: .blue)
                    }
                    Spacer()
                    if role == .active {
                        Text((l.status ?? "ASSIGNED").uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                Text(laneFor(l))
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                let metaParts: [String] = [
                    l.equipmentType,
                    l.distance.map { "\(Int($0.rounded())) mi" },
                    l.rate.map { Self.currency($0) },
                    l.unNumber.map { "UN\($0)" },
                ].compactMap { $0 }.filter { !$0.isEmpty }
                Text(metaParts.isEmpty ? "—" : metaParts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                if role == .tender {
                    acceptTenderButton(l)
                }
            }
        }
    }

    private func cargoChip(label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }

    private func laneFor(_ l: CHLoad) -> String {
        let p = [l.pickupLocation?.city, l.pickupLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let d = [l.deliveryLocation?.city, l.deliveryLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if p.isEmpty && d.isEmpty { return "—" }
        return "\(p.isEmpty ? "—" : p) → \(d.isEmpty ? "—" : d)"
    }

    private func acceptTenderButton(_ l: CHLoad) -> some View {
        let inFlight = bidInFlight == l.id
        return Button {
            Task { await acceptTender(l) }
        } label: {
            HStack(spacing: 6) {
                if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text(inFlight ? "Submitting…" : "Accept tender")
                    .font(EType.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(.white)
            .background(l.rate == nil
                        ? AnyShapeStyle(LinearGradient(colors: [palette.textTertiary, palette.textTertiary], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(LinearGradient.diagonal))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(inFlight || l.rate == nil)
    }

    // MARK: data

    private func refresh() async {
        async let p: Void = loadProfile()
        async let s: Void = loadStats()
        async let a: Void = loadActiveLoads()
        async let q: Void = loadAvailableLoads()
        _ = await (p, s, a, q)
    }

    private func loadProfile() async {
        do { profile = try await EusoTripAPI.shared.query("catalysts.getProfile", input: EmptyEncodable()) } catch { }
    }
    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.query("catalysts.getDashboardStats", input: EmptyEncodable()) } catch { }
    }
    private func loadActiveLoads() async {
        struct In: Encodable { let limit: Int }
        do { activeLoads = try await EusoTripAPI.shared.query("catalysts.getActiveLoads", input: In(limit: 5)) } catch { }
    }
    private func loadAvailableLoads() async {
        struct In: Encodable { let limit: Int }
        do { availableLoads = try await EusoTripAPI.shared.query("catalysts.getAvailableLoads", input: In(limit: 10)) } catch { }
    }

    private func acceptTender(_ l: CHLoad) async {
        guard let amount = l.rate else { return }
        bidInFlight = l.id; bidAck = nil; bidErr = nil
        defer { bidInFlight = nil }
        struct In: Encodable {
            let loadId: String
            let amount: Double
            let notes: String?
        }
        struct Out: Decodable {
            let bidId: String?
            let success: Bool?
            let message: String?
        }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "catalysts.submitBid",
                input: In(loadId: String(l.id), amount: amount, notes: nil)
            )
            let bidId = resp.bidId ?? "—"
            bidAck = "Tender accepted · bid \(bidId) submitted at \(Self.currency(amount)) for \(l.loadNumber ?? "LD-\(l.id)")."
            await refresh()
        } catch let e {
            bidErr = (e as? LocalizedError)?.errorDescription ?? "Accept failed: \(e)"
        }
    }

    private static func currency(_ amount: Double) -> String {
        let value = amount.rounded()
        return value < 1000 ? String(format: "$%.0f", value) : "$\(Int(value).formatted(.number))"
    }
}

// Helper for procs with no input.
private struct EmptyEncodable: Encodable {}

// MARK: - Previews

#Preview("300 Catalyst Home · Light") {
    CatalystOwnerOpHome(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("300 Catalyst Home · Dark") {
    CatalystOwnerOpHome(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
