//
//  791_VesselActiveDetentions.swift
//  EusoTrip — Vessel Operator · Active Detentions (LIVE MONEY-BOARD archetype).
//
//  Faithful 1:1 port of "791 Vessel Active Detentions.svg" (Light + Dark).
//  A live cost-of-waiting board (distinct from the 30-day portfolio 790 and the
//  ranked facilities 793): the gradient live-accrual figure leads, a
//  billable-vs-free-time card shows how much of every box's clock is now
//  billable, a 4-cell KPI strip highlights ACTIVE NOW + ACCRUING, and a
//  running-container ledger shows which box is bleeding money right now and how
//  long until it tips. The operator acts before the charge escalates.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getActiveDetentions {limit,offset}? (query, protectedProcedure,
//        companyId-scoped, RUNNING_STATUSES :577)
//        -> { detentions[{id,loadId,facilityName,locationType,arrivalTime,
//             elapsedMinutes,freeTimeMinutes,billableMinutes,currentCharge,
//             status,carrierName,shipperName,cargoType}], total }
//        currentCharge = billableMinutes/60 × $75/h (server-computed).
//    · "Refresh now" -> re-queries getActiveDetentions.
//    · "Export" -> exportDetentionLedger is a NAMED SERVER GAP (absent) — the
//      button surfaces the gap honestly.
//  transportMode=vessel · USLGB · USD $75/h. No mock data — every value derives
//  from the live endpoint with honest loading / error / empty states.
//

import SwiftUI

private struct ActiveDetention791: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let facilityName: String?
    let locationType: String?
    let elapsedMinutes: Int?
    let freeTimeMinutes: Int?
    let billableMinutes: Int?
    let currentCharge: Double?
    let status: String?
    let carrierName: String?
    let cargoType: String?
}
private struct ActiveResponse791: Decodable {
    let detentions: [ActiveDetention791]?
    let total: Int?
}

struct VesselActiveDetentionsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselActiveDetentionsBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselActiveDetentionsBody: View {
    @Environment(\.palette) private var palette
    @State private var data: ActiveResponse791? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var refreshing = false

    private let accrue = Color(hex: 0xFF6B61)
    private let ratePerHour = 75.0

    private var boxes: [ActiveDetention791] { data?.detentions ?? [] }
    private var accruingNow: Double { boxes.reduce(0) { $0 + ($1.currentCharge ?? 0) } }
    private var billableTotal: Int { boxes.reduce(0) { $0 + ($1.billableMinutes ?? 0) } }
    private var freeTotal: Int { boxes.reduce(0) { $0 + min($1.elapsedMinutes ?? 0, $1.freeTimeMinutes ?? 120) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "ACTIVE DETENTION", caption: "LIVE · USLGB")
                titleBlock
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if boxes.isEmpty {
                    EusoEmptyState(systemImage: "timer",
                                   title: "No clocks running",
                                   subtitle: "getActiveDetentions returned no accruing boxes. Nothing past free time right now — no per-diem is ticking.")
                } else {
                    billableCard
                    kpiStrip
                    runningLedger
                    ctaPair
                    if let e = actionError { errorCard(e) }
                    regimeSegment
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Title — live accrual figure

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(VDetn.money(accruingNow))
                    .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Brand.success).frame(width: 7, height: 7)
                    Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.success.opacity(0.16)))
            }
            Text("accruing now · \(boxes.count) active · \(billableTotal) billable min · clock running")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Billable vs free-time card

    private var billableCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("BILLABLE vs FREE-TIME · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                GeometryReader { g in
                    let denom = max(1, freeTotal + billableTotal)
                    let fW = CGFloat(freeTotal) / CGFloat(denom) * g.size.width
                    HStack(spacing: 4) {
                        Capsule().fill(palette.textPrimary.opacity(0.12)).frame(width: max(2, fW - 4))
                        Capsule().fill(accrue)
                    }
                    .frame(height: 10)
                }
                .frame(height: 10)
                HStack(spacing: 0) {
                    legendStat("Free time", "\(freeTotal)m", palette.textTertiary)
                    Spacer()
                    legendStat("Over (billable)", "\(billableTotal)m", accrue)
                    Spacer()
                    legendStat("Rate", "$\(Int(ratePerHour))/h", palette.textPrimary)
                }
            }
        }
    }

    private func legendStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(tint == palette.textPrimary ? Brand.info : tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
    }

    // MARK: KPI

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VDetnKPICell(label: "ACTIVE NOW", value: "\(boxes.count)", sub: "clock running", gradient: true)
            VDetnKPICell(label: "BILLABLE", value: "\(billableTotal)m", sub: "over free time")
            VDetnKPICell(label: "RATE", value: "$\(Int(ratePerHour))", sub: "/hr per box")
            VDetnKPICell(label: "ACCRUING", value: VDetn.moneyK(accruingNow), sub: "and climbing", gradient: true)
        }
    }

    // MARK: Running ledger

    private var runningLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VDetnSectionLabel(title: "RUNNING NOW", trailing: "See all (\(boxes.count))", trailingTint: Brand.info)
            VStack(spacing: 0) {
                let rows = Array(boxes.prefix(4).enumerated())
                ForEach(rows, id: \.element.id) { idx, b in
                    runningRow(b)
                    if idx < rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func runningRow(_ b: ActiveDetention791) -> some View {
        let billable = b.billableMinutes ?? 0
        let free = b.freeTimeMinutes ?? 120
        let elapsed = b.elapsedMinutes ?? 0
        let remaining = max(0, free - elapsed)
        let over = billable > 0
        let tint: Color = over ? accrue : Brand.info
        // Over-free-time dot strip: one dot per hour billable, capped at 5.
        let dots = min(5, max(over ? 1 : 0, billable / 60))
        return HStack(spacing: Space.s3) {
            VDetnIconChip(systemImage: "shippingbox", color: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(b.facilityName ?? "Terminal").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("load \(b.loadId ?? 0) · \(VDetn.hoursMin(elapsed)) elapsed · free \(VDetn.hoursMin(free))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary).lineLimit(1)
                if dots > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<dots, id: \.self) { _ in Circle().fill(tint).frame(width: 6, height: 6) }
                    }
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                VDetnPill(text: over ? "+\(billable)m" : "\(remaining)m left", color: tint)
                Text(over ? VDetn.money(b.currentCharge ?? 0) : "$0")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(over ? palette.textPrimary : palette.textSecondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: CTA + regime

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: refreshing ? "Refreshing…" : "Refresh now",
                      action: { Task { await load() } }, trailingIcon: "arrow.clockwise", isLoading: refreshing)
            secondaryButton791(title: "Export") { exportGap() }.frame(width: 130)
        }
    }

    private func secondaryButton791(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var regimeSegment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETENTION PER-DIEM REGIME · AUTHORITY + CURRENCY")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                regimePill("US · FMC", "$\(Int(ratePerHour))/h · USD · ACTIVE", active: true)
                regimePill("CA · CBSA/CTA", "CAD · standby", active: false)
                regimePill("MX · SAT/API", "MXN · standby", active: false)
            }
        }
    }

    private func regimePill(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 8.5)).foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(active ? AnyShapeStyle(LinearGradient.esangSoft) : AnyShapeStyle(palette.bgCard)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(active ? Brand.info.opacity(0.55) : palette.borderFaint, lineWidth: 1))
    }

    // MARK: Load / actions

    private struct ActiveInput791: Encodable { let limit: Int; let offset: Int }

    private func load() async {
        refreshing = !loading
        loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getActiveDetentions", input: ActiveInput791(limit: 25, offset: 0))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false; refreshing = false
    }

    private func exportGap() {
        actionError = "Ledger export isn't wired yet — detentionAccessorials.exportDetentionLedger is a named server gap. The live board reads honestly; the CSV/PDF writer is pending."
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading running detentions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("791 · Vessel Active Detentions · Night") { VesselActiveDetentionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("791 · Vessel Active Detentions · Light") { VesselActiveDetentionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
