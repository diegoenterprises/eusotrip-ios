//
//  652_RailClaimsDashboard.swift
//  EusoTrip — Rail Engineer · Claims Dashboard (carrier-side intermodal-parity).
//
//  Verbatim port of "05 Rail / 652 Rail Claims Dashboard" (Dark).
//  Flagship DETAIL grammar: back-chevron + eyebrow + mono caption + title
//  28/-0.4; gradient-rimmed hero ActiveCard with lead figure + progress;
//  3-cell KPI strip (cell-1 eusoDiagonal); itemized "BY TYPE" ListRow stack
//  (40x40 icon chip + title + mono sub + short status pill + right tabular
//  value); claims-feed context strip; CTA pair.
//
//  Carrier BNSF Intermodal · shipper-of-record Eusorone Technologies (DU).
//  Pure-rail so no driver-anchor (ME) disc. CARRIER-SIDE.
//
//  Live wiring (grep-confirmed, frontend/server/routers/freightClaims.ts):
//    freightClaims.getClaimsDashboard  (ts:75)  → counters + recentClaims
//    freightClaims.getClaims           (ts:172) → claims feed
//    freightClaims.fileClaim           (ts:332) → File claim CTA
//  iOS namespace: EusoTripAPI.shared.shipperFreightClaims (richest Dashboard
//  shape — carries recentClaims used to derive the BY-TYPE breakdown).
//

import SwiftUI

struct RailClaimsDashboardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimsDashboardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailClaimsDashboardBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: ShipperFreightClaimsAPI.Dashboard? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived

    /// Open-claims exposure dollar figure. Server returns `totalValue` as the
    /// open-claims exposure on the dashboard hero.
    private var exposure: Double { dashboard?.totalValue ?? 0 }

    private var openCount: Int { dashboard?.open ?? 0 }

    /// "Escalated" = recent claims whose severity reads critical / high /
    /// escalated. Derived from the live `recentClaims` payload — never
    /// fabricated; absent severity simply contributes 0.
    private var escalatedCount: Int {
        (dashboard?.recentClaims ?? []).filter { row in
            guard let s = row.severity?.lowercased() else { return false }
            return s == "critical" || s == "high" || s == "escalated"
        }.count
    }

    /// Total claim count surfaced in the hero + feed caption. Prefer the
    /// summed lifecycle counters; the feed line reads "N claims".
    private var totalClaims: Int {
        guard let d = dashboard else { return 0 }
        return d.open + d.pending + d.resolved + d.denied
    }

    /// Progress fraction for the hero bar — open / total. Empty when no data.
    private var openFraction: Double {
        let total = totalClaims
        guard total > 0 else { return 0 }
        return min(1.0, Double(openCount) / Double(total))
    }

    /// One aggregated "BY TYPE" bucket, derived LIVE from `recentClaims`.
    private struct TypeBucket: Identifiable {
        let id: String          // lowercased type key
        let label: String       // display label (Damage / Shortage / …)
        let count: Int
        let total: Double       // summed amount for this type
        let avg: Double         // average amount
        let status: String      // representative status of the bucket
    }

    /// Group the live recent claims by type, summing exposure. Plots ONLY
    /// real data — an absent series yields an empty section (no fabrication).
    private var typeBuckets: [TypeBucket] {
        let rows = dashboard?.recentClaims ?? []
        guard !rows.isEmpty else { return [] }

        // Preserve first-seen order so the stack reads stably.
        var order: [String] = []
        var grouped: [String: [ShipperFreightClaimsAPI.ClaimRow]] = [:]
        for r in rows {
            let key = (r.type.isEmpty ? "other" : r.type).lowercased()
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(r)
        }

        return order.compactMap { key -> TypeBucket? in
            guard let group = grouped[key], !group.isEmpty else { return nil }
            let total = group.reduce(into: 0.0) { $0 += $1.amount }
            let count = group.count
            let avg = count > 0 ? total / Double(count) : 0
            // Representative status: the most "active" status in the bucket.
            let status = representativeStatus(group)
            return TypeBucket(
                id: key,
                label: displayLabel(forType: key),
                count: count,
                total: total,
                avg: avg,
                status: status
            )
        }
    }

    private func representativeStatus(_ group: [ShipperFreightClaimsAPI.ClaimRow]) -> String {
        // Priority ladder mirrors claim lifecycle severity.
        let ladder = ["review", "escalated", "pending", "open", "filed", "investigating"]
        let statuses = group.map { $0.status.lowercased() }
        for rung in ladder where statuses.contains(rung) {
            return rung
        }
        return group.first?.status ?? "filed"
    }

    private func displayLabel(forType key: String) -> String {
        switch key {
        case "damage":        return "Damage"
        case "shortage":      return "Shortage"
        case "delay":         return "Delay"
        case "loss":          return "Loss"
        case "contamination": return "Contamination"
        default:              return key.prefix(1).uppercased() + key.dropFirst()
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    kpiStrip
                    byTypeCard
                    claimsFeedStrip
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (eyebrow + back-chevron + title + sync)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: gradient sparkle title left · mono "OPEN" right.
            HStack {
                Text("✦ RAIL ENGINEER · CLAIMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("OPEN")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s4)

            // Back-chevron + title block · right-aligned carrier + sync.
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 6)

                Text("Claims dashboard")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("BNSF")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 5m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Status pills row.
                HStack(spacing: Space.s2) {
                    Text("live")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    Text("\(escalatedCount) escalated")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Brand.danger.opacity(0.18)).clipShape(Capsule())
                    Spacer(minLength: 0)
                }

                // Lead figure + label · right OPEN counter.
                HStack(alignment: .top, spacing: Space.s3) {
                    Text(currency(exposure))
                        .font(.system(size: 26, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("open claims exposure")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(totalClaims) claims · \(escalatedCount) escalated")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 4)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("OPEN")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(openCount)")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0xFF6B5E))
                    }
                }

                // Progress bar (open / total).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * openFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (3-cell, cell-1 gradient)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // EXPOSURE — diagonal gradient cell.
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("EXPOSURE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(currencyCompact(exposure))
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "OPEN",      value: "\(openCount)",      accent: palette.textSecondary)
            kpiCell(label: "ESCALATED", value: "\(escalatedCount)", accent: Color(hex: 0xFF6B5E))
        }
    }

    private func kpiCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - BY TYPE card

    private var byTypeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BY TYPE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getClaimsDashboard:75")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                if typeBuckets.isEmpty {
                    EusoEmptyState(
                        systemImage: "chart.bar.doc.horizontal",
                        title: "No claims by type",
                        subtitle: "Claim breakdown by type will appear here once claims are filed."
                    )
                    .padding(.vertical, Space.s5)
                } else {
                    ForEach(Array(typeBuckets.enumerated()), id: \.element.id) { idx, bucket in
                        typeRow(bucket)
                        if idx < typeBuckets.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                        .padding(.top, Space.s3)
                    Text("+ 9-step workflow per claim · investigator assigned on escalation")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func typeRow(_ bucket: TypeBucket) -> some View {
        let accent = accentColor(forType: bucket.id)
        return HStack(spacing: Space.s3) {
            // 40x40 icon chip.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName(forType: bucket.id))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(bucket.count) claims · avg \(currencyCompact(bucket.avg))")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 6) {
                shortStatusPill(bucket.status, accent: accent)
                Text(currency(bucket.total))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(accent)
            }
        }
    }

    private func shortStatusPill(_ status: String, accent: Color) -> some View {
        Text(status.uppercased())
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(accent)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(accent.opacity(0.18)).clipShape(Capsule())
    }

    private func accentColor(forType key: String) -> Color {
        switch key {
        case "damage":   return Color(hex: 0xFF6B5E)   // danger-bright
        case "shortage": return Color(hex: 0xFFB74D)   // warning-bright
        case "delay":    return Color(hex: 0x5BB0F5)   // info-bright
        case "loss":     return Color(hex: 0xFF6B5E)
        default:         return palette.textSecondary
        }
    }

    private func iconName(forType key: String) -> String {
        switch key {
        case "damage":        return "exclamationmark.triangle"
        case "shortage":      return "rectangle.split.2x1"
        case "delay":         return "clock"
        case "loss":          return "xmark.bin"
        case "contamination": return "exclamationmark.triangle"
        default:              return "shippingbox"
        }
    }

    // MARK: - Claims feed context strip

    private var claimsFeedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CLAIMS FEED · getClaims")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalClaims) claims")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("real-time status · evidence + investigator per claim")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · shipper-of-record Eusorone Technologies (DU)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button(action: fileClaim) {
                Text("File claim")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: { /* All claims → 652 feed list (in-place) */ }) {
                Text("All claims")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
        }
    }

    // MARK: - Formatting

    private func currency(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? "$\(Int(v))"
    }

    private func currencyCompact(_ v: Double) -> String {
        let absV = abs(v)
        if absV >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if absV >= 1_000     { return String(format: "$%.1fK", v / 1_000) }
        return String(format: "$%.0f", v)
    }

    // MARK: - Actions

    private func fileClaim() {
        // File claim → freightClaims.fileClaim (ts:332). The full intake
        // (load id / type / amount / commodity / damage extent) is collected
        // on the dedicated File-Claim sheet; this CTA opens that flow.
        // PORT-GAP: file-claim intake sheet — fileClaim() mutation exists in
        // EusoTripAPI.shared.shipperFreightClaims (verify wiring once the
        // intake surface lands; no fabricated submit fired here).
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        do {
            let d = try await EusoTripAPI.shared.shipperFreightClaims.getClaimsDashboard()
            self.dashboard = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("652 · Rail Claims Dashboard · Night") {
    RailClaimsDashboardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("652 · Rail Claims Dashboard · Light") {
    RailClaimsDashboardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
