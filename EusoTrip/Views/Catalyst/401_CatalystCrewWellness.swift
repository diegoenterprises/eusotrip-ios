//
//  401_CatalystCrewWellness.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band.
//
//  Verbatim port of:
//    03 Catalyst/Code/401_CatalystCrewWellness.swift
//    03 Catalyst/Dark-SVG/401 Catalyst Crew Wellness.svg
//
//  Moment: the carrier watches a single fleet fatigue index and a per-driver
//  risk board so a tired driver surfaces BEFORE a roadside or a crash. This is
//  a BOARD archetype — a fitness-index hero with a red→amber→green risk band, a
//  compact sleep/HOS/check-in strip, and a crew roster ranked by score where
//  each driver carries an initials disc tinted by risk, on-duty/sleep/HOS
//  context, a big wellness score and a FIT/WATCH/REST pill. One tap schedules a
//  reset for the flagged unit.
//
//  Chrome-adapted to the iOS house: wrapper -> Shell { CrewWellnessBody_401() }
//  nav: { BottomNav(...) }. Catalyst variant — HOME · DISPATCH(current) ·
//  [orb] · WALLET · ME.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13):
//    • fleet index / at-risk / KPIs → driverWellness.getWellnessDashboard (driverWellness.ts:185)
//    • crew risk board + insight    → driverWellness.getFatigueAlerts     (driverWellness.ts:451)
//  Both decoded in-file against the exact server projections. The crew rows
//  ARE the live fatigue alerts (riskScore/riskLevel/reason) — the old seeded
//  Salazar/Brandt/Okafor roster never existed and is GONE. Fields without a
//  live source (on-duty-now) render an honest em-dash; honest EusoEmptyState
//  when no driver is flagged. transportMode=truck; FMCSA fatigue ruleset.
//

import SwiftUI

// MARK: - View model (board archetype)

private struct CrewMember_401: Identifiable {
    enum Risk { case fit, watch, rest }
    let id: String              // unit
    let driverId: String
    let initials: String        // "RS"
    let nameUnit: String        // live driver name · driver id
    let context: String         // mono on-duty/sleep/HOS line
    let score: Int              // 54
    let risk: Risk
    let riskLabel: String       // "REST" / "WATCH" / "FIT"
    let isOwnerOp: Bool         // ME gets the gradient disc
}

private struct CrewWellnessVM_401 {
    let headerSub: String           // live driver count line
    let fleetIndex: String          // live fleetAverageScore
    let atRisk: String              // live driversAtRisk
    let onDuty: String              // honest em-dash (no on-duty-now source)
    let bandMarkerFrac: Double      // fleetAverageScore / 100
    let bandCaption: String
    let safetyAvg: String           // live averageHosCompliance (safety-score avg)
    let safetyDelta: String         // live monthOverMonthChange
    let restQuality: String         // live averageRestQuality
    let checkIns: String            // live recentCheckIns + checkInRate
    let crew: [CrewMember_401]
    let insightTitle: String
    let insightSub: String

    /// Honest empty envelope — em-dash until a real hydrate lands.
    static let empty = CrewWellnessVM_401(
        headerSub: "— drivers · 7-day window",
        fleetIndex: "—", atRisk: "—", onDuty: "—",
        bandMarkerFrac: 0,
        bandCaption: "—",
        safetyAvg: "—", safetyDelta: "", restQuality: "—", checkIns: "—",
        crew: [],
        insightTitle: "No fatigue insight yet",
        insightSub: "Live duty data populates this board."
    )
}

// MARK: - Wire shapes (mirror driverWellness.ts projections exactly)

private struct WellnessDashboardWire_401: Decodable {
    struct Tracked: Decodable {
        let safety: Bool
        let inspections: Bool
        let rest: Bool
    }

    let fleetAverageScore: Double?
    let totalDrivers: Int
    let driversAtRisk: Double          // SUM(CASE…) Number()-wrapped server-side
    let averageHosCompliance: Double?
    let averageRestQuality: Double?
    let averageDrivingPatterns: Double?
    let monthOverMonthChange: Double?
    let recentCheckIns: Int
    let checkInRate: Double
    let tracked: Tracked?
}

private struct FatigueAlertsWire_401: Decodable {
    struct Alert: Decodable {
        let id: String
        let driverId: String
        let driverName: String
        let riskScore: Double
        let riskLevel: String          // "critical" | "elevated" | "moderate"
        let reason: String
    }
    let alerts: [Alert]
    let total: Int
}

// MARK: - Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME)

private func catalystNavLeading_401() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_401() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - Wrapper

struct CatalystCrewWellnessScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CrewWellnessBody_401()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_401(),
                trailing: catalystNavTrailing_401(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CrewWellnessBody_401: View {
    @Environment(\.palette) private var palette

    // Live VM — honest em-dash envelope until the real procs answer.
    @State private var vm: CrewWellnessVM_401 = .empty
    @State private var scheduling: Bool = false
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var showInsight = false
    @State private var showRestPlan = false
    @State private var showHistory = false
    @State private var historyRows: [WellnessHistoryRow_401] = []
    @State private var historyDriverId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard
                    kpiStrip
                    crewSection
                    insightRow
                    ctaPair
                    actionFeedback
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .eusoRefreshHandler { await loadAll() }
        .sheet(isPresented: $showInsight) { insightSheet }
        .sheet(isPresented: $showRestPlan) { restPlanSheet }
        .sheet(isPresented: $showHistory) { historySheet }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · WELLNESS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("FMCSA · FATIGUE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Dispatch")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crew Wellness").font(EType.display).foregroundStyle(palette.textPrimary)
                    Text(vm.headerSub)
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Hero · fleet fatigue index

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FLEET FITNESS INDEX · 7-DAY").font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(vm.fleetIndex).font(.system(size: 38, weight: .bold).monospacedDigit())
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("/100").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("AT RISK").font(EType.micro).tracking(0.6).foregroundStyle(Brand.danger)
                        Text(vm.atRisk).font(.system(size: 16, weight: .bold)).foregroundStyle(Brand.danger)
                        Text("ON DUTY NOW").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.onDuty).font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                riskBand.padding(.top, Space.s3)
                Text(vm.bandCaption).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 150)
    }

    private var riskBand: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Brand.danger, Brand.warning, Brand.success],
                                              startPoint: .leading, endPoint: .trailing))
                Circle().fill(.white).overlay(Circle().strokeBorder(palette.textPrimary, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: geo.size.width * vm.bandMarkerFrac - 7)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Fleet fitness \(vm.fleetIndex) of 100")
    }

    // MARK: KPI strip · 3 tiles

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiTile("SAFETY AVG", vm.safetyAvg, sub: vm.safetyDelta.isEmpty ? "30-day basis" : vm.safetyDelta,
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
            kpiTile("REST QUALITY", vm.restQuality, sub: "incident-derived",
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: palette.textSecondary)
            kpiTile("CHECK-INS", vm.checkIns, sub: "last 7 days",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
        }
    }

    private func kpiTile(_ label: String, _ value: String, sub: String,
                         valueStyle: AnyShapeStyle, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 28, weight: .semibold).monospacedDigit()).foregroundStyle(valueStyle)
            Text(sub).font(EType.caption).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Crew risk board

    private var crewSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CREW · FATIGUE RISK").font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ranked by risk").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.crew.isEmpty {
                    EusoEmptyState(
                        systemImage: "person.2.badge.gearshape",
                        title: loading ? "Scanning active duty…" : "No fatigue flags right now",
                        subtitle: loading ? "" : (loadError ?? "Drivers on active loads with notable fatigue risk appear here.")
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.crew.enumerated()), id: \.element.id) { idx, m in
                        crewRow(m)
                        if idx < vm.crew.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func riskColor(_ r: CrewMember_401.Risk) -> Color {
        switch r {
        case .fit:   return Brand.success
        case .watch: return Brand.warning
        case .rest:  return Brand.danger
        }
    }

    private func riskTintOpacity(_ r: CrewMember_401.Risk) -> Double {
        switch r {
        case .rest:  return 0.12
        case .watch: return 0.16
        case .fit:   return 0.14
        }
    }

    private func crewRow(_ m: CrewMember_401) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().fill(m.isOwnerOp ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(riskColor(m.risk).opacity(0.14)))
                Text(m.initials).font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(m.isOwnerOp ? AnyShapeStyle(Color.white) : AnyShapeStyle(riskColor(m.risk)))
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.nameUnit).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(m.context).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.s2)
            Text("\(m.score)").font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(riskColor(m.risk))
            Text(m.riskLabel).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(riskColor(m.risk))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(riskColor(m.risk).opacity(riskTintOpacity(m.risk))))
        }
        .padding(Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.nameUnit), score \(m.score), \(m.riskLabel)")
    }

    // MARK: ESang insight row

    private var insightRow: some View {
        Button { showInsight = true } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.insightTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }.buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                scheduling = true
                actionError = nil
                actionMessage = nil
                showRestPlan = true
                scheduling = false
            } label: {
                Text("Rest plan").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
                    .opacity(scheduling ? 0.6 : 1.0)
            }.buttonStyle(.plain).disabled(scheduling)
            Button {
                Task { await loadWellnessHistory() }
            } label: {
                Text("Wellness log").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let actionError {
            Text(actionError)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.danger.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.danger.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        } else if let actionMessage {
            Text(actionMessage)
                .font(EType.caption)
                .foregroundStyle(Brand.success)
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.success.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.success.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var insightSheet: some View {
        wellnessSheet(title: "Fatigue insight") {
            VStack(alignment: .leading, spacing: 8) {
                Text(vm.insightTitle).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(vm.insightSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                Text(vm.bandCaption).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var restPlanSheet: some View {
        wellnessSheet(title: "Rest plan") {
            VStack(alignment: .leading, spacing: 10) {
                if let driver = vm.crew.first {
                    Text(driver.nameUnit).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(driver.context).font(EType.caption).foregroundStyle(palette.textSecondary)
                    Text("Dispatch rest scheduling does not have a persisted write contract yet. Use this live risk packet to coordinate rest outside the app until that endpoint exists.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                    ForEach(restPlanItems(for: driver), id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
                            Text(item).font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    ShareLink(item: restPlanText(for: driver)) {
                        Label("Share rest plan", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(LinearGradient.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    EusoEmptyState(systemImage: "moon.zzz", title: "No rest plan needed", subtitle: "No active fatigue alert is loaded.")
                }
            }
        }
    }

    private var historySheet: some View {
        wellnessSheet(title: "Wellness log") {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let historyDriverId {
                    Text(historyDriverId).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                }
                if historyRows.isEmpty {
                    EusoEmptyState(systemImage: "list.clipboard", title: "No wellness check-ins", subtitle: "Stored wellness check-ins appear here once the driver has logged them.")
                } else {
                    ForEach(historyRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.date).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text("\(row.mood) · \(row.sleepHours, specifier: "%.1f")h sleep · stress \(row.stressLevel)")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
            }
        }
    }

    private func wellnessSheet<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showInsight = false
                        showRestPlan = false
                        showHistory = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Network (LIVE — driverWellness.getWellnessDashboard + getFatigueAlerts)

    private struct AlertsInput_401: Encodable { let severity: String; let limit: Int }
    private struct HistoryInput_401: Encodable { let driverId: String?; let days: Int }
    private struct WellnessHistoryWire_401: Decodable {
        let driverId: String?
        let history: [WellnessHistoryRow_401]
    }
    private struct WellnessHistoryRow_401: Decodable, Identifiable {
        let id: String
        let date: String
        let mood: String
        let sleepQuality: String
        let sleepHours: Double
        let stressLevel: String
        let physicalPain: Double?
        let exercised: Bool?
        let hydratedWell: Bool?
    }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        async let dashTask: WellnessDashboardWire_401 =
            EusoTripAPI.shared.queryNoInput("driverWellness.getWellnessDashboard")
        async let alertsTask: FatigueAlertsWire_401 =
            EusoTripAPI.shared.query("driverWellness.getFatigueAlerts",
                                     input: AlertsInput_401(severity: "all", limit: 10))

        do {
            let (dash, alertsWire) = try await (dashTask, alertsTask)

            let crew: [CrewMember_401] = alertsWire.alerts.map { a in
                let risk: CrewMember_401.Risk
                let label: String
                switch a.riskLevel {
                case "critical": risk = .rest;  label = "REST"
                case "elevated": risk = .watch; label = "WATCH"
                default:         risk = .fit;   label = "MONITOR"
                }
                return CrewMember_401(
                    id: a.id,
                    driverId: a.driverId,
                    initials: initials_401(a.driverName),
                    nameUnit: "\(a.driverName) · \(a.driverId)",
                    context: a.reason,
                    score: Int(a.riskScore.rounded()),
                    risk: risk,
                    riskLabel: label,
                    isOwnerOp: false
                )
            }

            let atRiskCount = Int(dash.driversAtRisk.rounded())
            let topAlert = alertsWire.alerts.first
            let fleetScore = dash.fleetAverageScore
            let safetyTracked = dash.tracked?.safety ?? (dash.averageHosCompliance != nil)
            vm = CrewWellnessVM_401(
                headerSub: "\(dash.totalDrivers) driver\(dash.totalDrivers == 1 ? "" : "s") · 7-day window",
                fleetIndex: fleetScore.map { "\(Int($0.rounded()))" } ?? "—",
                atRisk: safetyTracked ? "\(atRiskCount) driver\(atRiskCount == 1 ? "" : "s")" : "—",
                onDuty: "—",   // no on-duty-now rollup on any wired proc
                bandMarkerFrac: fleetScore.map { min(1.0, max(0.0, $0 / 100.0)) } ?? 0,
                bandCaption: !safetyTracked
                    ? "Safety scores have not been recorded"
                    : atRiskCount == 0
                    ? "No drivers below the safety floor this period"
                    : "\(atRiskCount) driver\(atRiskCount == 1 ? "" : "s") below the safety floor",
                safetyAvg: dash.averageHosCompliance.map { "\(Int($0.rounded()))" } ?? "—",
                safetyDelta: dash.monthOverMonthChange.map {
                    $0 == 0 ? "" : String(format: "%+.1f vs prior 30d", $0)
                } ?? "",
                restQuality: dash.averageRestQuality.map { "\(Int($0.rounded()))" } ?? "—",
                checkIns: "\(dash.recentCheckIns)",
                crew: crew,
                insightTitle: topAlert.map { "\($0.driverName) · risk \(Int($0.riskScore.rounded()))" }
                    ?? "No active-load fatigue signals",
                insightSub: topAlert?.reason ?? "No active load produced a fatigue alert."
            )
        } catch {
            vm = .empty
            loadError = "Couldn't reach the wellness service - retry."
        }
    }

    private func loadWellnessHistory() async {
        actionMessage = nil
        actionError = nil
        let driverId = vm.crew.first?.driverId
        do {
            let out: WellnessHistoryWire_401 = try await EusoTripAPI.shared.query(
                "driverWellness.getWellnessHistory",
                input: HistoryInput_401(driverId: driverId, days: 30))
            historyDriverId = out.driverId ?? driverId
            historyRows = out.history
            showHistory = true
        } catch {
            actionError = wellnessFailureCopy_401(error)
        }
    }

    private func restPlanItems(for driver: CrewMember_401) -> [String] {
        switch driver.risk {
        case .rest:
            return [
                "Pull this driver from dispatch consideration until rest status is reviewed.",
                "Verify HOS, last pickup timestamp, and the reason shown in the fatigue alert before assigning the next load.",
                "Document any off-app rest coordination in the driver wellness log once completed."
            ]
        case .watch:
            return [
                "Keep the driver on watch and avoid assigning a tight pickup window without a fresh fatigue check.",
                "Review route length, night-driving exposure, and current HOS before the next dispatch.",
                "Ask for a wellness check-in if the risk score continues to rise."
            ]
        case .fit:
            return [
                "No rest intervention is required from the live alert board.",
                "Keep wellness check-ins current so the fatigue model remains auditable."
            ]
        }
    }

    private func restPlanText(for driver: CrewMember_401) -> String {
        var lines = [
            "EusoTrip Crew Wellness Rest Plan",
            driver.nameUnit,
            "Score: \(driver.score) · \(driver.riskLabel)",
            driver.context,
            "",
            "Actions:"
        ]
        lines.append(contentsOf: restPlanItems(for: driver).map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    private func initials_401(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}

// MARK: - Previews

#Preview("401 · Catalyst · Crew Wellness · Dark") {
    CatalystCrewWellnessScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("401 · Catalyst · Crew Wellness · Light") {
    CatalystCrewWellnessScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason a crew-wellness lookup failed.
///
/// The caught error is still available for logging; the catalyst sees a
/// sentence they can act on rather than a raw `NSError` description.
fileprivate func wellnessFailureCopy_401(_ error: Error) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired. Sign in again to open crew wellness history."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account isn't cleared to view this driver's wellness history."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Wellness history was rejected for this driver. Refresh the crew list and try again."
                : trimmed
        case .httpStatus(let code, _):
            return "Wellness history didn't load (code \(code)). Try again in a moment."
        case .decodingFailed:
            return "Wellness history came back in a form this build can't read. Update the app, then retry."
        case .empty:
            return "No wellness history came back for this driver yet."
        case .notConfigured, .badURL:
            return "This device isn't set up for live wellness data yet. Restart the app and try again."
        case .queuedForOfflineReplay:
            return "You're offline — wellness history loads once you reconnect."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection right now. Wellness history will load once you have signal."
    }
    return "Wellness history didn't load. Refresh the crew list and try again."
}
