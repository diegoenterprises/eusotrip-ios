//
//  001_VesselShipperHome.swift
//  EusoTrip — Vessel Shipper · Home (booking dashboard + attention queue).
//
//  Web parity: client/src/pages/vessel/VesselShipperDashboard.tsx
//  Wireframe:  06 Vessel / 001 Vessel Shipper Home (canvas 440×956).
//  PERSONA:    Authenticated VESSEL_SHIPPER. Booking identifiers are server-issued.
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
    @EnvironmentObject private var session: EusoTripSession

    @State private var dash: VesselShipperDash? = nil
    @State private var bookings: [VesselBooking] = []
    @State private var attention: [VesselAttentionItem] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showCreateBooking = false
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

                // First-load unlock cascade: top-level sections spring in
                // top-to-bottom (scale 0.92 + blur 5pt + 50 ms stagger) once
                // per cold launch; settled on re-visit. Reduce-Motion → fade.
                StaggeredEntranceStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError {
                        actionErrorBanner(actionError)
                    }

	                    HomeWeatherWidget()
	                    EusoCardIssuePanel(
	                        title: "EusoCard",
	                        subtitle: "Vessel shipper spend card for D&D, claims and bookings"
	                    )

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
        .sheet(isPresented: $showCreateBooking) {
            VesselBookingCreateScreen(theme: palette) { _ in
                showCreateBooking = false
                actionError = nil
                Task { await load() }
            }
        }
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
                Text(headline)
                    .font(.system(size: 34, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                    if let initials = userInitials {
                        Text(initials)
                            .font(.system(size: 14, weight: .bold)).tracking(0.4)
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
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
            return "\(active) active bookings · \(needs) need attention"
        }
        return "\(active) active bookings"
    }

    private var headline: String {
        let firstName = session.user?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstName.isEmpty ? "Vessel dashboard" : "Welcome, \(firstName)"
    }

    private var userInitials: String? {
        guard let name = session.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return initials.isEmpty ? nil : initials
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
                showCreateBooking = true
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                     footnote: "live bookings", footnoteColor: palette.textSecondary)
            statTile(label: "TEU AFLOAT",
                     value: "\(d?.teuAfloat ?? 0)",
                     footnote: "\(d?.vesselsCount ?? 0) vessels", footnoteColor: palette.textSecondary)
            statTile(label: "AVG TRANSIT",
                     value: avgTransitStr, gradientNumeral: true,
                     footnote: "rolling average", footnoteColor: palette.textSecondary)
            statTile(label: "MO. SPEND",
                     value: monthlySpendStr, gradientNumeral: true,
                     footnote: "current month", footnoteColor: palette.textSecondary)
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
        guard let avg = dash?.avgTransitDays, avg > 0 else { return "-" }
        return "\(Int(avg.rounded()))d"
    }

    private var monthlySpendStr: String {
        guard let s = dash?.monthlySpend, s > 0 else { return "-" }
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
                               subtitle: "Your vessel bookings will appear here.")
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
                Text("\(b.origin ?? "-") → \(b.destination ?? "-")")
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
        default:                               return ((b.status ?? "-").replacingOccurrences(of: "_", with: " ").uppercased(), Brand.blue)
        }
    }

    private func amountStr(_ amount: Double?) -> String {
        guard let a = amount, a > 0 else { return "-" }
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
            return "\(first.bookingNumber) requires review"
        }
        return "No current booking exceptions"
    }

    private var esangSubline: String {
        attention.first(where: { $0.kind == .danger })?.detail
            ?? "Demurrage and ISF feeds report no active exceptions"
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
            let bn = d.bookingNumber ?? "-"
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
            let bn = f.bookingNumber ?? "-"
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

    /// getVesselTrack (EXISTS :1013) / liveTrackOceanShipment (EXISTS :1060)
    /// back the Track-cargo destination. We validate the live-track endpoint
    /// is reachable before routing so a dead feed surfaces honestly.
    private func trackCargo() async {
        struct TrackOut: Decodable { let positions: [String]? }
        do {
            let _: TrackOut = try await EusoTripAPI.shared.queryNoInput(
                "vesselShipments.liveTrackOceanShipment")
        } catch {
            actionError = "Tracking unavailable. "
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
            actionError = "Couldn't open \(bookingNumber). "
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
            actionError = "ESang couldn't refresh demurrage. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

// MARK: - Native vessel booking creation

private struct VesselBookingPortOption: Decodable, Identifiable, Hashable {
    let id: Int
    let canonicalKey: String
    let nodeType: String
    let name: String
    let city: String?
    let countryCode: String?
    let subdivisionCode: String?
    let modes: [String]
    let operatingStatus: String

    var displayName: String {
        let location = [city, subdivisionCode, countryCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return location.isEmpty ? name : "\(name) · \(location)"
    }

    var isSelectableVesselPort: Bool {
        nodeType.uppercased() == "PORT"
            && modes.contains(where: { $0.uppercased() == "VESSEL" })
            && !["inactive", "closed"].contains(operatingStatus.lowercased())
    }
}

private struct VesselBookingPortSearchInput: Encodable {
    let query: String?
    let countries: [String]
    let modes: [String]
    let nodeTypes: [String]
    let limit: Int
}

private struct VesselBookingAssessmentDraft: Encodable {
    let originNodeId: Int
    let destinationNodeId: Int
    let vesselId: Int?
    let cargoType: String
    let commodity: String
    let containerSize: String?
    let numberOfContainers: Int?
    let totalWeightKg: Double?
    let totalVolumeCBM: Double?
    let temperatureSetting: String?
    let hazmatClass: String?
    let imdgCode: String?
    let properShippingName: String?
    let marinePollutant: Bool
}

private struct VesselBookingAssessmentRequest: Encodable {
    let requestKey: String
    let title: String
    let draft: VesselBookingAssessmentDraft
}

private struct VesselBookingCreateInput: Encodable {
    let originNodeId: Int
    let destinationNodeId: Int
    let vesselId: Int?
    let cargoType: String
    let commodity: String
    let containerSize: String?
    let numberOfContainers: Int?
    let totalWeightKg: Double?
    let totalVolumeCBM: Double?
    let temperatureSetting: String?
    let hazmatClass: String?
    let imdgCode: String?
    let properShippingName: String?
    let marinePollutant: Bool
    let incoterms: String
    let freightTerms: String
    let rate: Double
    let rateType: String
    let currency: String
    let portIntelligenceAssessmentId: String
    let portIntelligenceAcknowledged: Bool

    init(
        draft: VesselBookingAssessmentDraft,
        incoterms: String,
        freightTerms: String,
        rate: Double,
        rateType: String,
        currency: String,
        portIntelligenceAssessmentId: String,
        portIntelligenceAcknowledged: Bool
    ) {
        originNodeId = draft.originNodeId
        destinationNodeId = draft.destinationNodeId
        vesselId = draft.vesselId
        cargoType = draft.cargoType
        commodity = draft.commodity
        containerSize = draft.containerSize
        numberOfContainers = draft.numberOfContainers
        totalWeightKg = draft.totalWeightKg
        totalVolumeCBM = draft.totalVolumeCBM
        temperatureSetting = draft.temperatureSetting
        hazmatClass = draft.hazmatClass
        imdgCode = draft.imdgCode
        properShippingName = draft.properShippingName
        marinePollutant = draft.marinePollutant
        self.incoterms = incoterms
        self.freightTerms = freightTerms
        self.rate = rate
        self.rateType = rateType
        self.currency = currency
        self.portIntelligenceAssessmentId = portIntelligenceAssessmentId
        self.portIntelligenceAcknowledged = portIntelligenceAcknowledged
    }
}

private struct VesselBookingCreateResult: Decodable {
    let id: Int
    let bookingNumber: String
    let status: String
    let portIntelligenceAssessmentId: String
    let portIntelligenceGate: String
}

private enum VesselBookingPortRole: String, Identifiable {
    case origin
    case destination

    var id: String { rawValue }
    var title: String { self == .origin ? "Origin port" : "Destination port" }
}

private struct VesselBookingCreateScreen: View {
    let theme: Theme.Palette
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cargoType = ""
    @State private var commodity = ""
    @State private var containerSize = ""
    @State private var numberOfContainers = 1
    @State private var totalWeightKg = ""
    @State private var totalVolumeCBM = ""
    @State private var temperatureSetting = ""
    @State private var isDangerousGoods = false
    @State private var hazmatClass = ""
    @State private var imdgCode = ""
    @State private var properShippingName = ""
    @State private var marinePollutant = false
    @State private var originPort: VesselBookingPortOption?
    @State private var destinationPort: VesselBookingPortOption?
    @State private var activePortRole: VesselBookingPortRole?
    @State private var incoterms = ""
    @State private var freightTerms = ""
    @State private var rate = ""
    @State private var rateType = ""
    @State private var currency = "USD"
    @State private var assessment: PortIntelAssessment?
    @State private var assessedDraftSignature: String?
    @State private var acknowledged = false
    @State private var isAssessing = false
    @State private var isSubmitting = false
    @State private var actionError: String?

    private static let cargoTypes = [
        "container", "bulk_dry", "bulk_liquid", "breakbulk",
        "ro_ro", "reefer", "project_cargo",
    ]
    private static let containerSizes = [
        "20ft", "40ft", "40ft_hc", "45ft", "20ft_reefer", "40ft_reefer",
    ]
    private static let incotermOptions = [
        "EXW", "FCA", "FAS", "FOB", "CFR", "CIF", "CPT", "CIP", "DAP", "DPU", "DDP",
    ]
    private static let freightTermOptions = ["prepaid", "collect", "third_party"]
    private static let rateTypeOptions = ["lump_sum", "per_teu", "per_ton", "per_cbm"]
    private static let currencyOptions = ["USD", "CAD", "MXN"]

    private var usesContainers: Bool {
        cargoType == "container" || cargoType == "reefer"
    }

    private var normalizedUNNumber: String? {
        guard isDangerousGoods else { return nil }
        let value = imdgCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = value.hasPrefix("UN") ? String(value.dropFirst(2)) : value
        guard digits.count == 4, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return "UN\(digits)"
    }

    private var parsedWeight: Double? {
        guard let value = positiveDouble(totalWeightKg), value <= 100_000_000 else { return nil }
        return value
    }
    private var parsedVolume: Double? {
        guard let value = positiveDouble(totalVolumeCBM), value <= 10_000_000 else { return nil }
        return value
    }
    private var parsedRate: Double? { positiveDouble(rate) }

    private var assessmentDraft: VesselBookingAssessmentDraft? {
        guard let originPort, let destinationPort, originPort.id != destinationPort.id else { return nil }
        let normalizedCommodity = commodity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.cargoTypes.contains(cargoType),
              (2...255).contains(normalizedCommodity.count) else { return nil }
        if usesContainers && (containerSize.isEmpty || numberOfContainers <= 0) { return nil }
        if !usesContainers && parsedWeight == nil && parsedVolume == nil { return nil }
        if cargoType == "reefer" {
            let temperature = temperatureSetting.trimmingCharacters(in: .whitespacesAndNewlines)
            if temperature.isEmpty || temperature.count > 50 { return nil }
        }
        if isDangerousGoods {
            let normalizedClass = hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedClass.isEmpty,
                  normalizedClass.count <= 10,
                  normalizedUNNumber != nil,
                  (2...255).contains(normalizedName.count) else {
                return nil
            }
        }
        return VesselBookingAssessmentDraft(
            originNodeId: originPort.id,
            destinationNodeId: destinationPort.id,
            vesselId: nil,
            cargoType: cargoType,
            commodity: normalizedCommodity,
            containerSize: usesContainers ? containerSize : nil,
            numberOfContainers: usesContainers ? numberOfContainers : nil,
            totalWeightKg: parsedWeight,
            totalVolumeCBM: parsedVolume,
            temperatureSetting: cargoType == "reefer"
                ? temperatureSetting.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            hazmatClass: isDangerousGoods
                ? hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            imdgCode: normalizedUNNumber,
            properShippingName: isDangerousGoods
                ? properShippingName.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil,
            marinePollutant: isDangerousGoods && marinePollutant
        )
    }

    private var currentDraftSignature: String? {
        guard let assessmentDraft else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(assessmentDraft).base64EncodedString()
        } catch {
            return nil
        }
    }

    private var hasCurrentAssessment: Bool {
        assessment != nil
            && assessedDraftSignature != nil
            && assessedDraftSignature == currentDraftSignature
    }

    private var assessmentAllowsSubmission: Bool {
        guard hasCurrentAssessment, let gate = assessment?.preflight.gate else { return false }
        if gate == "ready" { return true }
        return gate == "acknowledgement_required" && acknowledged
    }

    private var termsAreValid: Bool {
        guard Self.incotermOptions.contains(incoterms),
              Self.freightTermOptions.contains(freightTerms),
              Self.rateTypeOptions.contains(rateType),
              Self.currencyOptions.contains(currency),
              let parsedRate,
              abs(parsedRate * 100 - (parsedRate * 100).rounded()) < 0.000_001 else {
            return false
        }
        switch rateType {
        case "per_teu": return usesContainers && numberOfContainers > 0
        case "per_ton": return parsedWeight != nil
        case "per_cbm": return parsedVolume != nil
        case "lump_sum": return true
        default: return false
        }
    }

    private var canSubmit: Bool {
        assessmentDraft != nil && termsAreValid && assessmentAllowsSubmission && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                cargoSection
                quantitySection
                dangerousGoodsSection
                routeSection
                termsSection
                portIntelligenceSection
                submitSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.bgPrimary)
            .navigationTitle("Create vessel booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .sheet(item: $activePortRole) { role in
                VesselBookingPortSearchScreen(
                    theme: theme,
                    title: role.title,
                    excludingNodeId: role == .origin ? destinationPort?.id : originPort?.id
                ) { selected in
                    if role == .origin { originPort = selected }
                    else { destinationPort = selected }
                    activePortRole = nil
                }
            }
        }
    }

    private var cargoSection: some View {
        Section("Cargo") {
            Picker("Cargo type", selection: $cargoType) {
                Text("Select cargo type").tag("")
                ForEach(Self.cargoTypes, id: \.self) { value in
                    Text(display(value)).tag(value)
                }
            }
            TextField("Commodity or product grade", text: $commodity)
                .textInputAutocapitalization(.words)
        }
    }

    @ViewBuilder
    private var quantitySection: some View {
        Section("Quantity") {
            if usesContainers {
                Picker("Container size", selection: $containerSize) {
                    Text("Select size").tag("")
                    ForEach(Self.containerSizes, id: \.self) { value in
                        Text(display(value)).tag(value)
                    }
                }
                Stepper("Containers: \(numberOfContainers)", value: $numberOfContainers, in: 1...10_000)
            }
            TextField("Total weight in kg", text: $totalWeightKg)
                .keyboardType(.decimalPad)
            TextField("Total volume in CBM", text: $totalVolumeCBM)
                .keyboardType(.decimalPad)
            if !usesContainers && parsedWeight == nil && parsedVolume == nil {
                Text("Enter a positive weight or volume for Port Intelligence.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
            if cargoType == "reefer" {
                TextField("Temperature setting", text: $temperatureSetting)
            }
        }
    }

    private var dangerousGoodsSection: some View {
        Section("Dangerous goods") {
            Toggle("IMDG regulated cargo", isOn: $isDangerousGoods)
            if isDangerousGoods {
                TextField("IMDG class", text: $hazmatClass)
                TextField("UN number", text: $imdgCode)
                    .textInputAutocapitalization(.characters)
                TextField("Proper shipping name", text: $properShippingName)
                Toggle("Marine pollutant", isOn: $marinePollutant)
                if !imdgCode.isEmpty && normalizedUNNumber == nil {
                    Text("Use a four-digit UN number.")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                }
            }
        }
    }

    private var routeSection: some View {
        Section("Route") {
            portButton(role: .origin, selection: originPort)
            portButton(role: .destination, selection: destinationPort)
            if originPort?.id == destinationPort?.id, originPort != nil {
                Text("Origin and destination ports must differ.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
        }
    }

    private var termsSection: some View {
        Section("Commercial terms") {
            Picker("Incoterms", selection: $incoterms) {
                Text("Select incoterm").tag("")
                ForEach(Self.incotermOptions, id: \.self) { Text($0).tag($0) }
            }
            Picker("Freight terms", selection: $freightTerms) {
                Text("Select freight terms").tag("")
                ForEach(Self.freightTermOptions, id: \.self) { Text(display($0)).tag($0) }
            }
            Picker("Rate basis", selection: $rateType) {
                Text("Select rate basis").tag("")
                ForEach(Self.rateTypeOptions, id: \.self) { Text(display($0)).tag($0) }
            }
            Picker("Currency", selection: $currency) {
                ForEach(Self.currencyOptions, id: \.self) { Text($0).tag($0) }
            }
            TextField("Booked rate", text: $rate)
                .keyboardType(.decimalPad)
            if !rate.isEmpty && !termsAreValid {
                Text("Enter a positive two-decimal rate and a basis supported by the stated quantity.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var portIntelligenceSection: some View {
        Section("Port Intelligence") {
            if let assessment {
                let isCurrent = hasCurrentAssessment
                HStack {
                    Image(systemName: assessment.preflight.gate == "ready"
                          ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(assessment.preflight.gate == "blocked" ? Brand.danger : Brand.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isCurrent ? display(assessment.preflight.gate) : "Assessment needs refresh")
                            .font(EType.bodyStrong)
                        Text("\(assessment.preflight.counts.viable) viable · \(assessment.preflight.counts.conditional) conditional · \(assessment.preflight.counts.insufficientEvidence) unresolved · \(assessment.preflight.counts.blocked) blocked")
                            .font(EType.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                if isCurrent && assessment.preflight.gate == "acknowledgement_required" {
                    Toggle("I reviewed the documented unknowns", isOn: $acknowledged)
                }
                Text("\(assessment.evidence.count) evidence records · engine \(assessment.engineVersion)")
                    .font(EType.caption)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("A current vessel-booking assessment is required before submission.")
                    .font(EType.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            Button {
                Task { await assessPortIntelligence() }
            } label: {
                Label(hasCurrentAssessment ? "Refresh assessment" : "Assess booking", systemImage: "checkmark.shield")
            }
            .disabled(assessmentDraft == nil || isAssessing || isSubmitting)

            if isAssessing {
                ProgressView("Assessing route and facilities")
            }
        }
    }

    private var submitSection: some View {
        Section {
            if let actionError {
                Text(actionError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting { ProgressView() }
                    else { Text("Submit vessel booking").font(EType.bodyStrong) }
                    Spacer()
                }
            }
            .disabled(!canSubmit)
        }
    }

    private func portButton(role: VesselBookingPortRole, selection: VesselBookingPortOption?) -> some View {
        Button {
            activePortRole = role
        } label: {
            HStack {
                Text(role.title)
                Spacer()
                Text(selection?.displayName ?? "Select")
                    .foregroundStyle(selection == nil ? theme.textSecondary : theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func positiveDouble(_ raw: String) -> Double? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value > 0, value.isFinite else { return nil }
        return value
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func assessPortIntelligence() async {
        guard let draft = assessmentDraft, let signature = currentDraftSignature else {
            actionError = "Complete the cargo, quantity, and two global ports before assessment."
            return
        }
        isAssessing = true
        actionError = nil
        acknowledged = false
        defer { isAssessing = false }
        do {
            let result: PortIntelAssessment = try await EusoTripAPI.shared.mutation(
                "portIntelligence.assessVesselBookingDraft",
                input: VesselBookingAssessmentRequest(
                    requestKey: UUID().uuidString,
                    title: String("\(draft.commodity) vessel booking".prefix(255)),
                    draft: draft
                )
            )
            assessment = result
            assessedDraftSignature = signature
        } catch {
            assessment = nil
            assessedDraftSignature = nil
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard let draft = assessmentDraft,
              let assessment,
              hasCurrentAssessment,
              assessmentAllowsSubmission,
              termsAreValid,
              let parsedRate else {
            actionError = "Complete the current Port Intelligence gate and all booking terms before submission."
            return
        }
        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }
        do {
            let result: VesselBookingCreateResult = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBooking",
                input: VesselBookingCreateInput(
                    draft: draft,
                    incoterms: incoterms,
                    freightTerms: freightTerms,
                    rate: parsedRate,
                    rateType: rateType,
                    currency: currency,
                    portIntelligenceAssessmentId: assessment.publicId,
                    portIntelligenceAcknowledged: assessment.preflight.gate == "acknowledgement_required" && acknowledged
                )
            )
            onCreated(result.bookingNumber)
            dismiss()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct VesselBookingPortSearchScreen: View {
    let theme: Theme.Palette
    let title: String
    let excludingNodeId: Int?
    let onSelect: (VesselBookingPortOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [VesselBookingPortOption] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let loadError {
                    Text(loadError)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                }
                if isLoading && results.isEmpty {
                    ProgressView("Searching verified vessel ports")
                }
                ForEach(results.filter { $0.id != excludingNodeId && $0.isSelectableVesselPort }) { port in
                    Button {
                        onSelect(port)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(port.name)
                                .font(EType.bodyStrong)
                                .foregroundStyle(theme.textPrimary)
                            Text([port.city, port.subdivisionCode, port.countryCode, port.canonicalKey]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(EType.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !isLoading && loadError == nil && results.isEmpty {
                    Text("No evidenced vessel ports match this search.")
                        .font(EType.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .searchable(text: $query, prompt: "Port, city, or code")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: query) {
                do {
                    try await Task.sleep(nanoseconds: query.isEmpty ? 0 : 250_000_000)
                } catch {
                    return
                }
                await search()
            }
        }
    }

    private func search() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let normalizedQuery = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255))
        do {
            let rows: [VesselBookingPortOption] = try await EusoTripAPI.shared.query(
                "portIntelligence.searchNodes",
                input: VesselBookingPortSearchInput(
                    query: normalizedQuery.isEmpty ? nil : normalizedQuery,
                    countries: [],
                    modes: ["VESSEL"],
                    nodeTypes: ["PORT"],
                    limit: 100
                )
            )
            guard normalizedQuery == String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255)) else {
                return
            }
            results = rows.filter(\.isSelectableVesselPort)
        } catch {
            results = []
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("001 · Vessel Shipper Home · Night") {
    VesselShipperHomeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("001 · Vessel Shipper Home · Light") {
    VesselShipperHomeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
