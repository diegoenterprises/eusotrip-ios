//
//  661_RailDemurrageChargeGeneration.swift
//  EusoTrip — Rail Engineer · Demurrage Charge Generation (Dark + Light ·
//  verbatim port of "05 Rail / 661 Rail Demurrage Charge Generation.svg").
//
//  ARCHETYPE = ACCRUAL RUN: the run-total figure (the money accruing right
//  now), a danger-washed past-free-time attention band, an ACCRUAL QUEUE where
//  every car shows the chargeable-hours × rate math that produced the accrued
//  charge, a RUN TOTALS card, a free-time-regime tri-country band, and a
//  Generate-charges / Analytics CTA pair. Deliberately distinct from its
//  approval sibling (662) — 661 CALCULATES the charges, 662 DECIDES on them.
//
//  WIRING (grep-confirmed · frontend/server/routers/railDemurrageAuto.ts):
//    • run summary + queue → railDemurrageAuto.dashboard (query · :46)
//        no input; { summary{ totalChargesAccruing, activeAccruals,
//        disputesOpen }, perCarRunway[{ demurrageId, railcarNumber,
//        freeTimeHours, chargeableHours, ratePerHour, usdToday, usdProjected }] }.
//    • Generate charges      → railDemurrageAuto.runBulkAccrual (mutation · :248)
//        input { shipmentIds?, country }; returns { processed, ... }.
//    • Analytics             → railDemurrageAuto.reportByDwellReason (query · :499)
//    HONEST NOTE: the server computes in HOURS (chargeableHours × ratePerHour),
//    so the queue sub reads hours, not the SVG's day math — the units follow
//    the live return, never fabricated. Free-time defaults follow the country
//    enum on calculateAccrual (US/CA 48h · MX 24h).
//
//  RBAC: protectedProcedure. transportMode=rail · US·USD.
//  NAV (RailEngineerNavController): current = COMPLIANCE.
//

import SwiftUI

struct RailDemurrageChargeGenerationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageChargeGenerationBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodables (railDemurrageAuto.dashboard)

private struct DemurrageDashboard661: Decodable {
    struct Summary: Decodable {
        let activeAccruals: Int?
        let totalChargesAccruing: Double?
        let disputesOpen: Int?
    }
    struct CarRunway: Decodable, Identifiable {
        let demurrageId: Int?
        let railcarNumber: String?
        let freeTimeHours: Double?
        let chargeableHours: Double?
        let ratePerHour: Double?
        let usdToday: Double?
        let usdProjected: Double?
        var id: Int { demurrageId ?? railcarNumber.hashValue }
    }
    let summary: Summary?
    let perCarRunway: [CarRunway]?
}

private struct BulkAccrualResult661: Decodable {
    let processed: Int?
    let updated: Int?
    let totalNewCharges: Double?
    let note: String?
}

private enum DemCountry661: String, CaseIterable, Identifiable {
    case US, CA, MX
    var id: String { rawValue }
    var freeLabel: String { self == .MX ? "24h free" : "48h free" }
    var rateLabel: String { self == .MX ? "$40/hr · MXN" : (self == .CA ? "$35/hr · CAD" : "$35/hr · USD") }
}

// MARK: - Body

private struct RailDemurrageChargeGenerationBody: View {
    @Environment(\.palette) private var palette

    @State private var data: DemurrageDashboard661? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var country: DemCountry661 = .US
    @State private var genBusy = false
    @State private var ack: String? = nil

    private var cars: [DemurrageDashboard661.CarRunway] { data?.perCarRunway ?? [] }
    private var runTotal: Double { data?.summary?.totalChargesAccruing ?? 0 }
    private var pastFreeCount: Int { cars.filter { ($0.chargeableHours ?? 0) > 0 }.count }
    private var activeAccruals: Int { data?.summary?.activeAccruals ?? cars.count }
    private var disputesOpen: Int { data?.summary?.disputesOpen ?? 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                heroFigure
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    if pastFreeCount > 0 { attentionBand }
                    accrualQueue
                    runTotals
                    freeTimeBand
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
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

    // MARK: Eyebrow + title + hero figure

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · CHARGE RUN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("ACCRUAL · LIVE")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Demurrage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    private var heroFigure: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dollars(runTotal))
                    .font(.system(size: 32, weight: .bold)).tracking(-0.6).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("accruing now")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(activeAccruals) cars on the clock · \(pastFreeCount) past free time")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Attention band (past free time)

    private var attentionBand: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(pastFreeCount) car\(pastFreeCount == 1 ? "" : "s") past last free day")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(country.rawValue) free time \(country.freeLabel) · accrual auto-runs daily 06:00 CT")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Text("\(pastFreeCount)")
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(Brand.danger)
                .frame(width: 54, height: 34)
                .background(Brand.danger.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(Space.s4)
        .background(
            LinearGradient(colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)],
                           startPoint: .leading, endPoint: .trailing))
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Accrual queue

    private var accrualQueue: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACCRUAL QUEUE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("hours × rate · accrued")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if cars.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "clock.badge.checkmark"),
                    title: "No cars accruing",
                    subtitle: "The accrual queue populates from railDemurrageAuto.dashboard as cars pass their free-time clock.",
                    comingSoon: false
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cars.enumerated()), id: \.element.id) { idx, c in
                        carRow(c)
                        if idx < cars.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func carRow(_ c: DemurrageDashboard661.CarRunway) -> some View {
        let past = (c.chargeableHours ?? 0) > 0
        let accent: Color = past ? Brand.info : Brand.success
        let billed = (c.usdToday ?? 0) > 0 && !past
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.railcarNumber ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(hrs(c.chargeableHours))h × \(dollars(c.ratePerHour ?? 0))/hr · \(hrs(c.freeTimeHours))h free")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(past ? "ACCRUING" : (billed ? "BILLED" : "FREE"))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(accent.opacity(0.16)).clipShape(Capsule())
                Text(dollars(c.usdToday ?? 0))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Run totals

    private var runTotals: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RUN TOTALS").font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                totalCell("Accruing now", dollars(runTotal), gradient: true)
                cellDivider
                totalCell("On the clock", "\(activeAccruals)", gradient: false, accent: palette.textPrimary)
                cellDivider
                totalCell("Disputes", "\(disputesOpen)", gradient: false,
                          accent: disputesOpen > 0 ? Brand.danger : palette.textPrimary)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var cellDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 44)
    }

    private func totalCell(_ label: String, _ value: String, gradient: Bool, accent: Color = .clear) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(accent)
                }
            }
            .font(.system(size: 20, weight: .bold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2)
    }

    // MARK: Free-time regime band (tri-country)

    private var freeTimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME REGIME · BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(DemCountry661.allCases) { c in
                    let active = c == country
                    Button { country = c } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(c.rawValue) · \(c.freeLabel)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(active ? Color.white : palette.textPrimary)
                            Text(c.rateLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(minHeight: 44)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await generate() } } label: {
                Text(genBusy ? "Generating…" : "Generate charges")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(genBusy ? 0.6 : 1).disabled(genBusy)

            RailSecondaryActionButton(
                title: "Analytics",
                sheetTitle: "Charge run context",
                lines: [
                    "Accruing now: \(dollars(runTotal))",
                    "Cars on the clock: \(activeAccruals)",
                    "Past free time: \(pastFreeCount)",
                    "Disputes open: \(disputesOpen)",
                    "Free-time regime: \(country.rawValue) \(country.freeLabel)",
                    "Analytics: railDemurrageAuto.reportByDwellReason"
                ],
                systemImage: "chart.bar"
            )
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 66)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 72)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Formatting

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$\(f.string(from: NSNumber(value: v)) ?? "0")"
    }
    private func hrs(_ v: Double?) -> String {
        let x = v ?? 0
        return x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.queryNoInput("railDemurrageAuto.dashboard")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generate() async {
        genBusy = true; ack = nil
        defer { genBusy = false }
        struct Input: Encodable { let country: String }
        do {
            let res: BulkAccrualResult661 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.runBulkAccrual", input: Input(country: country.rawValue))
            ack = "Accrual run complete · \(res.processed ?? 0) cars processed. \(res.note ?? "")"
        } catch {
            ack = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("661 · Rail Demurrage Charge Generation · Night") {
    RailDemurrageChargeGenerationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("661 · Rail Demurrage Charge Generation · Light") {
    RailDemurrageChargeGenerationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
