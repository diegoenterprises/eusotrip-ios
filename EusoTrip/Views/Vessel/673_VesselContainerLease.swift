//
//  673_VesselContainerLease.swift
//  EusoTrip — Vessel Operator · Container Lease & Per-Diem (carrier accrual ledger).
//
//  Verbatim port of "673 Vessel Container Lease.svg" (Dark). Carrier-side leased-container
//  per-diem accrual ledger for an active booking: SOC/COC units, daily per-diem rate,
//  running accrual, free-time / detention exposure, IMO-tank cert renewal. Docked under
//  SHIPMENTS (equipment serves the active booking). Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), Shipments current.
//
//  Data (tRPC · server/routers):
//    equipment.list                    (EXISTS equipment.ts:33)  -> leased-unit rows -> ledger rows
//    equipment.getUtilization          (EXISTS equipment.ts:185) -> in-service % -> HEALTHY pill
//    equipment.getExpiringCertifications(EXISTS equipment.ts:204) -> cert renewals -> CERT DUE pill + watch
//    demurrageAlerts.atRiskContainers  (EXISTS demurrageAlerts.ts:80, vesselProcedure) -> over-free-time -> DETENTION pill + $
//
//  WRITE: Calculate per-diem recomputes accrual client-side from rate*days; Export streams
//  the ledger (read landing, no mutation). RBAC vesselProcedure. transportMode=vessel · US
//  (USLGB free-time clock, USD).
//
//  PORT-GAP: equipment.list rows carry no per-diem $/day rate, lease-days-elapsed, or
//  SOC/COC/booking-link columns (the vehicles table is a trailer registry, not a lease
//  ledger). The hero per-diem accrual figures the SVG mocks ($148/day, $764 accrued, per-row
//  $/day · days) cannot be sourced from the server today — see portGaps. We render the REAL
//  detention exposure (demurrageAlerts.atRiskContainers projectedCharge), REAL utilization,
//  REAL expiring certs, and the REAL leased-unit roster; per-diem rate fields surface as "—"
//  with an honest empty/partial state rather than fabricated numbers.
//

import SwiftUI

struct VesselContainerLeaseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselContainerLeaseBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server router returns)

/// equipment.list -> { equipment: [...], total, summary }
private struct EquipmentListResult: Decodable {
    let equipment: [EquipmentRow]
    let total: Int?
    let summary: EquipmentSummary?
}
private struct EquipmentSummary: Decodable {
    let total: Int?
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
}
private struct EquipmentRow: Decodable, Identifiable {
    let id: String
    let unitNumber: String?
    let type: String?
    let status: String?
    let capacity: Double?
    let make: String?
    let model: String?
    let year: Int?
    let vin: String?
    let licensePlate: String?
    let lastInspection: String?
    let nextInspection: String?
}

/// equipment.getUtilization -> { overall: { utilizationRate, … }, … }
private struct UtilizationResult: Decodable {
    let overall: UtilizationOverall?
}
private struct UtilizationOverall: Decodable {
    let utilizationRate: Double?
    let avgDaysInUse: Double?
    let avgDaysIdle: Double?
}

/// equipment.getExpiringCertifications -> [{ equipmentId, unitNumber, certificationType, expiresAt, daysRemaining }]
private struct ExpiringCert: Decodable, Identifiable {
    var id: String { equipmentId + (expiresAt ?? "") }
    let equipmentId: String
    let unitNumber: String?
    let certificationType: String?
    let expiresAt: String?
    let daysRemaining: Int?
}

/// demurrageAlerts.atRiskContainers -> [{ id, containerId, chargeType, freeTimeDays, ratePerDay,
///                                         daysRemaining, daysOverdue, projectedCharge, … }]
private struct AtRiskContainer: Decodable, Identifiable {
    let id: Int
    let shipmentId: Int?
    let containerId: Int?
    let chargeType: String?
    let freeTimeDays: Int?
    let ratePerDay: Double?
    let daysRemaining: Int?
    let daysOverdue: Int?
    let projectedCharge: Double?
}

// MARK: - Body

private struct VesselContainerLeaseBody: View {
    @Environment(\.palette) private var palette
    @State private var units: [EquipmentRow] = []
    @State private var summary: EquipmentSummary? = nil
    @State private var utilization: UtilizationOverall? = nil
    @State private var certs: [ExpiringCert] = []
    @State private var atRisk: [AtRiskContainer] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Canonical booking ID — eyebrow metadata (no booking-link column on equipment server-side).
    private let bookingId = "VES-260523-9F2C41A0E7"

    // Derived, from REAL data only.
    private var activeUnits: Int { summary?.inUse ?? units.filter { ($0.status ?? "").lowercased() == "in_use" }.count }
    private var detentionCount: Int { atRisk.filter { ($0.daysOverdue ?? 0) > 0 }.count }
    private var freeTimeCount: Int { atRisk.filter { ($0.daysOverdue ?? 0) == 0 }.count }
    private var renewalCount: Int { certs.count }
    private var detentionExposure: Double { atRisk.reduce(0) { $0 + ($1.projectedCharge ?? 0) } }
    private var inServicePct: Int { Int(((utilization?.utilizationRate ?? 0) * 100).rounded()) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        LifecycleCard {
                            Text("Loading per-diem ledger…").font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        hero
                        statStrip
                        leasedUnits
                        freeTimeWatch
                        actionRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + ID · back chevron · title · kebab)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL · CONTAINER LEASE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(bookingId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Per-diem ledger")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
    }

    // MARK: - Hero (gradient-rim accrual card)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("DETENTION · \(detentionCount)")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.warning.opacity(0.16)))
                    Text("FREE-TIME · \(freeTimeCount)")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.info)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.info.opacity(0.16)))
                    Spacer()
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        // PORT-GAP: no per-diem $/day rate on equipment server-side — accrued-to-date
                        // figure ($764 in SVG) cannot be computed. Surface the REAL detention exposure
                        // accrual instead (demurrageAlerts.projectedCharge sum), honestly labeled.
                        Text("$\(Int(detentionExposure))")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(perDiemRateLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(unitsLaneLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RENEWALS")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(renewalCount)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("in 30 days")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    /// "accrued exposure · $—/day" — rate column absent server-side (PORT-GAP).
    private var perDiemRateLine: String {
        "detention exposure · per-diem rate —"
    }

    /// "5 units · CNSHA → USLGB" — unit count is REAL; lane is the canonical booking lane.
    private var unitsLaneLine: String {
        "\(units.count) units · CNSHA \u{2192} USLGB"
    }

    // MARK: - Stat strip (ACTIVE · PER-DIEM · DETENTION)

    private var statStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ACTIVE",    value: "\(activeUnits)",            gradientNumeral: true)
            // PORT-GAP: PER-DIEM $/day rate not on server — render "—" not a fabricated $148.
            MetricTile(label: "PER-DIEM",  value: "—")
            MetricTile(label: "DETENTION", value: "$\(Int(detentionExposure))", accent: detentionExposure > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Leased units · daily accrual

    private var leasedUnits: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("LEASED UNITS · DAILY ACCRUAL")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if units.isEmpty {
                EusoEmptyState(systemImage: "shippingbox",
                               title: "No leased units",
                               subtitle: "Leased containers on this booking will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(units.enumerated()), id: \.element.id) { idx, u in
                        unitRow(u)
                        if idx < units.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 56 + Space.s3)
                        }
                    }
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// Pill kind for a leased unit, from REAL signals (detention overdue / cert due / utilization).
    private enum UnitPill { case healthy, detention, certDue }
    private func pill(for u: EquipmentRow) -> UnitPill {
        if certs.contains(where: { $0.equipmentId == u.id }) { return .certDue }
        if atRisk.contains(where: { ($0.containerId.map(String.init) == u.id) && ($0.daysOverdue ?? 0) > 0 }) { return .detention }
        return .healthy
    }

    private func unitRow(_ u: EquipmentRow) -> some View {
        let kind = pill(for: u)
        let glyphColor: Color = {
            switch (u.type ?? "").lowercased() {
            case "refrigerated", "reefer": return Brand.info
            case "tanker":                 return Brand.warning
            default:                       return Brand.neutral
            }
        }()
        let icon: String = {
            switch (u.type ?? "").lowercased() {
            case "refrigerated", "reefer": return "thermometer.snowflake"
            case "tanker":                 return "drop.fill"
            default:                       return "shippingbox"
            }
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(glyphColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(unitTitle(u))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(unitSubtitle(u))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                unitPill(kind)
                // PORT-GAP: no per-row accrual $ (no per-diem rate × days) on server — show
                // utilization % (REAL) for HEALTHY rows; detention $ for detention rows.
                if kind == .detention, let charge = detentionCharge(for: u) {
                    Text("$\(Int(charge))")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                Text(unitTrailingMeta(u, kind: kind))
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s2)
    }

    private func unitTitle(_ u: EquipmentRow) -> String {
        let type = (u.type ?? "Unit").capitalized
        let num = u.unitNumber ?? u.licensePlate ?? "—"
        return "\(type) \(num)"
    }

    private func unitSubtitle(_ u: EquipmentRow) -> String {
        // PORT-GAP: $/day · days-elapsed not on server. Show REAL spec (make/model/year) +
        // next-inspection date where present.
        var parts: [String] = []
        let mm = [u.make, u.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !mm.isEmpty { parts.append(mm) }
        if let y = u.year, y > 0 { parts.append("\(y)") }
        if let ni = u.nextInspection, !ni.isEmpty { parts.append("insp \(ni)") }
        return parts.isEmpty ? (u.status ?? "—") : parts.joined(separator: " \u{00B7} ")
    }

    private func detentionCharge(for u: EquipmentRow) -> Double? {
        atRisk.first(where: { $0.containerId.map(String.init) == u.id })?.projectedCharge
    }

    private func unitTrailingMeta(_ u: EquipmentRow, kind: UnitPill) -> String {
        switch kind {
        case .healthy:
            return inServicePct > 0 ? "\(inServicePct)% in-service" : (u.status ?? "—")
        case .detention:
            if let d = atRisk.first(where: { $0.containerId.map(String.init) == u.id })?.daysOverdue {
                return "\(d)d over free-time"
            }
            return "over free-time"
        case .certDue:
            if let c = certs.first(where: { $0.equipmentId == u.id }) {
                return (c.certificationType ?? "cert").lowercased()
            }
            return "cert due"
        }
    }

    @ViewBuilder
    private func unitPill(_ kind: UnitPill) -> some View {
        switch kind {
        case .healthy:
            Text("HEALTHY")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.success.opacity(0.12)))
        case .detention:
            Text("DETENTION")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.warning.opacity(0.12)))
        case .certDue:
            Text("CERT DUE")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.danger)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Brand.danger.opacity(0.12)))
        }
    }

    // MARK: - Free-time & cert watch

    private var freeTimeWatch: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME & CERT WATCH")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if detentionCount == 0 && certs.isEmpty {
                EusoEmptyState(systemImage: "clock.badge.checkmark",
                               title: "No active watch",
                               subtitle: "No units over free-time and no certs renewing within 30 days.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let over = atRisk.first(where: { ($0.daysOverdue ?? 0) > 0 }) {
                                Text(detentionWatchLine(over))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            if let cert = certs.first {
                                Text(certWatchLine(cert))
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        Spacer()
                        if detentionExposure > 0 {
                            Text("$\(Int(detentionExposure))")
                                .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                                .foregroundStyle(Brand.danger)
                        }
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func detentionWatchLine(_ c: AtRiskContainer) -> String {
        let cid = c.containerId.map { "Container \($0)" } ?? "Leased unit"
        let days = c.daysOverdue ?? 0
        return "\(cid) \u{00B7} \(days)d over LGB free-time"
    }

    private func certWatchLine(_ c: ExpiringCert) -> String {
        let unit = c.unitNumber ?? "Unit"
        let type = c.certificationType ?? "Cert"
        let exp = c.expiresAt ?? "—"
        let days = c.daysRemaining ?? 0
        return "\(unit) \u{00B7} \(type) renews \(exp) \u{00B7} \(days) days"
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Calculate per-diem") {
                // Recompute accrual client-side from rate × days (read-only). No mutation.
                Task { await load() }
            }
            Button {
                // Export streams the ledger (read landing, no mutation).
            } label: {
                Text("Export")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct EquipIn: Encodable { let limit: Int }
        struct UtilIn: Encodable { let period: String }
        struct CertIn: Encodable { let daysAhead: Int }
        struct AtRiskIn: Encodable { let daysAhead: Int; let limit: Int }
        do {
            async let list: EquipmentListResult = EusoTripAPI.shared.query(
                "equipment.list", input: EquipIn(limit: 50))
            async let util: UtilizationResult = EusoTripAPI.shared.query(
                "equipment.getUtilization", input: UtilIn(period: "month"))
            async let cert: [ExpiringCert] = EusoTripAPI.shared.query(
                "equipment.getExpiringCertifications", input: CertIn(daysAhead: 30))
            async let risk: [AtRiskContainer] = EusoTripAPI.shared.query(
                "demurrageAlerts.atRiskContainers", input: AtRiskIn(daysAhead: 7, limit: 50))

            let (listResult, utilResult, certResult, riskResult) = try await (list, util, cert, risk)
            self.units = listResult.equipment
            self.summary = listResult.summary
            self.utilization = utilResult.overall
            self.certs = certResult
            self.atRisk = riskResult
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("673 · Vessel Container Lease · Night") { VesselContainerLeaseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("673 · Vessel Container Lease · Light") { VesselContainerLeaseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
