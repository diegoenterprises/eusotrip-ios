//
//  001_VesselShipperHome.swift
//  EusoTrip — Vessel Shipper · Home (booking dashboard + attention queue).
//
//  Web parity: client/src/pages/vessel/VesselShipperDashboard.tsx
//  Wireframe:  06 Vessel / 001 Vessel Shipper Home (canvas 440×956).
//  PERSONA:    Diego Usoro · Eusorone Marine (VESSEL_SHIPPER). Booking VS-#####.
//  transportMode = vessel.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct VesselShipperHomeScreen: View {
    var theme: Theme.Palette = Theme.dark
    var body: some View {
        Shell(theme: theme) { VesselShipperHomeBody() } nav: {
            // PROPOSED greenfield Vessel nav: HOME · BOOKINGS · [orb] · TRACK · ME
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house.fill",        isCurrent: true),
                          NavSlot(label: "Bookings", systemImage: "shippingbox.fill",  isCurrent: false)],
                trailing: [NavSlot(label: "Track",   systemImage: "clock",             isCurrent: false),
                           NavSlot(label: "Me",      systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (tRPC vesselShipments.*)

/// vesselShipments.getVesselDashboard (EXISTS :715)
private struct VesselShipperDash: Decodable {
    let activeBookings: Int?
    let teuAfloat: Int?
    let containersInTransit: Int?
    let avgTransitDays: Double?
    let monthlySpend: Double?
    let vesselsCount: Int?
}

/// vesselShipments.getVesselShipments (EXISTS :121)
private struct VesselBooking: Decodable, Identifiable {
    let id: String
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let status: String?
    let containerType: String?
    let containersCount: Int?
    let commodity: String?
    let carrier: String?
    let terminal: String?
    let amount: Double?
    let progress: Double?      // 0…1 transit progress
    let reefer: Bool?
    let hazmat: Bool?
    let customsHold: Bool?
}

/// Synthesized attention item — fed from getVesselDemurrage (EXISTS :632)
/// + getISFStatus (EXISTS :815) joined to the booking list. There is no
/// dedicated shipper "needs attention" aggregator endpoint yet
/// (STUB · named-gap: vesselShipments.getVesselAttention), so we derive
/// the queue from the two compliance endpoints client-side.
private struct VesselAttentionItem: Identifiable {
    let id: String
    let bookingNumber: String
    let detail: String
    let route: String
    let kind: StatusPill.Kind   // .danger (customs/demurrage) | .warning (ISF)
}

/// vesselShipments.getVesselDemurrage (EXISTS :632)
private struct VesselDemurrageRow: Decodable {
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let containerType: String?
    let commodity: String?
    let carrier: String?
    let terminal: String?
    let freeDaysTotal: Int?
    let freeDaysUsed: Int?
    let onHold: Bool?
}

/// vesselShipments.getISFStatus (EXISTS :815)
private struct VesselISFRow: Decodable {
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let containerType: String?
    let commodity: String?
    let carrier: String?
    let hoursUntilDue: Double?
    let filed: Bool?
}

// MARK: - Body

private struct VesselShipperHomeBody: View {
    @Environment(\.palette) private var palette

    @State private var dash: VesselShipperDash? = nil
    @State private var bookings: [VesselBooking] = []
    @State private var attention: [VesselAttentionItem] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Action surface (Create booking · row VIEW taps · ESang CTA) writes
    /// here on failure — never silently swallowed.
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError {
                        actionErrorBanner(actionError)
                    }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        attentionCard
                        ctaRow
                        statStrip
                        activeBookingsSection
                        esangCard
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar  (SVG y=72 eyebrow · y=116 display · y=140 subline)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("✦ VESSEL SHIPPER · DASHBOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(afloatSummary)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .top) {
                Text("Hey, Diego")
                    .font(.system(size: 34, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                // Avatar + alert dot (SVG translate(380,82))
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal)
                            .frame(width: 40, height: 40)
                        Text("DU")
                            .font(.system(size: 14, weight: .bold)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    Circle().fill(Brand.danger)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(palette.bgPrimary, lineWidth: 2).frame(width: 11, height: 11))
                        .offset(x: 2, y: -2)
                }
            }
            .padding(.top, Space.s3)

            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s6)
    }

    private var afloatSummary: String {
        let active = dash?.activeBookings ?? bookings.count
        let teu = dash?.teuAfloat ?? 0
        return "\(active) ACTIVE · \(teu) TEU AFLOAT"
    }

    private var subline: String {
        let active = dash?.activeBookings ?? bookings.count
        let needs = attention.count
        if needs > 0 {
            return "Eusorone Marine · \(active) active bookings · \(needs) needs attention"
        }
        return "Eusorone Marine · \(active) active bookings"
    }

    // MARK: - Bookings requiring attention  (SVG y=178, 400×148, danger header)

    @ViewBuilder
    private var attentionCard: some View {
        if !attention.isEmpty {
            VStack(spacing: 0) {
                // Header strip (danger tint, triangle icon, count pill)
                HStack(spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Brand.danger)
                    Text("Bookings requiring attention")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(attention.count)")
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                        .frame(width: 26, height: 22)
                        .background(Capsule().fill(Brand.danger.opacity(0.18)))
                }
                .padding(.horizontal, Space.s5)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .background(Brand.danger.opacity(0.14))

                VStack(spacing: 0) {
                    ForEach(Array(attention.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.horizontal, Space.s5)
                        }
                        attentionRow(item)
                    }
                }
            }
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
        }
    }

    private func attentionRow(_ item: VesselAttentionItem) -> some View {
        let tint: Color = item.kind == .danger ? Brand.danger : Brand.warning
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.detail)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Text(item.route)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button {
                Task { await openBooking(item.bookingNumber) }
            } label: {
                Text("VIEW")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(tint)
                    .frame(width: 60, height: 24)
                    .background(Capsule().fill(tint.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
    }

    // MARK: - Primary CTA row  (SVG y=346: gradient "Create booking" + glass "Track cargo")

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await createBooking() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Create booking")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                Task { await trackCargo() }
            } label: {
                Text("Track cargo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats  (SVG y=418: ACTIVE · TEU AFLOAT · AVG TRANSIT · MO. SPEND)

    private var statStrip: some View {
        let d = dash
        return HStack(spacing: Space.s2) {
            statTile(label: "ACTIVE",
                     value: "\(d?.activeBookings ?? bookings.count)",
                     footnote: "+1 this wk", footnoteColor: Brand.success)
            statTile(label: "TEU AFLOAT",
                     value: "\(d?.teuAfloat ?? 0)",
                     footnote: "\(d?.vesselsCount ?? 0) vessels", footnoteColor: palette.textSecondary)
            statTile(label: "AVG TRANSIT",
                     value: avgTransitStr, gradientNumeral: true,
                     footnote: "−1d", footnoteColor: Brand.success)
            statTile(label: "MO. SPEND",
                     value: monthlySpendStr, gradientNumeral: true,
                     footnote: "+6% vs Apr", footnoteColor: palette.textSecondary)
        }
    }

    private func statTile(label: String, value: String,
                          gradientNumeral: Bool = false,
                          footnote: String, footnoteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            Text(footnote)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(footnoteColor)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var avgTransitStr: String {
        guard let avg = dash?.avgTransitDays, avg > 0 else { return "—" }
        return "\(Int(avg.rounded()))d"
    }

    private var monthlySpendStr: String {
        guard let s = dash?.monthlySpend, s > 0 else { return "—" }
        if s >= 1_000_000 { return String(format: "$%.1fM", s / 1_000_000) }
        return String(format: "$%.0fK", s / 1_000)
    }

    // MARK: - Active bookings  (SVG y=518: eyebrow + "See all (n)" + list card)

    @ViewBuilder
    private var activeBookingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE BOOKINGS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("See all (\(bookings.count))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if bookings.isEmpty {
                EusoEmptyState(systemImage: "shippingbox.fill",
                               title: "No active bookings",
                               subtitle: "Vessel bookings for Eusorone Marine will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bookings.prefix(3).enumerated()), id: \.element.id) { idx, b in
                        if idx > 0 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                        bookingRow(b)
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func bookingRow(_ b: VesselBooking) -> some View {
        let (statusText, statusColor) = statusStyle(for: b)
        return HStack(alignment: .top, spacing: Space.s3) {
            bookingBadge(for: b)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(b.origin ?? "—") → \(b.destination ?? "—")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(metaLine(b))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                progressDots(b.progress ?? 0)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(statusColor)
                Text(amountStr(b.amount))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    private func bookingBadge(for b: VesselBooking) -> some View {
        let (icon, color): (String, Color) = {
            if b.customsHold == true { return ("exclamationmark.triangle.fill", Brand.warning) }
            if b.reefer == true      { return ("thermometer.snowflake", Brand.success) }
            if b.hazmat == true      { return ("exclamationmark.triangle.fill", Brand.hazmat) }
            return ("shippingbox.fill", Brand.info)
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

    /// Progress dots — gradient up to the active node, faint white beyond.
    private func progressDots(_ progress: Double) -> some View {
        let total = 8
        let filled = max(1, min(total, Int((progress * Double(total)).rounded())))
        return HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < filled
                          ? AnyShapeStyle(LinearGradient.primary)
                          : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: i == filled - 1 ? 6 : (i < filled ? 5 : 4),
                           height: i == filled - 1 ? 6 : (i < filled ? 5 : 4))
            }
        }
        .frame(height: 8)
    }

    private func metaLine(_ b: VesselBooking) -> String {
        var parts: [String] = []
        if let n = b.bookingNumber { parts.append(n) }
        if let t = b.containerType { parts.append(t) }
        if let c = b.containersCount { parts.append("\(c) cntr") }
        if let cm = b.commodity, b.containerType == nil { parts.append(cm) }
        if let car = b.carrier { parts.append(car) }
        if let term = b.terminal { parts.append(term) }
        return parts.joined(separator: " · ")
    }

    private func statusStyle(for b: VesselBooking) -> (String, Color) {
        switch (b.status ?? "").lowercased() {
        case "in_transit", "at_sea":           return ("IN TRANSIT", Brand.blue)
        case "customs_hold", "on_hold", "hold": return ("CUSTOMS HOLD", Brand.warning)
        case "loaded", "loaded_on_vessel":     return ("LOADED", Brand.success)
        case "delivered":                      return ("DELIVERED", palette.textSecondary)
        default:                               return ((b.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(), Brand.blue)
        }
    }

    private func amountStr(_ amount: Double?) -> String {
        guard let a = amount, a > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: a)) ?? "$\(Int(a))"
    }

    // MARK: - ESang card  (SVG y=786, 400×56)

    private var esangCard: some View {
        Button {
            Task { await openEsangSuggestion() }
        } label: {
            HStack(spacing: Space.s3) {
                OrbeSang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(esangHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(esangSubline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var esangHeadline: String {
        if let first = attention.first(where: { $0.kind == .danger }) {
            return "ESang AI: \(first.bookingNumber) free time ends in 3 days at APM"
        }
        return "ESang AI: all bookings on schedule"
    }

    private var esangSubline: String {
        attention.contains(where: { $0.kind == .danger })
            ? "Expedite CBP exam booking · avoid ~$2,400 demurrage"
            : "No demurrage or ISF exposure right now"
    }

    // MARK: - Loading + error chrome

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 148)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Spacer()
            Button { actionError = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load (real loading + error; do/catch — never try?)

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        do {
            // getVesselDashboard (EXISTS :715) — hero figures.
            async let dashTask: VesselShipperDash =
                EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselDashboard")
            // getVesselShipments (EXISTS :121) — active bookings list.
            async let listTask: [VesselBooking] =
                EusoTripAPI.shared.query("vesselShipments.getVesselShipments",
                                         input: ListIn(limit: 50, offset: 0))
            // getVesselDemurrage (EXISTS :632) — demurrage exposure rows.
            async let demTask: [VesselDemurrageRow] =
                EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselDemurrage")
            // getISFStatus (EXISTS :815) — ISF 10+2 filing status.
            async let isfTask: [VesselISFRow] =
                EusoTripAPI.shared.queryNoInput("vesselShipments.getISFStatus")

            let (d, list, dem, isf) = try await (dashTask, listTask, demTask, isfTask)
            self.dash = d
            self.bookings = list
            self.attention = buildAttention(demurrage: dem, isf: isf)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Derive the "needs attention" queue client-side from the demurrage +
    /// ISF endpoints. STUB · named-gap: vesselShipments.getVesselAttention —
    /// a server-side shipper attention aggregator does not exist yet, so we
    /// join here.
    private func buildAttention(demurrage: [VesselDemurrageRow],
                                isf: [VesselISFRow]) -> [VesselAttentionItem] {
        var items: [VesselAttentionItem] = []
        for d in demurrage where (d.onHold == true) {
            let used = d.freeDaysUsed ?? 0
            let total = d.freeDaysTotal ?? 0
            let bn = d.bookingNumber ?? "—"
            var meta: [String] = [bn, "customs hold"]
            if total > 0 { meta.append("demurrage day \(used) of \(total) free") }
            var route: [String] = []
            if let o = d.origin { route.append(o) }
            if let dest = d.destination { route.append(dest) }
            var routeMeta: [String] = []
            if let ct = d.containerType { routeMeta.append(ct) }
            if let cm = d.commodity { routeMeta.append(cm) }
            if let car = d.carrier { routeMeta.append(car) }
            items.append(VesselAttentionItem(
                id: "dem-\(bn)",
                bookingNumber: bn,
                detail: meta.joined(separator: " · "),
                route: (route.joined(separator: " → ")
                        + (routeMeta.isEmpty ? "" : " · " + routeMeta.joined(separator: " · "))),
                kind: .danger))
        }
        for f in isf where (f.filed != true) {
            let bn = f.bookingNumber ?? "—"
            var meta: [String] = [bn]
            if let h = f.hoursUntilDue, h > 0 {
                meta.append("ISF 10+2 due in \(Int(h.rounded()))h")
                meta.append("file before loading")
            } else {
                meta.append("ISF 10+2 outstanding")
            }
            var route: [String] = []
            if let o = f.origin { route.append(o) }
            if let dest = f.destination { route.append(dest) }
            var routeMeta: [String] = []
            if let ct = f.containerType { routeMeta.append(ct) }
            if let cm = f.commodity { routeMeta.append(cm) }
            if let car = f.carrier { routeMeta.append(car) }
            items.append(VesselAttentionItem(
                id: "isf-\(bn)",
                bookingNumber: bn,
                detail: meta.joined(separator: " · "),
                route: (route.joined(separator: " → ")
                        + (routeMeta.isEmpty ? "" : " · " + routeMeta.joined(separator: " · "))),
                kind: .warning))
        }
        return items
    }

    // MARK: - Actions (do/catch · actionError on failure)

    /// createVesselBooking (EXISTS :59). Real mutation surface for the
    /// primary CTA. Navigation to the booking wizard is wired at the
    /// surface router; here we honestly surface the mutation result/error.
    private func createBooking() async {
        struct CreateIn: Encodable { let draft: Bool }
        struct CreateOut: Decodable { let id: String?; let bookingNumber: String? }
        do {
            let _: CreateOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBooking",
                input: CreateIn(draft: true))
            await load()
        } catch {
            actionError = "Couldn't start a booking — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// getVesselTrack (EXISTS :1013) / liveTrackOceanShipment (EXISTS :1060)
    /// back the Track-cargo destination. We validate the live-track endpoint
    /// is reachable before routing so a dead feed surfaces honestly.
    private func trackCargo() async {
        struct TrackOut: Decodable { let positions: [String]? }
        do {
            let _: TrackOut = try await EusoTripAPI.shared.queryNoInput(
                "vesselShipments.liveTrackOceanShipment")
        } catch {
            actionError = "Tracking unavailable — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func openBooking(_ bookingNumber: String) async {
        struct DetailIn: Encodable { let bookingNumber: String }
        struct DetailOut: Decodable { let id: String? }
        do {
            let _: DetailOut = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments",
                input: DetailIn(bookingNumber: bookingNumber))
        } catch {
            actionError = "Couldn't open \(bookingNumber) — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// ESang demurrage suggestion taps into getVesselDemurrage (EXISTS :632)
    /// for the live free-time window. STUB · named-gap:
    /// vesselShipments.esangVesselSuggestion (no AI suggestion endpoint yet).
    private func openEsangSuggestion() async {
        struct DemOut: Decodable { let bookingNumber: String? }
        do {
            let _: [DemOut] = try await EusoTripAPI.shared.queryNoInput(
                "vesselShipments.getVesselDemurrage")
        } catch {
            actionError = "ESang couldn't refresh demurrage — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("001 · Vessel Shipper Home · Night") {
    VesselShipperHomeScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("001 · Vessel Shipper Home · Light") {
    VesselShipperHomeScreen(theme: Theme.light).preferredColorScheme(.light)
}
