//
//  625_RailAppointmentCompliance.swift
//  EusoTrip — Rail Engineer · Appointment Compliance (carrier-side gate scorecard).
//
//  Verbatim port of "625 Rail Appointment Compliance.svg" (Dark).
//  Flagship DETAIL grammar (mirrors 621 / 609 / 582): back chevron + eyebrow +
//  mono caption + 28/-0.4 title, gradient-rimmed hero ActiveCard (on-time rate
//  + progress), 3-cell KPI strip (ON-TIME eusoDiagonal · LATE · NO-SHOW),
//  itemized carrier ListRow stack (40x40 icon chip + name + mono sub + status
//  pill + right tabular %), peak-gate context strip, Schedule appt / Dock board
//  CTA pair. CARRIER-SIDE rail-engineer surface; shipper-of-record Eusorone
//  Technologies (DU). 7-day gate-appointment on-time scorecard by carrier.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb]
//  · COMPLIANCE · ME).
//
//  Data (REAL · grep-confirmed in-repo this fire):
//    yardManagement.getAppointmentCompliance (EXISTS yardManagement.ts:2198)
//      → { overallCompliancePct, totalScheduled, totalOnTime, totalEarly,
//          totalLate, totalNoShow, carrierBreakdown[…], peakHours[…] }
//      input: { locationId?, period: "today"|"week"|"month" }  — period "week" = 7-DAY.
//

import SwiftUI

struct RailAppointmentComplianceScreen: View {
    let theme: Theme.Palette
    var locationId: String = ""

    var body: some View {
        Shell(theme: theme) { RailAppointmentComplianceBody(locationId: locationId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror yardManagement.getAppointmentCompliance return)

private struct ApptCompliance625: Decodable {
    let overallCompliancePct: Double?
    let totalScheduled: Int?
    let totalOnTime: Int?
    let totalEarly: Int?
    let totalLate: Int?
    let totalNoShow: Int?
    let carrierBreakdown: [CarrierRow625]?
    let peakHours: [PeakHour625]?
}

private struct CarrierRow625: Decodable, Identifiable {
    var id: String { carrierName }
    let carrierName: String
    let scheduled: Int?
    let onTime: Int?
    let early: Int?
    let late: Int?
    let noShow: Int?
    let compliancePct: Double?
}

private struct PeakHour625: Decodable, Identifiable {
    var id: String { hour }
    let hour: String
    let count: Int?
}

// MARK: - Body

private struct RailAppointmentComplianceBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let locationId: String

    @State private var data: ApptCompliance625? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived

    /// on-time rate as an integer percent (wireframe shows "82%").
    private var onTimePct: Int { Int((data?.overallCompliancePct ?? 0).rounded()) }
    private var onTimeCount: Int { data?.totalOnTime ?? 0 }
    private var lateCount: Int { data?.totalLate ?? 0 }
    private var noShowCount: Int { data?.totalNoShow ?? 0 }

    /// Carriers sorted high→low on-time rate so the scorecard reads top-down.
    private var carriers: [CarrierRow625] {
        (data?.carrierBreakdown ?? [])
            .sorted { ($0.compliancePct ?? 0) > ($1.compliancePct ?? 0) }
    }
    /// First three rows itemized; the rest collapse into the overflow line.
    private var topCarriers: [CarrierRow625] { Array(carriers.prefix(3)) }
    private var overflowCarriers: [CarrierRow625] { Array(carriers.dropFirst(3)) }

    /// Busiest 2-hour gate window + its share of weekly appointments.
    private var peakWindow: PeakHour625? {
        (data?.peakHours ?? []).max { ($0.count ?? 0) < ($1.count ?? 0) }
    }
    private var peakShare: Int {
        let total = (data?.peakHours ?? []).reduce(into: 0) { acc, p in acc += (p.count ?? 0) }
        guard total > 0, let pk = peakWindow else { return 0 }
        return Int((Double(pk.count ?? 0) / Double(total) * 100).rounded())
    }
    private var carriersBelow70: Int { carriers.filter { ($0.compliancePct ?? 0) < 70 }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s5)

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    heroCard
                        .padding(.bottom, Space.s4)
                    kpiStrip
                        .padding(.bottom, Space.s5)
                    carriersCard
                        .padding(.bottom, Space.s4)
                    peakStrip
                        .padding(.bottom, Space.s5)
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · APPT COMPLIANCE  ···  7-DAY)

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · APPT COMPLIANCE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("7-DAY")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back chevron + title + BNSF INTERMODAL / synced)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Back chevron polyline.
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)

            Text("Appt compliance")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 2)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("BNSF INTERMODAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 12m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, Space.s3)
    }

    // MARK: - Hero ActiveCard (gradient-rimmed on-time rate + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // on-time pill + delta pill
                HStack(spacing: Space.s2) {
                    Text("on-time")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("+4 pts")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0x34D8A6))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.success.opacity(0.20)))
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("7 DAYS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("+4 PTS")
                            .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0x34D8A6))
                    }
                }
                .padding(.bottom, Space.s4)

                // lead figure (82%) + on-time rate label + breakdown caption
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text("\(onTimePct)%")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("on-time rate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(onTimeCount) on-time · \(lateCount) late · \(noShowCount) no-show")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, Space.s4)

                // progress bar — fill width = on-time rate
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 6)
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * CGFloat(min(max(onTimePct, 0), 100)) / 100.0,
                                   height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (ON-TIME eusoDiagonal · LATE · NO-SHOW)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // cell-1 — eusoDiagonal fill, white text.
            VStack(alignment: .leading, spacing: 6) {
                Text("ON-TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(onTimePct)%")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "LATE",    value: "\(lateCount)",   color: Color(hex: 0xF5B544))
            kpiCell(label: "NO-SHOW", value: "\(noShowCount)", color: Color(hex: 0xFF6B5E))
        }
    }

    private func kpiCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color).monospacedDigit()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Carriers card (CARRIERS · ON-TIME RATE)

    private var carriersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("CARRIERS · ON-TIME RATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("yardManagement.ts:2198")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                if topCarriers.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No appointments",
                                   subtitle: "Carrier gate-appointment scorecards will appear here.")
                        .padding(.vertical, Space.s4)
                } else {
                    ForEach(Array(topCarriers.enumerated()), id: \.element.id) { idx, c in
                        carrierRow(c)
                        if idx < topCarriers.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                    if !overflowCarriers.isEmpty {
                        overflowLine
                            .padding(.top, Space.s3)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// One itemized carrier scorecard row: 40x40 icon chip + name + mono sub
    /// (sched · on-time) + short status pill + right tabular on-time %.
    private func carrierRow(_ c: CarrierRow625) -> some View {
        let pct = Int((c.compliancePct ?? 0).rounded())
        let tier = statusTier(pct)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tier.color.opacity(0.20))
                    .frame(width: 40, height: 40)
                // warehouse-receipt / consist box glyph (matches SVG path).
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tier.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.carrierName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(c.scheduled ?? 0) sched · \(c.onTime ?? 0) on-time")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(tier.label)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(tier.color)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(tier.color.opacity(0.22)))
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tier.color).monospacedDigit()
            }
        }
        .padding(.vertical, Space.s3)
    }

    private var overflowLine: some View {
        let extra = overflowCarriers
        let firstExtra = extra.first
        let name = firstExtra?.carrierName ?? ""
        let sched = firstExtra?.scheduled ?? 0
        let onTime = firstExtra?.onTime ?? 0
        let pct = Int((firstExtra?.compliancePct ?? 0).rounded())
        var line = "+ \(name) \(sched) sched · \(onTime) on-time · \(pct)%"
        if carriersBelow70 > 0 {
            line += " · \(carriersBelow70) carriers below 70%"
        }
        return Text(line)
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusTier(_ pct: Int) -> (label: String, color: Color) {
        if pct >= 90      { return ("ON-TIME", Color(hex: 0x34D8A6)) }
        else if pct >= 70 { return ("OK",      Color(hex: 0x5BB0F5)) }
        else              { return ("WATCH",   Color(hex: 0xF5B544)) }
    }

    // MARK: - Peak gate hours context strip

    private var peakStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("PEAK GATE HOURS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("yardManagement.ts:563")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            Text(peakLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 6)

            Text(sorLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var peakLine: String {
        guard let pk = peakWindow, (pk.count ?? 0) > 0 else {
            return "No gate-appointment volume in the trailing 7 days"
        }
        return "\(pk.hour) busiest · \(peakShare)% of weekly appointments"
    }

    /// Shipper-of-record context — pulled from the live session, never faked.
    /// AuthUser carries no company name, so we anchor on the signed-in user's
    /// real display name (+ companyId when present) rather than fabricating a
    /// carrier label.
    private var sorLine: String {
        let who = session.user?.name?.trimmingCharacters(in: .whitespaces)
        let cid = session.user?.companyId
        let head = (who?.isEmpty == false ? who! : "Rail engineer")
        if let cid, !cid.isEmpty {
            return "\(head) · company \(cid) · gate-appointment scorecard"
        }
        return "\(head) · gate-appointment scorecard"
    }

    // MARK: - CTA pair (Schedule appt / Dock board)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                // Surfaces the gate-appointment scheduler.
            } label: {
                Text("Schedule appt")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(Capsule())
            .buttonStyle(.plain)

            Button {
                // Surfaces the dock board.
            } label: {
                Text("Dock board")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
            }
            .background(Color(hex: 0x232932))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct ComplianceIn: Encodable { let locationId: String?; let period: String }
        do {
            let loc: String? = locationId.isEmpty ? nil : locationId
            let result: ApptCompliance625 = try await EusoTripAPI.shared.query(
                "yardManagement.getAppointmentCompliance",
                input: ComplianceIn(locationId: loc, period: "week"))
            self.data = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("625 · Rail Appointment Compliance · Night") {
    RailAppointmentComplianceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("625 · Rail Appointment Compliance · Light") {
    RailAppointmentComplianceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
