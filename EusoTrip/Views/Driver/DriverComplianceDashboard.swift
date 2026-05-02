//
//  DriverComplianceDashboard.swift
//  EusoTrip — Driver-side compliance status surface.
//
//  Closes Phase 20 (Compliance signals) of the 8000-scenario shipper↔
//  driver parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md §4.7).
//  Phase 20 was PARTIAL because the shipper had `216_ShipperCompliance`
//  with FMCSA + insurance + hazmat alerts surfaced, while the driver
//  only saw push notifications on the `safety` channel — no in-app
//  consolidated dashboard for THEIR own compliance posture.
//
//  Surface anatomy:
//    1. Title block — "Compliance posture" + last-sync sub-line
//    2. HOS card — drive / on-duty / cycle remaining via hos.getStatus
//    3. Insurance card — expiry date + days remaining (CLEAR / WATCH
//       / WARN / EXPIRED) from drivers.getMyCarrier
//    4. Hazmat card — endorsement expiry + days remaining
//    5. TWIC card — TWIC card expiry + days remaining
//    6. Carrier card — DOT / MC / compliance status from
//       drivers.getMyCarrier
//
//  Severity vocabulary keys off the *DaysRemaining fields the server
//  evaluates: <=0 → EXPIRED red, <=7 → WARN red, <=30 → WATCH amber,
//  >30 → CLEAR green, nil → "Not on file" neutral.
//
//  Production-grade per [feedback_swiftui_previews] mandate. Dark +
//  Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DriverComplianceDashboard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var hos: HOSStatus? = nil
    @State private var carrier: DriversAPI.MyCarrier? = nil
    @State private var loading: Bool = false
    @State private var error: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                titleBlock
                if loading && hos == nil && carrier == nil {
                    skeletonStack
                } else {
                    hosCard
                    insuranceCard
                    hazmatCard
                    twicCard
                    carrierCard
                }
                if let err = error {
                    errorBanner(err)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Cards

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("✦ DRIVER · COMPLIANCE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Text("Compliance posture")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
            Text(syncSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncSubline: String {
        let name = session.user?.name ?? "Driver"
        return loading ? "\(name) · syncing FMCSA + HOS…" : "\(name) · last sync just now"
    }

    @ViewBuilder
    private var hosCard: some View {
        let h = hos
        statusCard(
            eyebrow: "HOS · ELECTRONIC LOG",
            title: hosHeadline(h),
            subtitle: hosSub(h),
            badge: hosStatusBadge(h)
        )
    }

    private func hosHeadline(_ h: HOSStatus?) -> String {
        guard let h = h else { return "Connect ELD to see live clock" }
        return "\(formatHHMM(h.drivingRemaining)) drive · \(formatHHMM(h.onDutyRemaining)) on-duty"
    }

    private func hosSub(_ h: HOSStatus?) -> String {
        guard let h = h else { return "—" }
        return String(format: "%.1fh cycle remaining · %@", h.cycleRemaining, h.status.uppercased())
    }

    private func hosStatusBadge(_ h: HOSStatus?) -> StatusBadge {
        guard let h = h else { return .init(label: "PENDING", color: palette.textSecondary) }
        let drive = h.drivingRemaining
        if drive <= 0  { return .init(label: "EXPIRED", color: Brand.danger) }
        if drive < 1.0 { return .init(label: "WARN",    color: Brand.danger) }
        if drive < 2.0 { return .init(label: "WATCH",   color: Brand.warning) }
        return .init(label: "CLEAR", color: Brand.success)
    }

    private var insuranceCard: some View {
        statusCard(
            eyebrow: "INSURANCE · CARRIER POLICY",
            title: expiryTitle(carrier?.insuranceExpiry, days: carrier?.insuranceDaysRemaining),
            subtitle: expirySub(label: "Insurance certificate", days: carrier?.insuranceDaysRemaining),
            badge: expiryBadge(carrier?.insuranceDaysRemaining)
        )
    }

    private var hazmatCard: some View {
        statusCard(
            eyebrow: "HAZMAT ENDORSEMENT",
            title: expiryTitle(carrier?.hazmatExpiry, days: carrier?.hazmatDaysRemaining),
            subtitle: expirySub(label: "H endorsement", days: carrier?.hazmatDaysRemaining),
            badge: expiryBadge(carrier?.hazmatDaysRemaining)
        )
    }

    private var twicCard: some View {
        statusCard(
            eyebrow: "TWIC · TSA",
            title: expiryTitle(carrier?.twicExpiry, days: carrier?.twicDaysRemaining),
            subtitle: expirySub(label: "TWIC card", days: carrier?.twicDaysRemaining),
            badge: expiryBadge(carrier?.twicDaysRemaining)
        )
    }

    @ViewBuilder
    private var carrierCard: some View {
        let dot: String = carrier?.dotNumber ?? "—"
        let mc:  String = carrier?.mcNumber ?? "—"
        let name = carrier?.legalName ?? carrier?.name ?? "Carrier of record"
        let cstatus = (carrier?.complianceStatus ?? "—").uppercased()
        statusCard(
            eyebrow: "CARRIER · FMCSA SAFER",
            title: name,
            subtitle: "USDOT \(dot) · MC \(mc)",
            badge: complianceBadge(cstatus)
        )
    }

    // MARK: - Severity logic

    private struct StatusBadge {
        let label: String
        let color: Color
    }

    private func expiryTitle(_ iso: String?, days: Int?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "Not on file" }
        // Trim ISO to YYYY-MM-DD when possible.
        let date = iso.split(separator: "T").first.map(String.init) ?? iso
        if let d = days {
            return "Expires \(date) · \(d)d"
        }
        return "Expires \(date)"
    }

    private func expirySub(label: String, days: Int?) -> String {
        guard let d = days else { return "\(label) · expiration date pending carrier sync" }
        if d <= 0   { return "\(label) · LAPSED — renewal blocking new loads" }
        if d <= 7   { return "\(label) · expires within 7 days — renew this week" }
        if d <= 30  { return "\(label) · expires within 30 days — renew soon" }
        return "\(label) · current"
    }

    private func expiryBadge(_ days: Int?) -> StatusBadge {
        guard let d = days else { return .init(label: "—",       color: palette.textSecondary) }
        if d <= 0   { return .init(label: "EXPIRED", color: Brand.danger) }
        if d <= 7   { return .init(label: "WARN",    color: Brand.danger) }
        if d <= 30  { return .init(label: "WATCH",   color: Brand.warning) }
        return            .init(label: "CLEAR",     color: Brand.success)
    }

    private func complianceBadge(_ status: String) -> StatusBadge {
        let s = status.lowercased()
        if s.contains("active") || s.contains("authorized") || s.contains("clear") {
            return .init(label: "CLEAR", color: Brand.success)
        }
        if s.contains("conditional") || s.contains("watch") {
            return .init(label: "WATCH", color: Brand.warning)
        }
        if s.contains("revoked") || s.contains("suspended") || s.contains("unsatisfactory") {
            return .init(label: "BLOCKED", color: Brand.danger)
        }
        return .init(label: "—", color: palette.textSecondary)
    }

    // MARK: - Card primitive

    private func statusCard(
        eyebrow: String,
        title: String,
        subtitle: String,
        badge: StatusBadge
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(badge.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(badge.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badge.color.opacity(0.14),
                                in: Capsule())
            }
            Text(title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var skeletonStack: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCardSoft)
                    .frame(height: 88)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Helpers

    private func formatHHMM(_ hours: Double) -> String {
        let total = max(0, Int(hours * 60))
        let h = total / 60
        let m = total % 60
        return String(format: "%dh %02dm", h, m)
    }

    // MARK: - Network

    private func load() async {
        loading = true
        defer { loading = false }
        async let hosT: HOSStatus? = (try? await EusoTripAPI.shared.hos.getStatus())
        async let carrierT: DriversAPI.MyCarrier? = (try? await EusoTripAPI.shared.drivers.getMyCarrier()) ?? nil
        let h = await hosT
        let c = await carrierT
        await MainActor.run {
            hos = h
            carrier = c
        }
    }
}

// MARK: - Previews

#Preview("Driver compliance · Dark") {
    DriverComplianceDashboard()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Driver compliance · Light") {
    DriverComplianceDashboard()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
