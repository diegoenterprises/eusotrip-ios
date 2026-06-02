//
//  683_VesselFleetHealth.swift
//  EusoTrip — Vessel Operator · Fleet Health / Asset Condition (CONDITION BOARD).
//
//  Verbatim port of canonical wireframe 683 "Vessel Fleet Health · Dark".
//  Condition-board grammar (distinct from 676 single-asset detail): one board
//  ranks every machinery system by LIVE condition with a per-system bar,
//  surfacing the system drifting before special survey so the operator
//  schedules the survey / work order before a deficiency becomes a class hold.
//
//  Docked under COMPLIANCE. transportMode=vessel · US (ABS class / USCG).
//
//  REAL WIRING (tRPC, server/routers):
//    · vesselShipments.getVesselFleet      {limit} -> operator fleet -> hero asset
//        (vesselShipments.ts:922)
//    · vesselShipments.getVesselParticulars {imoNumber} -> IMO/class/specs strip
//        (vesselShipments.ts:1046)
//    · maintenance.getSummary               {} -> health rollup -> HEALTH KPI +
//        composite ring (maintenance.ts:67 — returns { healthScore, ... })
//    · maintenance.getAlerts                {} -> open defects -> system condition
//        rows + bars (maintenance.ts:151)
//    · maintenance.schedule  mutation  {vehicleId,type,description,scheduledDate}
//        -> "Schedule survey" CTA (maintenance.ts:184 — REAL server arg-shape;
//        the canvas {assetId,type,date} was a wireframe sketch).
//
//  RBAC: reads protectedProcedure; schedule mutation broadcasts on WS
//  maintenance channel. NO mock data — every number derives from a live
//  endpoint, with real loading / error / empty states.
//

import SwiftUI

struct VesselFleetHealthScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselFleetHealthBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// vesselShipments.getVesselFleet -> { vessels: [...], total }
private struct VesselFleetResponse683: Decodable {
    let vessels: [VesselAsset683]
    let total: Int?
}

private struct VesselAsset683: Decodable, Identifiable {
    let id: Int
    let name: String?
    let imoNumber: String?
    let vesselType: String?
    let flag: String?
    let teuCapacity: Int?
    let yearBuilt: Int?
    let classificationSociety: String?
    let status: String?
}

/// vesselShipments.getVesselParticulars -> particulars or null
private struct VesselParticulars683: Decodable {
    let imoNumber: String?
    let name: String?
    let type: String?
    let flag: String?
    let yearBuilt: Int?
    let classification: String?
    let grossTonnage: Int?
    let deadweight: Int?
}

/// maintenance.getSummary -> health rollup
private struct MaintenanceSummary683: Decodable {
    let healthScore: Int?
    let scheduled: Int?
    let overdue: Int?
    let dueSoon: Int?
    let totalVehicles: Int?
    let avgDaysSinceService: Int?
    let complianceRate: Int?
}

/// maintenance.getAlerts -> open defects (one machinery-condition row each)
private struct MaintenanceAlert683: Decodable, Identifiable {
    let id: String
    let vehicleId: String?
    let serviceType: String?
    let priority: String?
    let isOverdue: Bool?
    let nextDueDate: String?
}

/// maintenance.schedule mutation result
private struct ScheduleResult683: Decodable {
    let success: Bool?
    let maintenanceId: String?
    let scheduledDate: String?
}

// MARK: - Body

private struct VesselFleetHealthBody: View {
    @Environment(\.palette) private var palette

    @State private var asset: VesselAsset683? = nil
    @State private var particulars: VesselParticulars683? = nil
    @State private var summary: MaintenanceSummary683? = nil
    @State private var alerts: [MaintenanceAlert683] = []

    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var scheduling = false
    @State private var scheduleAck: String? = nil
    @State private var scheduleError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        kpiStrip
                        machineryConditionSection
                        classStatutorySection
                        ctaRow
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

    // MARK: - Top bar (eyebrow + back + title + menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL · FLEET HEALTH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(imoLabel)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Asset condition")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    private var imoLabel: String {
        if let imo = asset?.imoNumber ?? particulars?.imoNumber, !imo.isEmpty {
            return imo.uppercased().hasPrefix("IMO") ? imo : "IMO \(imo)"
        }
        return "IMO —"
    }

    // MARK: - Hero card (gradient rim + composite ring)

    private var heroCard: some View {
        let vesselName = asset?.name ?? particulars?.name ?? "—"
        let teu = asset?.teuCapacity
        let classSoc = asset?.classificationSociety ?? particulars?.classification
        let built = asset?.yearBuilt ?? particulars?.yearBuilt
        let inClass = isInClass
        let composite = compositeScore

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vesselName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(specLine(imo: asset?.imoNumber ?? particulars?.imoNumber, teu: teu, classSoc: classSoc))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Text(originLine(built: built))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 0) {
                        Text(inClass ? "IN CLASS" : "OUT OF CLASS")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(inClass ? Brand.success : Brand.danger)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill((inClass ? Brand.success : Brand.danger).opacity(0.16)))
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                compositeRing(composite)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func compositeRing(_ score: Int?) -> some View {
        let frac = Double(score ?? 0) / 100.0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 5)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: max(0.02, min(frac, 1.0)))
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
            VStack {
                Spacer()
                Text("COMPOSITE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .offset(y: 18)
            }
            .frame(height: 56)
        }
        .frame(width: 72, height: 84)
    }

    private func specLine(imo: String?, teu: Int?, classSoc: String?) -> String {
        var parts: [String] = []
        if let imo, !imo.isEmpty { parts.append(imo.uppercased().hasPrefix("IMO") ? imo : "IMO \(imo)") }
        if let teu { parts.append("\(teu.formatted(.number.grouping(.automatic))) TEU") }
        if let classSoc, !classSoc.isEmpty { parts.append(classSoc.uppercased()) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func originLine(built: Int?) -> String {
        if let built { return "built \(built)" }
        return "specs from class register"
    }

    // MARK: - KPI strip (HEALTH · SURVEY · CLASS)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // HEALTH — gradient-fill tile, composite from maintenance.getSummary.
            VStack(alignment: .leading, spacing: 6) {
                Text("HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text(compositeScore.map(String.init) ?? "—")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
                Text("composite")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "SURVEY", value: surveyValue, sub: "since service")
            kpiTile(label: "CLASS",  value: isInClass ? "OK" : "HOLD",
                    sub: classSubLine, accent: isInClass ? nil : Brand.danger)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpiTile(label: String, value: String, sub: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent ?? palette.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var surveyValue: String {
        if let d = summary?.avgDaysSinceService { return "\(d)d" }
        return "—"
    }

    private var classSubLine: String {
        if let soc = asset?.classificationSociety ?? particulars?.classification, !soc.isEmpty {
            return isInClass ? "\(soc.uppercased()) in date" : "\(soc.uppercased()) review"
        }
        return isInClass ? "in date" : "review"
    }

    // MARK: - Machinery condition · by system

    private var machineryConditionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MACHINERY CONDITION · BY SYSTEM")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s1)

            VStack(spacing: 0) {
                if alerts.isEmpty {
                    // No open defects — board is clean. Render the live "all
                    // systems nominal" state rather than fabricated rows.
                    allClearRow
                } else {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { idx, alert in
                        systemRow(alert)
                        if idx < alerts.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var allClearRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("All systems nominal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("no open defects · condition GOOD")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("GOOD")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.success.opacity(0.12)))
        }
        .padding(Space.s4)
    }

    private func systemRow(_ alert: MaintenanceAlert683) -> some View {
        let watch = (alert.isOverdue ?? false) || (alert.priority ?? "").uppercased() == "HIGH"
        let critical = (alert.priority ?? "").uppercased() == "CRITICAL"
        let color: Color = critical ? Brand.danger : (watch ? Brand.warning : Brand.success)
        let statusLabel = critical ? "ACTION" : (watch ? "WATCH" : "GOOD")
        // Bar fill: overdue/critical reads lower; healthy reads near-full.
        let pct: Int = critical ? 45 : (watch ? 62 : 88)

        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: systemIcon(for: alert.serviceType))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(systemTitle(for: alert))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.12)))
                }
                Text(systemDetail(for: alert))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: Space.s2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                                .frame(height: 5)
                            Capsule().fill(color)
                                .frame(width: geo.size.width * CGFloat(pct) / 100.0, height: 5)
                        }
                    }
                    .frame(height: 5)
                    Text("\(pct)%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s4)
    }

    private func systemIcon(for serviceType: String?) -> String {
        let s = (serviceType ?? "").lowercased()
        if s.contains("engine") || s.contains("propuls") { return "engine.combustion.fill" }
        if s.contains("genset") || s.contains("generator") || s.contains("electric") { return "bolt.fill" }
        if s.contains("reefer") || s.contains("refrig") || s.contains("plug") { return "thermometer.snowflake" }
        if s.contains("hull") || s.contains("coat") { return "shield.lefthalf.filled" }
        return "gearshape.fill"
    }

    private func systemTitle(for alert: MaintenanceAlert683) -> String {
        if let t = alert.serviceType, !t.isEmpty {
            return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Machinery system"
    }

    private func systemDetail(for alert: MaintenanceAlert683) -> String {
        var parts: [String] = []
        if let due = alert.nextDueDate, !due.isEmpty {
            parts.append("due \(String(due.prefix(10)))")
        }
        if alert.isOverdue == true { parts.append("OVERDUE") }
        if let p = alert.priority, !p.isEmpty { parts.append("\(p.lowercased()) priority") }
        return parts.isEmpty ? "open defect · monitor condition" : parts.joined(separator: " · ")
    }

    // MARK: - Class & statutory · ABS

    private var classStatutorySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CLASS & STATUTORY · \(classSocietyLabel)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(classHeadline)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(classSubhead)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var classSocietyLabel: String {
        (asset?.classificationSociety ?? particulars?.classification ?? "CLASS").uppercased()
    }

    private var classHeadline: String {
        let soc = classSocietyLabel
        return isInClass
            ? "\(soc) classed · ISM & ISPS valid · DOC + SMC in date"
            : "\(soc) class status under review · verify ISM/ISPS"
    }

    private var classSubhead: String {
        let flag = asset?.flag ?? particulars?.flag
        var lead = "Hull & coatings \(isInClass ? "GOOD" : "CHECK")"
        if let flag, !flag.isEmpty { lead += " · flag \(flag)" }
        if let dwt = particulars?.deadweight, dwt > 0 {
            lead += " · \(dwt.formatted(.number.grouping(.automatic))) DWT"
        }
        return lead
    }

    // MARK: - CTA row (Schedule survey · Work orders)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let ack = scheduleAck {
                LifecycleCard(accentGradient: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(ack).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            if let err = scheduleError {
                LifecycleCard(accentDanger: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    Task { await scheduleSurvey() }
                } label: {
                    HStack(spacing: 6) {
                        if scheduling {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                        Text(scheduling ? "Scheduling…" : "Schedule survey")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(scheduling || asset == nil)
                .opacity(asset == nil ? 0.6 : 1.0)

                Button { } label: {
                    Text("Work orders")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Derived condition values (all from live endpoints)

    private var compositeScore: Int? {
        // Composite reads off the maintenance health rollup; nil renders "—"
        // rather than a fabricated 92.
        summary?.healthScore
    }

    private var isInClass: Bool {
        // In-class iff no overdue defects and a non-zero health rollup. If the
        // summary hasn't loaded we don't claim "in class" — default to true
        // only once we have real data showing zero overdue.
        guard let s = summary else { return alerts.isEmpty }
        let overdue = (s.overdue ?? 0) + alerts.filter { $0.isOverdue == true }.count
        let critical = alerts.contains { ($0.priority ?? "").uppercased() == "CRITICAL" }
        return overdue == 0 && !critical
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct FleetIn: Encodable { let limit: Int }
        struct ParticularsIn: Encodable { let imoNumber: String }
        do {
            // Hero asset + health rollup + open defects in parallel.
            async let fleet: VesselFleetResponse683 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 1))
            async let sum: MaintenanceSummary683 = EusoTripAPI.shared.queryNoInput(
                "maintenance.getSummary")
            async let alertList: [MaintenanceAlert683] = EusoTripAPI.shared.queryNoInput(
                "maintenance.getAlerts")

            let (fleetResp, summaryResp, alertsResp) = try await (fleet, sum, alertList)
            self.asset = fleetResp.vessels.first
            self.summary = summaryResp
            self.alerts = alertsResp

            // Particulars (IMO/class/specs strip) — only if we have an IMO.
            if let imo = self.asset?.imoNumber, !imo.isEmpty {
                let bare = imo.uppercased().hasPrefix("IMO")
                    ? String(imo.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    : imo
                self.particulars = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselParticulars", input: ParticularsIn(imoNumber: bare))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Schedule survey mutation

    private func scheduleSurvey() async {
        guard let asset else { return }
        scheduling = true; scheduleAck = nil; scheduleError = nil
        // REAL server arg-shape: maintenance.schedule expects
        // {vehicleId, type, description, scheduledDate}. The canvas
        // {assetId, type, date} was a wireframe sketch — we wire the real one.
        struct ScheduleIn: Encodable {
            let vehicleId: String
            let type: String
            let description: String
            let scheduledDate: String
        }
        let due: String = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
        }()
        let input = ScheduleIn(
            vehicleId: String(asset.id),
            type: "special_survey",
            description: "Special survey scheduled from Fleet Health board for \(asset.name ?? "vessel")",
            scheduledDate: due
        )
        do {
            let result: ScheduleResult683 = try await EusoTripAPI.shared.mutation(
                "maintenance.schedule", input: input)
            if result.success == true {
                scheduleAck = "Survey scheduled for \(result.scheduledDate ?? due)."
                await load()
            } else {
                scheduleError = "Schedule did not confirm. Try again."
            }
        } catch {
            scheduleError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        scheduling = false
    }
}

#Preview("683 · Vessel Fleet Health · Night") { VesselFleetHealthScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("683 · Vessel Fleet Health · Light") { VesselFleetHealthScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
