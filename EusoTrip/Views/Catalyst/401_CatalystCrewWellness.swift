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
//  tRPC wiring manifest (line-confirmed on disk; NONE present in EusoTripAPI yet
//  — house 0%-mock seeds from the Code/ spec are retained verbatim and overwrite
//  on hydrate when the client methods land):
//    • fleet index + at-risk count → driverWellness.getWellnessDashboard      (driverWellness.ts:185)
//    • per-driver score + band     → driverWellness.getFatigueRiskAssessment  (driverWellness.ts:317)
//    • flagged-driver row          → driverWellness.getFatigueAlerts          (driverWellness.ts:451)
//    • retention context           → driverWellness.getRetentionScore         (driverWellness.ts:681)
//    • "Schedule rest" CTA         → catalystProcedure write on hos plan       (_core/trpc.ts:150)
//    • "Wellness log" CTA          → driverWellness.getWellnessHistory         (driverWellness.ts:610)
//  transportMode=truck; country=US (FMCSA ELD fatigue ruleset; CA ELD / NOM-087
//  per domicile). Persona: Eusotrans LLC · Michael Eusorone owner-op lead 142.
//

import SwiftUI

// MARK: - View model (board archetype)

private struct CrewMember_401: Identifiable {
    enum Risk { case fit, watch, rest }
    let id: String              // unit
    let initials: String        // "RS"
    let nameUnit: String        // "R. Salazar · Unit 261"
    let context: String         // mono on-duty/sleep/HOS line
    let score: Int              // 54
    let risk: Risk
    let riskLabel: String       // "REST" / "WATCH" / "FIT"
    let isOwnerOp: Bool         // ME gets the gradient disc
}

private struct CrewWellnessVM_401 {
    let fleetIndex: String          // "82"
    let atRisk: String              // "1 driver"
    let onDuty: String              // "4 of 6"
    let bandMarkerFrac: Double      // 0.82 (position along red→green band)
    let bandCaption: String
    let avgSleep: String            // "7.1h"
    let avgSleepDelta: String       // "+0.4h vs wk"
    let hosMargin: String           // "3.2h"
    let checkIns: String            // "6/6"
    let crew: [CrewMember_401]
    let insightTitle: String
    let insightSub: String
}

// MARK: - Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME)

private func catalystNavLeading_401() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: true)]
}

private func catalystNavTrailing_401() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
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

    // House 0%-mock seed — mirrors the SVG content verbatim, overwritten on
    // hydrate once the driverWellness.* client methods land in EusoTripAPI.
    @State private var vm: CrewWellnessVM_401 = .seed
    @State private var scheduling: Bool = false

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
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · WELLNESS").font(EType.micro).tracking(1.0)
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
                    Text("Eusotrans LLC · 6 drivers · 7-day window")
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
            kpiTile("AVG SLEEP", vm.avgSleep, sub: vm.avgSleepDelta,
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: Brand.success)
            kpiTile("HOS MARGIN", vm.hosMargin, sub: "avg drive left",
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: palette.textSecondary)
            kpiTile("CHECK-INS", vm.checkIns, sub: "all logged today",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: Brand.success)
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
                Text("ranked by score").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.crew.enumerated()), id: \.element.id) { idx, m in
                    crewRow(m)
                    if idx < vm.crew.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
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
        Button {
            NotificationCenter.default.post(name: .eusoCatalystWellnessInsight_401, object: nil,
                userInfo: ["source": "401_CatalystCrewWellness"])
        } label: {
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
                // WIRE: hos.scheduleReset via catalystProcedure (_core/trpc.ts:150)
                //       rest block + 34-hr reset; blockchainAudit row; carrier WS wellness update.
                NotificationCenter.default.post(name: .eusoCatalystWellnessScheduleRest_401, object: nil,
                    userInfo: ["source": "401_CatalystCrewWellness"])
                scheduling = false
            } label: {
                Text("Schedule rest").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
                    .opacity(scheduling ? 0.6 : 1.0)
            }.buttonStyle(.plain).disabled(scheduling)
            Button {
                // WIRE: driverWellness.getWellnessHistory (driverWellness.ts:610)
                NotificationCenter.default.post(name: .eusoCatalystWellnessLog_401, object: nil,
                    userInfo: ["source": "401_CatalystCrewWellness"])
            } label: {
                Text("Wellness log").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Network
    //
    // No driverWellness.* client method exists in EusoTripAPI yet, so the
    // Code/-spec representative seed (CrewWellnessVM_401.seed) stands as the
    // 0%-mock board and is overwritten verbatim the moment hydrate lands.
    private func loadAll() async {
        // WIRE: driverWellness.getWellnessDashboard     (driverWellness.ts:185)
        // WIRE: driverWellness.getFatigueRiskAssessment (driverWellness.ts:317)
        // WIRE: driverWellness.getFatigueAlerts         (driverWellness.ts:451)
        // WIRE: driverWellness.getRetentionScore        (driverWellness.ts:681)
        vm = .seed
    }
}

// MARK: - Notifications (file-private hooks)

extension Notification.Name {
    static let eusoCatalystWellnessScheduleRest_401 = Notification.Name("eusoCatalystWellnessScheduleRest_401")
    static let eusoCatalystWellnessLog_401          = Notification.Name("eusoCatalystWellnessLog_401")
    static let eusoCatalystWellnessInsight_401      = Notification.Name("eusoCatalystWellnessInsight_401")
}

// MARK: - Seed (mirrors the SVG content verbatim)

private extension CrewWellnessVM_401 {
    static let seed = CrewWellnessVM_401(
        fleetIndex: "82", atRisk: "1 driver", onDuty: "4 of 6",
        bandMarkerFrac: 0.82,
        bandCaption: "Fleet sits in the FMCSA fatigue-safe band · 1 unit flagged",
        avgSleep: "7.1h", avgSleepDelta: "+0.4h vs wk", hosMargin: "3.2h", checkIns: "6/6",
        crew: [
            CrewMember_401(id: "261", initials: "RS", nameUnit: "R. Salazar · Unit 261",
                           context: "9h45 on duty · sleep 5.2h · 0h30 drive left",
                           score: 54, risk: .rest, riskLabel: "REST", isOwnerOp: false),
            CrewMember_401(id: "318", initials: "LB", nameUnit: "L. Brandt · Unit 318",
                           context: "7h10 on duty · sleep 6.4h · 2h10 drive left",
                           score: 66, risk: .watch, riskLabel: "WATCH", isOwnerOp: false),
            CrewMember_401(id: "207", initials: "DO", nameUnit: "D. Okafor · Unit 207",
                           context: "5h20 on duty · sleep 7.6h · 5h40 drive left",
                           score: 79, risk: .fit, riskLabel: "FIT", isOwnerOp: false),
            CrewMember_401(id: "142", initials: "ME", nameUnit: "Michael Eusorone · Unit 142",
                           context: "4h05 on duty · sleep 7.9h · owner-op lead",
                           score: 88, risk: .fit, riskLabel: "FIT", isOwnerOp: true),
        ],
        insightTitle: "ESang: Salazar at 54 · 0h30 drive left",
        insightSub: "Schedule a 34-hr reset before the next dispatch"
    )
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
