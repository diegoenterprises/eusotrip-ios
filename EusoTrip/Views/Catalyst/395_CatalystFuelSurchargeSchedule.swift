//
//  395_CatalystFuelSurchargeSchedule.swift
//  EusoTrip — Catalyst · Fuel Surcharge Schedule (carrier back-office pricing band).
//
//  Verbatim iOS-house port of the canonical bespoke wireframe:
//    03 Catalyst/Code/395_CatalystFuelSurchargeSchedule.swift
//    03 Catalyst/Dark-SVG/395 Catalyst Fuel Surcharge Schedule.svg
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op · USDOT 3 194 882 ·
//  MC-820 144 · Belle Plaine IA) opens his fuel-surcharge program from
//  the Wallet tab. The signature body is an FSC STEP LADDER — a diesel-
//  index gauge hero (PADD-3 Gulf Coast EIA) feeding a stepped bracket
//  table where each diesel $/gal band escalates to its own ¢/mi
//  surcharge; the bracket holding the live PADD-3 price is lit gradient
//  with a NOW marker and the bars step outward row by row as a literal
//  staircase. Table rows omit lifecycle dots (Foundation Contract §5).
//  Web peer: /catalyst/wallet/fsc.
//
//  Server wiring (line-confirmed on disk this fire):
//    • index gauge (PADD-3 $/gal · natl avg · week-of · week Δ)
//        → rateSheet.getCurrentDiesel(padd:)   — EXISTS (EusoTripAPI
//          RateSheetAPI). Returns price / padd / reportDate / source /
//          change1w. Hydrates the hero over the seed; honest em-dash on
//          failure. (Web peer fuelSurchargeIndex.currentDieselIndex
//          fuelSurchargeIndex.ts:56 maps to this iOS-shaped wrapper.)
//    • active schedule + method  → fscEngine.getSchedules (fscEngine.ts:27)   — not on iOS yet
//    • bracket-ladder rows       → fscEngine.getSchedulePreview (fscEngine.ts:233) — not on iOS yet
//      (fsc_lookup_table: fuelPriceMin / fuelPriceMax / surchargeAmount)
//    • applied-now ¢/mi          → fscEngine.calculateFSC (fscEngine.ts:97)  — not on iOS yet
//    • week Δ + trend            → fscEngine.getFSCHistory (fscEngine.ts:333) — not on iOS yet
//    • attached-lanes count      → fscEngine.attachToContract (fscEngine.ts:300) — not on iOS yet
//    • "Refresh PADD prices" CTA → fscEngine.updatePaddPrices (fscEngine.ts:172, mutation) — not on iOS yet
//    • "Edit table" CTA          → fscEngine.createSchedule (fscEngine.ts:49, mutation) — not on iOS yet
//  RBAC: isolatedApprovedProcedure carrier-scope (fscEngine.ts:16)
//        + requireAccess DISPATCH/CATALYST resource INVOICE on writes (fscEngine.ts:71).
//  transportMode = truck · PADD region 3 Gulf Coast · currency USD.
//
//  0% mock — the ladder/footer seeds mirror the SVG verbatim and are
//  overwritten on hydrate; the live PADD-3 index lights up the hero
//  gauge + national line the moment getCurrentDiesel resolves.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (WALLET current).
//

import SwiftUI

// MARK: - Wrapper

struct CatalystFuelSurchargeScheduleScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            FuelSurchargeBody_395()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_395(),
                trailing: catalystNavTrailing_395(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_395() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_395() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Bracket model

private struct FscBracket_395: Identifiable {
    let id: String            // "3.75-4.00"
    let range: String         // "$3.75 – 4.00"
    let surcharge: String     // "$0.46"
    let barFraction: Double   // 0…1 — escalating step width
    let active: Bool          // band holding the live PADD price
}

// MARK: - Body

private struct FuelSurchargeBody_395: View {
    @Environment(\.palette) private var palette

    // Index gauge (hydrated from rateSheet.getCurrentDiesel over the seed)
    @State private var paddRegion: String   = "PADD 3 GULF COAST"
    @State private var weekLabel: String    = "EIA WK21"
    @State private var scheduleId: String   = "FSC-DV-23 · WK21"
    @State private var dieselPrice: String  = "$3.75"
    @State private var basePegLabel: String = "$1.25 base peg"
    @State private var ceilingLabel: String = "$5.00"
    @State private var gaugeFraction: Double = (3.75 - 1.25) / (5.00 - 1.25)   // 0.6667
    @State private var appliedSurcharge: String = "$0.46"
    @State private var nationalLine: String = "natl $3.89 · +$0.04 wk"

    // Step ladder — seeds mirror the SVG verbatim, overwritten by
    // fscEngine.getSchedulePreview once that procedure ships on iOS.
    @State private var methodLabel: String  = "CPM · 6 STEPS · WEEKLY"
    @State private var brackets: [FscBracket_395] = [
        FscBracket_395(id: "3.00-3.25", range: "$3.00 – 3.25", surcharge: "$0.33", barFraction: 0.125, active: false),
        FscBracket_395(id: "3.25-3.50", range: "$3.25 – 3.50", surcharge: "$0.37", barFraction: 0.292, active: false),
        FscBracket_395(id: "3.50-3.75", range: "$3.50 – 3.75", surcharge: "$0.42", barFraction: 0.500, active: false),
        FscBracket_395(id: "3.75-4.00", range: "$3.75 – 4.00", surcharge: "$0.46", barFraction: 0.667, active: true),
        FscBracket_395(id: "4.00-4.25", range: "$4.00 – 4.25", surcharge: "$0.50", barFraction: 0.833, active: false),
        FscBracket_395(id: "4.25-4.50", range: "$4.25 – 4.50", surcharge: "$0.54", barFraction: 1.000, active: false),
    ]
    @State private var nextStepDiesel: String    = "$4.00"
    @State private var nextStepSurcharge: String = "$0.50/mi"
    @State private var nextStepDelta: String     = "+$0.04"

    // Footer · attached lanes
    @State private var attachedLanes: Int  = 6
    @State private var fscBilled: String   = "$4,210"
    @State private var billedWindow: String = "90d"

    @State private var refreshing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_395
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard_395
                    ladderSection_395
                    attachedFooter_395
                    ctaRow_395
                    legend_395
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

    // MARK: - TopBar

    private var topBar_395: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("CATALYST · FUEL SURCHARGE · PADD 3")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text(scheduleId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                Text("Fuel surcharge")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero · PADD-3 diesel index gauge

    private var heroCard_395: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(paddRegion) · \(weekLabel)")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dieselPrice)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("/gal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    indexGauge_395
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("SURCHARGE NOW")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(appliedSurcharge)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text("/mi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(nationalLine)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Brand.success)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 108)
    }

    private var indexGauge_395: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textTertiary.opacity(0.18)).frame(height: 6)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(8, w * gaugeFraction), height: 6)
                    Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 12)
                    Circle().fill(palette.bgCard)
                        .overlay(Circle().strokeBorder(Brand.magenta, lineWidth: 2.5))
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, w * gaugeFraction - 5))
                }
                .frame(height: 12)
            }
            .frame(width: 200, height: 12)
            HStack {
                Text(basePegLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(ceilingLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 200)
        }
    }

    // MARK: - Step ladder

    private var ladderSection_395: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SURCHARGE TABLE · ¢/MI BY DIESEL $/GAL")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(methodLabel)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("DIESEL BAND $/GAL")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("SURCHARGE")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s2)
                Rectangle().fill(palette.borderFaint).frame(height: 1)

                ForEach(Array(brackets.enumerated()), id: \.element.id) { idx, b in
                    bracketRow_395(b)
                    if idx < brackets.count - 1 && !b.active && !brackets[idx + 1].active {
                        Rectangle().fill(palette.borderFaint.opacity(0.7))
                            .frame(height: 1)
                            .padding(.horizontal, Space.s4)
                    }
                }

                Rectangle().fill(palette.borderFaint).frame(height: 1)
                HStack(spacing: 0) {
                    (Text("Next step at ")
                        + Text(nextStepDiesel).fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" diesel → ")
                        + Text(nextStepSurcharge).fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" (\(nextStepDelta))"))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func bracketRow_395(_ b: FscBracket_395) -> some View {
        HStack(spacing: Space.s3) {
            Text(b.range)
                .font(EType.mono(.caption))
                .fontWeight(b.active ? .bold : .semibold)
                .foregroundStyle(b.active ? palette.textPrimary : palette.textSecondary)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                Capsule()
                    .fill(b.active
                          ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(Brand.rail.opacity(0.28)))
                    .frame(width: max(14, w * b.barFraction), height: 14)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            if b.active {
                Text("NOW")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            Text(b.surcharge)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 50)
        .background(activeBracketBackground_395(b.active))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(b.range) dollars per gallon, surcharge \(b.surcharge) per mile\(b.active ? ", active band" : "")")
    }

    @ViewBuilder
    private func activeBracketBackground_395(_ active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Brand.blue.opacity(0.10))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 3)
                }
                .padding(.horizontal, 6)
        } else {
            Color.clear
        }
    }

    // MARK: - Footer · attached lanes

    private var attachedFooter_395: some View {
        HStack {
            (Text("Attached to ")
                + Text("\(attachedLanes) active lanes").fontWeight(.bold).foregroundColor(palette.textPrimary)
                + Text(" · ")
                + Text(fscBilled).fontWeight(.bold).foregroundColor(palette.textPrimary)
                + Text(" FSC billed · \(billedWindow)"))
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Button {
                // WIRE: fscEngine.createSchedule (fscEngine.ts:49, mutation · method=table · adds a bracket row)
            } label: {
                Text("+ NEW BRACKET")
                    .font(EType.micro).tracking(0.4).fontWeight(.heavy)
                    .foregroundStyle(LinearGradient.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - CTA pair

    private var ctaRow_395: some View {
        HStack(spacing: Space.s2) {
            CTAButton(
                title: "Refresh PADD prices",
                action: {
                    // Live re-pull of the EIA PADD-3 diesel index lights the
                    // hero gauge. The server-side snapshot write is the
                    // fscEngine mutation below (not yet on iOS).
                    // WIRE: fscEngine.updatePaddPrices (fscEngine.ts:172, mutation · writes hz_fuel_prices + fsc_history + blockchainAudit, broadcasts FSC_SCHEDULE_UPDATED)
                    Task { await loadAll() }
                },
                isLoading: refreshing
            )

            Button {
                // WIRE: fscEngine.createSchedule (fscEngine.ts:49, mutation · method=table · tableEntries[])
            } label: {
                Text("Edit table")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132)
                    .frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit surcharge table")
        }
    }

    // MARK: - Legend

    private var legend_395: some View {
        HStack(spacing: Space.s4) {
            legendItem_395(
                swatch: AnyView(Capsule().fill(LinearGradient.diagonal).frame(width: 14, height: 8)),
                label: "live band today")
            legendItem_395(
                swatch: AnyView(Capsule().fill(Brand.rail.opacity(0.34)).frame(width: 14, height: 8)),
                label: "inactive band")
            legendItem_395(
                swatch: AnyView(Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 8)),
                label: "base peg")
            Spacer(minLength: 0)
        }
    }

    private func legendItem_395(swatch: AnyView, label: String) -> some View {
        HStack(spacing: 6) {
            swatch
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Network

    private func loadAll() async {
        refreshing = true
        defer { refreshing = false }
        // Live PADD-3 Gulf Coast diesel index → hero gauge + national line.
        // rateSheet.getCurrentDiesel EXISTS on iOS; the fscEngine ladder
        // procedures do not yet, so the bracket table keeps its SVG-verbatim
        // seeds (overwritten the moment getSchedulePreview ships).
        guard let diesel = try? await EusoTripAPI.shared.rateSheet.getCurrentDiesel(padd: "3") else {
            return
        }
        applyDiesel_395(diesel)
    }

    private func applyDiesel_395(_ d: RateSheetAPI.CurrentDiesel) {
        // Price → "$3.75"
        dieselPrice = formatPrice_395(d.price)
        // Gauge fraction over the $1.25 base peg → $5.00 ceiling band.
        let basePeg = 1.25, ceiling = 5.00
        let frac = (d.price - basePeg) / (ceiling - basePeg)
        gaugeFraction = min(1.0, max(0.0, frac))
        // PADD label (server echoes "3" / "PADD 3" / region name).
        if let p = d.padd, !p.isEmpty {
            paddRegion = p.uppercased().contains("PADD") ? p.uppercased() : "PADD \(p) GULF COAST"
        }
        // Week-of label from the EIA report date + source provenance.
        if let rd = d.reportDate, !rd.isEmpty {
            weekLabel = "EIA \(shortDate_395(rd))"
        } else if d.source == "EIA" {
            weekLabel = "EIA LIVE"
        }
        // National line: live price + honest week-over-week Δ when present.
        nationalLine = nationalLine_395(price: d.price, change1w: d.change1w)
    }

    private func nationalLine_395(price: Double, change1w: Double?) -> String {
        let base = "natl \(formatPrice_395(price))"
        guard let w = change1w, w != 0 else { return "\(base) · flat wk" }
        let sign = w > 0 ? "+" : "-"
        return "\(base) · \(sign)\(formatPrice_395(abs(w))) wk"
    }

    private func formatPrice_395(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func shortDate_395(_ raw: String) -> String {
        // "2026-05-25" → "WK21"-style short tag; fall back to the raw prefix.
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }
}

// MARK: - Previews

#Preview("395 · Catalyst · Fuel Surcharge · Night") {
    CatalystFuelSurchargeScheduleScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("395 · Catalyst · Fuel Surcharge · Afternoon") {
    CatalystFuelSurchargeScheduleScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
