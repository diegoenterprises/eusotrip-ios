//
//  792_VesselDemurrageCalculator.swift
//  EusoTrip — Vessel Operator · Demurrage Calculator.
//
//  Faithful 1:1 port of "792 Vessel Demurrage Calculator.svg" (Light + Dark), RECONSTRUCTED to a
//  TIER-LADDER calculator archetype — DISTINCT from the detention dashboards (790/793/795/796).
//  Composition mirrors the SVG: a computed-total gradient figure headline, an INPUTS summary card
//  (arrival/departure/free-time/cargo), a 3-tile strip (EST. TOTAL highlighted), and an escalation
//  ladder card with per-tier hours/rate/subtotal + proportional fill bars + a total row, CTA pair.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) —
//  the same Shell + BottomNav wrapper the registered vessel siblings 664/680/757 ship. COMPLIANCE is
//  inked because demurrage/detention is a D&D-compliance surface.
//
//  Data / wiring:
//    detentionAccessorials.getDemurrageTracking resolves the current company-scoped demurrage claims
//      and supplies the live source claim/container/load/timing context for this calculator.
//    detentionAccessorials.calculateDetention (EXISTS frontend/server/routers/detentionAccessorials.ts ·
//      query · input {arrivalTime, departureTime?, freeTimeMinutes=120, cargoType="general", customRatePerHour?}
//      -> {totalMinutes, freeTimeMinutes, billableMinutes, billableHours, totalCharge,
//          tierBreakdown:[{tier,hours,rate,subtotal}], cargoType, arrivalTime, departureTime}).
//      DETENTION_TIERS escalation rates by tier. Seeds the headline, EST. TOTAL tile, BILLABLE tile,
//      subline, and every ladder row. departureTime omitted -> server uses now().
//    detentionAccessorials.createClaim bills the selected real source claim into detention_claims with
//      tenant ownership checks, audit trail, and company realtime fan-out.
//    "Recalculate" re-runs the query with the current inputs.
//    "Bill it" promotes the selected live claim to the billing ledger instead of reloading.
//
//  0 mock data on load · honest empty/error states — every value renders from decoded response rows.
//  KpiTile792 / LadderTier792 / SecondaryButton792 / ESangRow792 / EmptyInput792 are file-scoped
//  bespoke helpers (the canonical port's KpiTile/Money/DurFmt/SecondaryButton/ESangRow are not shared
//  app symbols), built from the same grammar the registered siblings use to preserve the wireframe look.
//

import SwiftUI

struct VesselDemurrageCalculatorScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageCalculatorBody()
        } nav: {
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

private struct LadderTier792: Identifiable {
    let id = UUID()
    let name: String
    let band: String
    let hours: String
    let rate: String
    let subtotal: String
    let frac: Double
    let tone: Color
}

private struct VesselDemurrageCalculatorBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selectedClaim: DemurrageContainer792? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var actionInFlight = false

    @State private var total    = "$0"
    @State private var subline  = "computing billable time over free time…"
    @State private var freeUsed = "120m"
    @State private var billable = "0.0h"
    @State private var estTotal = "$0"
    @State private var tiers: [LadderTier792] = []

    private var arrivalDisplay: String { displayDate792(selectedClaim?.arrivalDate) }
    private var departureDisplay: String { selectedClaim?.lastFreeDay.map(displayDate792) ?? "now · live" }
    private var activeFreeTimeMinutes: Int { selectedClaim?.freeTimeMinutes ?? 120 }
    private var freeTimeDisplay: String { "\(activeFreeTimeMinutes) min" }
    private var cargoType: String { selectedClaim?.cargoType?.lowercased() ?? "general" }
    private var cargoDisplay: String { "\(cargoType) · tiered" }
    private var containerLabel: String { selectedClaim?.containerNumber ?? "LIVE CLAIM" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(total).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Computing…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if selectedClaim == nil {
                    EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                                   title: "No billable demurrage claim",
                                   subtitle: "No demurrage claim of yours carries both a live load and an arrival time. Billing opens when a real claim exists.")
                } else {
                    inputsCard
                    HStack(spacing: 8) {
                        KpiTile792(caption: "FREE USED",  value: freeUsed, footnote: "of \(activeFreeTimeMinutes)m",  highlighted: false)
                        KpiTile792(caption: "BILLABLE",   value: billable, footnote: "over free", highlighted: false)
                        KpiTile792(caption: "EST. TOTAL", value: estTotal, footnote: "per box",   highlighted: true)
                    }
                    Text("ESCALATION LADDER · PER BOX · PER HOUR").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    if tiers.isEmpty {
                        EusoEmptyState(systemImage: "function",
                                       title: "Within free time",
                                       subtitle: "No billable tiers came back — the box is still inside its \(freeTimeDisplay) free window. Nothing to escalate.")
                    } else {
                        ladderCard
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: "Recalculate", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                        SecondaryButton792(title: actionInFlight ? "Billing…" : "Bill it") { Task { await billIt() } }
                    }
                    if let error = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(error).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let message = actionMessage {
                        LifecycleCard {
                            Text(message).font(EType.caption).foregroundStyle(Brand.success)
                        }
                    }
                    ESangRow792(title: "ESang: \(containerLabel) can move into billing at \(estTotal)",
                                subtitle: "source claim \(selectedClaim?.id ?? 0) · load \(selectedClaim?.loadId ?? 0) · audit trail writes on Bill it")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DEMURRAGE CALC").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(containerLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var inputsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("INPUTS · detention math").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(spacing: 0) {
                    field("Arrival",   arrivalDisplay)
                    field("Departure", departureDisplay)
                }
                HStack(spacing: 0) {
                    field("Free time", freeTimeDisplay)
                    field("Cargo",     cargoDisplay)
                }
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ladderCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("TIER").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("HOURS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("RATE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).frame(width: 52, alignment: .trailing)
                    Text("SUBTOTAL").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).frame(width: 64, alignment: .trailing)
                }
                Divider().overlay(palette.borderFaint).padding(.vertical, 8)
                ForEach(tiers) { t in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle().fill(t.tone.opacity(0.14)).frame(width: 12, height: 12)
                            Circle().fill(t.tone).frame(width: 6, height: 6)
                        }.padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(t.band).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                                    Capsule().fill(t.tone).frame(width: geo.size.width * t.frac, height: 5)
                                }
                            }.frame(height: 5)
                        }
                        Text("\(t.hours)h").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text(t.rate).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary).frame(width: 52, alignment: .trailing)
                        Text(t.subtotal).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary).frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 12)
                    Divider().overlay(palette.borderFaint)
                }
                HStack {
                    Text("Total demurrage due").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(total).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                }.padding(.top, 12)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let tracking: DemurrageTrackingResp792 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDemurrageTracking",
                input: DemurrageTrackingInput792(limit: 25))
            let row = (tracking.containers ?? []).first { c in
                guard (c.loadId ?? 0) > 0, (c.arrivalDate ?? "").isEmpty == false else { return false }
                let status = (c.status ?? "").lowercased()
                return !["disputed", "denied", "voided", "invoiced", "paid", "reimbursed"].contains(status)
            }
            guard let row, let arrival = row.arrivalDate else {
                selectedClaim = nil
                tiers = []
                total = "$0"
                estTotal = "$0"
                billable = "0.0h"
                freeUsed = "0m"
                subline = "no live demurrage claim to calculate"
                loading = false
                return
            }
            selectedClaim = row
            let r: CalcDetentionResp792 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.calculateDetention",
                input: CalcDetentionInput792(arrivalTime: arrival,
                                             departureTime: row.lastFreeDay,
                                             freeTimeMinutes: row.freeTimeMinutes ?? 120,
                                             cargoType: row.cargoType ?? "general"))
            total    = usd792(r.totalCharge ?? 0)
            estTotal = usd792(r.totalCharge ?? 0)
            billable = String(format: "%.1fh", r.billableHours ?? 0)
            freeUsed = hm792(min(r.totalMinutes ?? 0, row.freeTimeMinutes ?? 120))
            subline  = "billable \(hm792(r.billableMinutes ?? 0)) over free time · \(r.tierBreakdown.count) tiers · USD"
            let tones = [Brand.success, Brand.warning, Brand.danger]
            let bands = ["0–24h", "24–48h", "48h+"]
            let maxHours = max(1.0, r.tierBreakdown.map { $0.hours ?? 0 }.max() ?? 1)
            tiers = r.tierBreakdown.enumerated().map { i, t -> LadderTier792 in
                LadderTier792(name: t.tier ?? "Tier \(i + 1)",
                              band: bands[min(i, bands.count - 1)],
                              hours: String(format: "%.1f", t.hours ?? 0),
                              rate: "$\(Int(t.rate ?? 0))",
                              subtotal: usd792(t.subtotal ?? 0),
                              frac: (t.hours ?? 0) / maxHours,
                              tone: tones[min(i, tones.count - 1)])
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func billIt() async {
        guard !actionInFlight else { return }
        actionMessage = nil; actionError = nil
        guard let claim = selectedClaim, let arrival = claim.arrivalDate else {
            actionError = "Open a live demurrage claim before billing."
            return
        }
        actionInFlight = true
        do {
            let result: CreateClaimResp792 = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.createClaim",
                input: CreateClaimInput792(sourceClaimId: claim.id,
                                           claimType: "demurrage",
                                           facilityName: claim.facilityName,
                                           containerNumber: claim.containerNumber,
                                           description: "Demurrage billed from vessel calculator for \(claim.containerNumber ?? "container")",
                                           arrivalTime: arrival,
                                           departureTime: claim.lastFreeDay,
                                           freeTimeMinutes: claim.freeTimeMinutes ?? 120,
                                           status: "approved"))
            if result.success == true {
                let finalized = result.alreadyFinalized == true ? "already finalized" : "ready for billing"
                actionMessage = "Claim \(result.claimId ?? claim.id) \(finalized) · \(usd792(result.totalAmount ?? 0))."
                await load()
            } else {
                actionError = "Billing did not confirm. Reopen the claim and try again."
            }
        } catch {
            actionError = error.eusoUserCopy
        }
        actionInFlight = false
    }
}

// MARK: - Data shapes (mirror detentionAccessorials.getDemurrageTracking/createClaim/calculateDetention)

private struct DemurrageTrackingInput792: Encodable { let limit: Int }

private struct DemurrageContainer792: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let containerNumber: String?
    let facilityName: String?
    let arrivalDate: String?
    let lastFreeDay: String?
    let freeTimeMinutes: Int?
    let totalDwellMinutes: Int?
    let billableMinutes: Int?
    let perDiemRate: Double?
    let totalCharge: Double?
    let status: String?
    let shipperName: String?
    let cargoType: String?
}

private struct DemurrageTrackingResp792: Decodable {
    let containers: [DemurrageContainer792]?
}

private struct CreateClaimInput792: Encodable {
    let sourceClaimId: Int
    let claimType: String
    let facilityName: String?
    let containerNumber: String?
    let description: String
    let arrivalTime: String
    let departureTime: String?
    let freeTimeMinutes: Int
    let status: String
}

private struct CreateClaimResp792: Decodable {
    let success: Bool?
    let claimId: Int?
    let loadId: Int?
    let status: String?
    let alreadyFinalized: Bool?
    let totalAmount: Double?
    let billableMinutes: Int?
}

private struct CalcDetentionInput792: Encodable {
    let arrivalTime: String
    let departureTime: String?
    let freeTimeMinutes: Int
    let cargoType: String
}

private struct CalcDetentionTier792: Decodable {
    let tier: String?
    let hours: Double?
    let rate: Double?
    let subtotal: Double?
}

private struct CalcDetentionResp792: Decodable {
    let totalMinutes: Int?
    let billableMinutes: Int?
    let billableHours: Double?
    let totalCharge: Double?
    let tierBreakdown: [CalcDetentionTier792]
}

private struct EmptyInput792: Encodable {}

// MARK: - File-scoped formatters (the canonical port's Money/DurFmt are not shared app symbols)

private func usd792(_ amount: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = (amount.truncatingRemainder(dividingBy: 1) == 0) ? 0 : 2
    return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
}

private func hm792(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

private func displayDate792(_ raw: String?) -> String {
    guard let raw, raw.isEmpty == false else { return "—" }
    let compact = raw.replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
    if compact.count >= 16 {
        let monthDayStart = compact.index(compact.startIndex, offsetBy: min(5, compact.count))
        let monthDayEnd = compact.index(compact.startIndex, offsetBy: min(16, compact.count))
        return String(compact[monthDayStart..<monthDayEnd])
    }
    return compact
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// KPI tile strip cell — the canonical port's `KpiTile` is not a shared app
/// symbol, so we render the same caption / value / footnote grammar file-scoped.
/// The highlighted tile carries the gradient rim the registered siblings use.
private struct KpiTile792: View {
    @Environment(\.palette) private var palette
    let caption: String
    let value: String
    let footnote: String
    let highlighted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
            Text(footnote).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                              lineWidth: highlighted ? 1.5 : 1)
        )
    }
}

/// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
/// is not a shared app symbol, so we hand-roll the same outline grammar the
/// registered siblings (757) use, on the RoundedRectangle(Radius.md) standard.
private struct SecondaryButton792: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void
    init(title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped (mirror 757).
private struct ESangRow792: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

#Preview("792 · Demurrage Calculator · Night") { VesselDemurrageCalculatorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("792 · Demurrage Calculator · Light") { VesselDemurrageCalculatorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
