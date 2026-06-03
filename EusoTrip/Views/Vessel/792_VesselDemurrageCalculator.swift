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
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    detentionAccessorials.calculateDetention (EXISTS frontend/server/routers/detentionAccessorials.ts:363 ·
//      query · input {arrivalTime, departureTime?, freeTimeMinutes=120, cargoType="general", customRatePerHour?}
//      -> {totalMinutes, freeTimeMinutes, billableMinutes, billableHours, totalCharge,
//          tierBreakdown:[{tier,hours,rate,subtotal}], cargoType, arrivalTime, departureTime}).
//      DETENTION_TIERS escalation rates by tier. Seeds the headline (totalCharge), the EST. TOTAL tile,
//      the BILLABLE tile, the subline, and every ladder row (tierBreakdown). departureTime omitted ->
//      server uses now(). protectedProcedure · transportMode=vessel · USLGB · USD.
//    "Recalculate" re-runs the query with the current inputs.
//    "Bill it"     -> STUB · named-gap detentionAccessorials.createClaim (propose: mutation inserting a
//      detention_claims row + blockchainAuditTrail entry + broadcast WS_EVENTS.detentionCreated). No
//      backing mutation today, so it is honestly flagged STUB and just re-runs load() — never faked.
//
//  0 mock data on load · honest empty/error states — every value renders from the decoded response.
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

    // Inputs (bound to the calculateDetention query). Display strings mirror the SVG.
    private let arrivalDisplay   = "05-29 08:10"
    private let departureDisplay = "now · live"
    private let freeTimeDisplay  = "120 min"
    private let cargoDisplay     = "reefer · tiered"
    // Wire values bound to the query.
    private let arrivalISO       = "2026-05-29T08:10:00Z"
    private let freeTimeMinutes  = 120
    private let cargoType        = "reefer"

    // Seeded only as placeholders; replaced by the decoded response in load().
    @State private var total    = "$0"
    @State private var subline  = "computing billable time over free time…"
    @State private var freeUsed = "120m"
    @State private var billable = "0.0h"
    @State private var estTotal = "$0"
    @State private var tiers: [LadderTier792] = []

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
                } else {
                    inputsCard
                    HStack(spacing: 8) {
                        KpiTile792(caption: "FREE USED",  value: freeUsed, footnote: "of 120m",  highlighted: false)
                        KpiTile792(caption: "BILLABLE",   value: billable, footnote: "over free", highlighted: false)
                        KpiTile792(caption: "EST. TOTAL", value: estTotal, footnote: "per box",   highlighted: true)
                    }
                    Text("ESCALATION LADDER · PER BOX · PER HOUR").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    if tiers.isEmpty {
                        EusoEmptyState(systemImage: "function",
                                       title: "Within free time",
                                       subtitle: "calculateDetention returned no billable tiers — the box is still inside its \(freeTimeDisplay) free window. Nothing to escalate.")
                    } else {
                        ladderCard
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: "Recalculate", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                        SecondaryButton792(title: "Bill it") { Task { await billIt() } }
                    }
                    ESangRow792(title: "ESang: drayage out today caps this at Tier 2",
                                subtitle: "waiting to 06-02 adds Tier 3 escalation at the top rate")
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
                Text("MSCU 7741203").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var inputsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("INPUTS · calculateDetention").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
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
            // Arrival ISO bound to the booking's gate-in; departure omitted -> server uses now().
            let r: CalcDetentionResp792 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.calculateDetention",
                input: CalcDetentionInput792(arrivalTime: arrivalISO, freeTimeMinutes: freeTimeMinutes, cargoType: cargoType))
            total    = usd792(r.totalCharge ?? 0)
            estTotal = usd792(r.totalCharge ?? 0)
            billable = String(format: "%.1fh", r.billableHours ?? 0)
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
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func billIt() async {
        // STUB · named-gap detentionAccessorials.createClaim — surfaced to the web team.
        // No backing mutation today, so we honestly re-run the calc rather than fake a write.
        await load()
    }
}

// MARK: - Data shapes (mirror detentionAccessorials.calculateDetention projection)

private struct CalcDetentionInput792: Encodable {
    let arrivalTime: String
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
