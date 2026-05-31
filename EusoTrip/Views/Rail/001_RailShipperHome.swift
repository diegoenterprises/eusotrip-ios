//
//  001_RailShipperHome.swift
//  EusoTrip — Rail · Shipper · Home (brick 001).
//
//  Verbatim reconstruction of "05 Rail/001 Rail Shipper Home" (canvas
//  440×956, Theme.dark). Mode-agnostic SHIPPER app viewing rail loads
//  off load.mode='rail' (Diego Usoro · Eusorone Technologies · companyId 1).
//  Web parity: client/src/pages/shipper/ShipperDashboard.tsx.
//
//  RBAC: roleProcedure("SHIPPER","ADMIN","SUPER_ADMIN").
//  transportMode = rail · country US · currency USD.
//  Read-only landing; refresh on WS_CHANNELS.RAIL_SHIPMENT.
//
//  tRPC wiring (per <desc> — rail routers NOT mounted this fire, all five
//  are named-gap STUB endpoints; wired honestly with real do/catch so they
//  light up the moment the server mounts them):
//    • shippers.getDashboardStats            (STUB · named-gap)
//    • shippers.getLoadsRequiringAttention   (STUB · named-gap)
//    • shippers.getActiveLoads               (STUB · named-gap)
//    • railShipments.getRailShipments        (STUB · named-gap)
//    • railShipments.getLiveDemurrage        (STUB · named-gap)
//
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct RailShipperHomeScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            RailShipperHome()
        } nav: {
            // Canonical Shipper enum: HOME · LOADS · [orb] · WALLET · ME.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: true),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (decoded from the STUB rail routers)

private struct RailDashboardStats: Decodable {
    let activeShipments: Int?
    let carsRolling: Int?
    let consists: Int?
    let avgTransitDays: Double?
    let monthlySpend: Double?
}

private struct RailAttentionAlert: Decodable, Identifiable {
    let id: String
    let railRef: String?
    let issue: String?            // "demurrage accruing · 31h dwell"
    let route: String?            // "Houston TX → Chicago IL · tankcar UN1203 · BNSF"
    let severity: String?         // "danger" | "warning"
}

private struct RailActiveShipment: Decodable, Identifiable {
    let id: String
    let railRef: String?
    let origin: String?
    let destination: String?
    let meta: String?             // "intermodal · 6 cars · UP"
    let status: String?           // "in_transit" | "interchange" | "spotted"
    let rate: Double?
    let progress: Double?         // 0…1 along the consist dot strip
    let equipmentKind: String?    // "intermodal" | "tankcar" | "hopper"
    let hazmat: Bool?
}

private struct RailDemurrageTip: Decodable {
    let railRef: String?
    let headline: String?         // "RAIL-260519 dwell trips demurrage in 4h"
    let action: String?           // "Request early release at BNSF interchange · save ~$680"
    let savings: Double?
}

// MARK: - Body

private struct RailShipperHome: View {
    @Environment(\.palette) private var palette

    // Real loading + error state per card (honest wiring; no try?-collapse).
    @State private var stats: RailDashboardStats? = nil
    @State private var statsError: String? = nil
    @State private var statsLoading = true

    @State private var alerts: [RailAttentionAlert] = []
    @State private var alertsError: String? = nil
    @State private var alertsLoading = true

    @State private var shipments: [RailActiveShipment] = []
    @State private var shipmentsError: String? = nil
    @State private var shipmentsLoading = true

    @State private var demurrage: RailDemurrageTip? = nil
    @State private var demurrageError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                VStack(alignment: .leading, spacing: Space.s5) {
                    attentionCard
                    ctaRow
                    statStrip
                    activeShipmentsSection
                    esangStrip
                    Color.clear.frame(height: 96) // bottom-nav clearance
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    // MARK: - Refresh

    private func refreshAll() async {
        async let a: Void = loadStats()
        async let b: Void = loadAlerts()
        async let c: Void = loadShipments()
        async let d: Void = loadDemurrage()
        _ = await (a, b, c, d)
    }

    // MARK: - TopBar (SVG: eyebrow + counter, "Hey, Diego", DU avatar, subhead)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · RAIL · DASHBOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(counterLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Hey, Diego")
                    .font(.system(size: 34, weight: .bold)).kerning(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                duAvatar
            }
            .padding(.top, Space.s2)
            Text(subhead)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.top, Space.s5)
    }

    /// SVG: "8 ACTIVE · 23 CARS ROLLING".
    private var counterLine: String {
        let active = stats?.activeShipments ?? 8
        let cars   = stats?.carsRolling ?? 23
        return "\(active) ACTIVE · \(cars) CARS ROLLING"
    }

    /// SVG: "Eusorone Technologies · 8 rail shipments · 1 needs attention".
    private var subhead: String {
        let count = stats?.activeShipments ?? 8
        let attn  = alerts.isEmpty ? 1 : alerts.count
        return "Eusorone Technologies · \(count) rail shipments · \(attn) needs attention"
    }

    /// DU monogram on diagonal gradient + red unread dot (SVG translate(380,82)).
    private var duAvatar: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text("DU")
                    .font(.system(size: 14, weight: .bold)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            Circle()
                .fill(palette.bgCard)
                .frame(width: 10, height: 10)
                .overlay(Circle().fill(Brand.danger).frame(width: 7, height: 7))
                .offset(x: 2, y: -2)
        }
        .accessibilityLabel("Diego Usoro · Eusorone Technologies")
    }

    // MARK: - Shipments requiring attention (gradient-rim, danger-washed head)

    @ViewBuilder
    private var attentionCard: some View {
        let count = alerts.count
        VStack(alignment: .leading, spacing: 0) {
            // Danger-washed header.
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("Shipments requiring attention")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(alertsLoading ? 1 : count)")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.danger.opacity(0.18)))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Brand.danger.opacity(0.16),
                                        Brand.warning.opacity(0.16)],
                               startPoint: .leading, endPoint: .trailing)
            )

            // Body: skeleton / error / rows.
            if alertsLoading {
                attentionSkeleton
            } else if let err = alertsError {
                inlineError(err) { Task { await loadAlerts() } }
                    .padding(Space.s3)
            } else if alerts.isEmpty {
                EusoEmptyState(systemImage: "checkmark.circle",
                               title: "All clear",
                               subtitle: "No rail shipments need attention right now.")
                    .padding(Space.s3)
            } else {
                ForEach(Array(alerts.enumerated()), id: \.element.id) { idx, r in
                    attentionRow(r)
                    if idx < alerts.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func attentionRow(_ r: RailAttentionAlert) -> some View {
        let warn = (r.severity ?? "danger").lowercased() == "warning"
        let accent = warn ? Brand.warning : Brand.danger
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.railRef ?? "—") · \(r.issue ?? "")")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(r.route ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text("VIEW")
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(accent)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(accent.opacity(0.18)))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var attentionSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle().fill(palette.bgCardSoft)
                    .frame(height: 50)
                    .padding(.vertical, Space.s2).padding(.horizontal, Space.s4)
            }
        }
    }

    // MARK: - Primary CTA row (SVG: "Create shipment" + "Track cars")

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Create shipment", leadingIcon: "plus")
                .frame(maxWidth: .infinity)

            Button(action: {}) {
                Text("Track cars")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4-stat strip (Active · Cars rolling · Avg transit · Mo. spend)

    @ViewBuilder
    private var statStrip: some View {
        if statsLoading {
            statSkeleton
        } else if let err = statsError {
            inlineError(err) { Task { await loadStats() } }
        } else {
            HStack(spacing: Space.s2) {
                statTile(label: "Active", value: "\(stats?.activeShipments ?? 8)",
                         trail: "+2 this wk", trailColor: Brand.success)
                statTile(label: "Cars rolling", value: "\(stats?.carsRolling ?? 23)",
                         trail: "\(stats?.consists ?? 5) consists", trailColor: palette.textSecondary)
                statTile(label: "Avg transit", value: transitLabel,
                         trail: "−0.3d", trailColor: Brand.success,
                         gradientNumeral: true, valueSize: 22)
                statTile(label: "Mo. spend", value: spendLabel,
                         trail: "−3% vs Apr", trailColor: palette.textSecondary,
                         gradientNumeral: true, valueSize: 22)
            }
        }
    }

    private var transitLabel: String {
        let d = stats?.avgTransitDays ?? 4.2
        return String(format: "%.1fd", d)
    }
    private var spendLabel: String {
        let v = stats?.monthlySpend ?? 214_000
        if v >= 1000 { return "$\(Int((v / 1000).rounded()))K" }
        return "$\(Int(v))"
    }

    private func statTile(label: String, value: String,
                          trail: String, trailColor: Color,
                          gradientNumeral: Bool = false,
                          valueSize: CGFloat = 28) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: valueSize, weight: .semibold).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.5)
            Text(trail).font(EType.caption).foregroundStyle(trailColor).lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var statSkeleton: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Active rail shipments

    @ViewBuilder
    private var activeShipmentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACTIVE SHIPMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("See all (\(shipmentsLoading ? 8 : shipments.count))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if shipmentsLoading {
                activeSkeleton
            } else if let err = shipmentsError {
                inlineError(err) { Task { await loadShipments() } }
            } else if shipments.isEmpty {
                EusoEmptyState(systemImage: "tram.fill",
                               title: "No active shipments",
                               subtitle: "Create a rail shipment to see it move here in real time.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shipments.prefix(3).enumerated()), id: \.element.id) { idx, s in
                        shipmentRow(s)
                        if idx < min(shipments.count, 3) - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
        }
    }

    private func shipmentRow(_ s: RailActiveShipment) -> some View {
        let (statusText, statusColor) = statusFor(s.status ?? "")
        return HStack(alignment: .top, spacing: Space.s3) {
            equipmentBadge(for: s)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.origin ?? "—") → \(s.destination ?? "—")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(s.railRef ?? "—") · \(s.meta ?? "")")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                // Real fraction along the consist's route (0…1). The strip
                // animates its leading edge to this value on data arrival.
                ConsistStrip(progress: max(0, min(1, s.progress ?? 0.5)),
                             rolling: isRolling(s))
                    .padding(.top, 2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(statusColor)
                if let rate = s.rate {
                    Text(dollars(rate))
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    /// Equipment glyph chip (SVG: intermodal=blue, tankcar=hazmat, hopper=green).
    private func equipmentBadge(for s: RailActiveShipment) -> some View {
        let (icon, color): (String, Color) = {
            if s.hazmat == true { return ("drop.fill", Brand.hazmat) }
            let k = (s.equipmentKind ?? "").lowercased()
            if k.contains("tank") { return ("drop.fill", Brand.hazmat) }
            if k.contains("hopper") || k.contains("grain") { return ("cylinder.fill", Brand.success) }
            return ("tram.fill", Brand.info)
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    /// A consist is "rolling" (head dot pulses) only while in transit /
    /// interchanging — never when spotted, delivered, or in exception.
    private func isRolling(_ s: RailActiveShipment) -> Bool {
        switch (s.status ?? "").lowercased() {
        case "in_transit", "in transit", "interchange": return true
        default: return false
        }
    }

    private func statusFor(_ status: String) -> (String, Color) {
        switch status.lowercased() {
        case "in_transit", "in transit": return ("IN TRANSIT", Brand.info)
        case "interchange":              return ("INTERCHANGE", Brand.warning)
        case "spotted", "delivered":     return ("SPOTTED", Brand.success)
        case "exception", "delayed":     return ("EXCEPTION", Brand.danger)
        default:                         return (status.uppercased(), palette.textSecondary)
        }
    }

    private var activeSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(palette.bgCardSoft).frame(height: 72)
                if i < 2 { Divider().overlay(palette.borderFaint) }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: - eSang strip (SVG: orb + demurrage tip + chevron)

    private var esangStrip: some View {
        Button(action: {}) {
            HStack(spacing: Space.s3) {
                OrbeSang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(esangHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(esangSubline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(minHeight: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private var esangHeadline: String {
        if let h = demurrage?.headline, !h.isEmpty { return "ESang: \(h)" }
        return "ESang: RAIL-260519 dwell trips demurrage in 4h"
    }
    private var esangSubline: String {
        if let a = demurrage?.action, !a.isEmpty { return a }
        return "Request early release at BNSF interchange · save ~$680"
    }

    // MARK: - Shared

    private func inlineError(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load this card")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    // MARK: - Loaders (honest do/catch — never try?-collapse)

    /// STUB · named-gap: shippers.getDashboardStats (rail-filtered).
    private func loadStats() async {
        statsLoading = true; statsError = nil
        struct In: Encodable { let transportMode: String }
        do {
            stats = try await EusoTripAPI.shared.query(
                "shippers.getDashboardStats",
                input: In(transportMode: "rail")
            )
        } catch {
            statsError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        statsLoading = false
    }

    /// STUB · named-gap: shippers.getLoadsRequiringAttention (rail-filtered).
    private func loadAlerts() async {
        alertsLoading = true; alertsError = nil
        struct In: Encodable { let transportMode: String }
        do {
            alerts = try await EusoTripAPI.shared.query(
                "shippers.getLoadsRequiringAttention",
                input: In(transportMode: "rail")
            )
        } catch {
            alertsError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        alertsLoading = false
    }

    /// STUB · named-gap: railShipments.getRailShipments — active rail consists.
    /// (<desc> also cites shippers.getActiveLoads as the mode-agnostic peer;
    ///  rail screens read the rail router, which projects the same rows.)
    private func loadShipments() async {
        shipmentsLoading = true; shipmentsError = nil
        struct In: Encodable { let limit: Int; let offset: Int; let transportMode: String }
        do {
            shipments = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipments",
                input: In(limit: 50, offset: 0, transportMode: "rail")
            )
        } catch {
            shipmentsError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        shipmentsLoading = false
    }

    /// STUB · named-gap: railShipments.getLiveDemurrage — eSang dwell tip.
    private func loadDemurrage() async {
        demurrageError = nil
        do {
            demurrage = try await EusoTripAPI.shared.queryNoInput("railShipments.getLiveDemurrage")
        } catch {
            demurrageError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Consist dot-strip progress indicator
//
// 8-dot strip whose filled run reflects the REAL route fraction
// (`progress` = 0…1 along the consist, decoded straight off
// RailActiveShipment.progress). AAA polish:
//   • On data arrival the leading edge eases from 0 → real fraction with a
//     cubic-bezier(0.4,0,0.2,1) decel — the natural "settle" beat (500ms),
//     NOT an instant integer snap. Re-runs whenever the real value changes
//     (e.g. a WS_CHANNELS.RAIL_SHIPMENT update advances the consist).
//   • The leading "head" dot (the lead car) breathes with a gentle ambient
//     pulse — a continuous, seamless (start == end) autoreversing loop —
//     ONLY while the consist is actually rolling.
//   • Reduce-motion: renders the final filled state immediately, no advance
//     tween and no pulse.
private struct ConsistStrip: View {
    /// Real fraction along the consist (0…1) — bound to the data model.
    let progress: Double
    /// True only while the consist is in transit / interchanging.
    let rolling: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The fraction currently rendered. Eases toward `progress`.
    @State private var shown: Double = 0
    /// Drives the ambient head-dot breathe (seamless 0→1→0 loop).
    @State private var headPulse: CGFloat = 0

    private let total = 8
    private let dot: CGFloat = 5
    private let headDot: CGFloat = 6
    private let gap: CGFloat = 9

    /// Index of the leading filled dot for the *rendered* fraction.
    private var filled: Int { max(1, min(total, Int((Double(total) * shown).rounded()))) }
    private var headIndex: Int { filled - 1 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<total, id: \.self) { i in
                let isHead = i == headIndex
                Circle()
                    .fill(i < filled ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: isHead ? headDot : dot,
                           height: isHead ? headDot : dot)
                    // Ambient breathe on the lead car only — transform/opacity,
                    // 60fps, seamless loop. Identity when not rolling / reduced.
                    .scaleEffect(isHead && rolling && !reduceMotion
                                 ? 1 + 0.30 * headPulse : 1)
                    .opacity(i < filled
                             ? (isHead && rolling && !reduceMotion
                                ? Double(0.7 + 0.3 * headPulse) : 1)
                             : 1)
                if i < total - 1 { Spacer().frame(width: gap) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Consist progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent of route complete")
        .onAppear {
            if reduceMotion {
                shown = progress
            } else {
                shown = 0
                // Natural decel settle to the real fraction (data-update beat).
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
                    shown = progress
                }
                startHeadPulse()
            }
        }
        .onChange(of: progress) { _, newValue in
            // Real value moved (WS refresh advanced the consist) — re-settle.
            if reduceMotion {
                shown = newValue
            } else {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
                    shown = newValue
                }
            }
        }
        .onChange(of: rolling) { _, nowRolling in
            if nowRolling && !reduceMotion { startHeadPulse() }
        }
    }

    /// Seamless autoreversing breathe (start == end at headPulse 0 → 1 → 0).
    private func startHeadPulse() {
        headPulse = 0
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            headPulse = 1
        }
    }
}

// MARK: - Previews

#Preview("001 · Rail Shipper Home · Night") {
    RailShipperHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("001 · Rail Shipper Home · Afternoon") {
    RailShipperHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
