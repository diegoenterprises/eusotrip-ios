//
//  396_CatalystLaneRateSheet.swift
//  EusoTrip — Catalyst · Lane Rate Sheet (carrier back-office growth band).
//
//  Verbatim iOS-house port of the canonical bespoke wireframe:
//    03 Catalyst/Code/396_CatalystLaneRateSheet.swift
//    03 Catalyst/Dark-SVG/396 Catalyst Lane Rate Sheet.svg
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op · USDOT 3 194 882 ·
//  MC-820 144 · Belle Plaine IA) opens his lane pricebook from the
//  Dispatch tab to check, before the next round of tenders, where his
//  quoted rate-per-mile sits against the live platform clearing rate on
//  each lane he runs. This is NOT the stamped home/detail skeleton: the
//  body is a RATE-SPREAD board — a blended RPM-vs-market hero, then
//  per-lane rows whose distinctive element is a CENTER-ZERO SPREAD BAR
//  (green above market, amber below) in place of the usual 8-stage
//  lifecycle dots. It turns guesswork bidding into a margin-defended
//  pricebook: Michael sees the two lanes priced under market bleeding
//  RPM and the one priced 6% over that may be losing tenders.
//
//  Web peer: /catalyst/rates (rate sheet manager).
//  tRPC wiring manifest (per the Code/ spec — line-confirmed on disk):
//    • hero blended RPM + market spread  → rateSheet.getPlatformRateIntelligence (rateSheet.ts:706)
//    • diesel / FSC band                 → rateSheet.getCurrentDiesel            (rateSheet.ts:611)
//    • per-lane your-rate rows           → rateSheet.getRateSheet                (rateSheet.ts:1425)
//                                          + rateSheet.listMyRateSheets          (rateSheet.ts:1618)
//    • "Recalculate rates" CTA           → rateSheet.calculateRate               (rateSheet.ts:812)
//    • "Edit sheet" / save + version     → rateSheet.saveRateSheet               (rateSheet.ts:1370)
//                                          → getVersionHistory                   (rateSheet.ts:1578)
//  RBAC: isolatedApprovedProcedure — carrier-scoped. transportMode = truck · USD.
//
//  HONEST WIRING (iOS EusoTripAPI.RateSheetAPI — grep-verified):
//    • getCurrentDiesel EXISTS → the DOE-diesel band hydrates live (price,
//      1-week change, source freshness). The remaining seeds (FSC peg,
//      hero RPM-vs-market, per-lane spreads) are overwritten on hydrate
//      ONCE the platform-rate-intelligence client method ships — the iOS
//      RateSheetAPI does not yet expose `getPlatformRateIntelligence` /
//      `saveRateSheet`, so those carry a // WIRE: marker and the Code/
//      representative seeds (house "0% mock — seeds overwritten on
//      hydrate"). The lane RPM-vs-market board is NOT representable from
//      getRateSheet (BBL mileage tiers), so it stays seeded until the
//      rate-intelligence projection lands.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME
//  (DISPATCH current — the rate sheet is reached from the Dispatch tab).
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystLaneRateSheetScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            LaneRateSheetBody_396()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_396(),
                trailing: catalystNavTrailing_396(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_396() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_396() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Lane row model (mirrors the rateSheet.* lane projection)

private enum LaneEquipment_396 { case dryVan, reefer, tanker, flatbed }

private struct LaneRate_396: Identifiable {
    let id: String              // rateSheet row id
    let lane: String            // "Houston → Dallas"
    let spec: String            // "53' Dry Van · 239 mi"
    let equipment: LaneEquipment_396
    let yourRate: Double        // $/mi
    let marketRate: Double      // $/mi (getPlatformRateIntelligence)
    var spreadPct: Double { (yourRate - marketRate) / marketRate * 100 }
    var isAbove: Bool { yourRate >= marketRate }
}

// MARK: - Body

private struct LaneRateSheetBody_396: View {
    @Environment(\.palette) private var palette

    // ----- Diesel / FSC band (getCurrentDiesel — LIVE) -----
    @State private var doeDiesel: String   = "$4.012"     // /gal · overwritten on hydrate
    @State private var fscPeg: String      = "$0.42"      // /mi  · WIRE: derived peg
    @State private var weekDelta: String   = "+$0.03"     // WK Δ · overwritten on hydrate
    @State private var refreshedAgo: String = "6m ago"    // overwritten on hydrate
    @State private var weekDeltaUp: Bool   = true

    // ----- Hero (getPlatformRateIntelligence — seeded · WIRE) -----
    @State private var blendedRPM: String  = "$2.84"
    @State private var marketClears: String = "$2.71/mi"
    @State private var activeLanes: Int    = 8
    @State private var blendedSpreadPct: Double = 4.8
    @State private var winCover: String    = "96.4%"

    // ----- Lanes (getRateSheet / listMyRateSheets — seeded · WIRE) -----
    @State private var lanes: [LaneRate_396] = LaneRateSheetBody_396.seedLanes
    @State private var underMarketNote: String = "2 lanes under market · ~$118/load RPM gap on KC→Omaha"
    @State private var version: String = "v4"

    static let seedLanes: [LaneRate_396] = [
        LaneRate_396(id: "rs-hou-dal", lane: "Houston → Dallas",
                     spec: "53' Dry Van · 239 mi", equipment: .dryVan,
                     yourRate: 2.91, marketRate: 2.74),
        LaneRate_396(id: "rs-la-phx", lane: "LA → Phoenix",
                     spec: "53' Reefer 38°F · 372 mi", equipment: .reefer,
                     yourRate: 3.02, marketRate: 2.98),
        LaneRate_396(id: "rs-kc-oma", lane: "KC → Omaha",
                     spec: "MC-331 NH₃ · escort · 185 mi", equipment: .tanker,
                     yourRate: 3.18, marketRate: 3.41),
        LaneRate_396(id: "rs-pit-cle", lane: "Pittsburgh → Cleveland",
                     spec: "48' Flatbed · steel coils · 134 mi", equipment: .flatbed,
                     yourRate: 2.46, marketRate: 2.55),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_396
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                dieselBand_396
                heroCard_396
                lanesSection_396
                ctaRow_396
                legend_396
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: TopBar — eyebrow + back chevron + "Lane rates" + version + kebab

    private var topBar_396: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("CATALYST · RATE SHEET · DOE WK21")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text("\(version) · \(lanes.count) LANES")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Dispatch")
                Text("Lane rates")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                kebab_396
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var kebab_396: some View {
        VStack(spacing: 3) {
            Circle().frame(width: 4, height: 4)
            Circle().frame(width: 4, height: 4)
            Circle().frame(width: 4, height: 4)
        }
        .foregroundStyle(palette.textPrimary)
        .frame(width: 28, height: 28)
        .accessibilityLabel("Rate sheet actions")
    }

    // MARK: Diesel / FSC band (getCurrentDiesel — LIVE)

    private var dieselBand_396: some View {
        HStack(spacing: 0) {
            bandStat_396(label: "DOE DIESEL", value: doeDiesel, unit: "/gal",
                         valueColor: palette.textPrimary)
            bandDivider_396
            bandStat_396(label: "FSC PEG", value: fscPeg, unit: "/mi",
                         valueColor: palette.textPrimary)
            bandDivider_396
            bandStat_396(label: "WK Δ", value: weekDelta, unit: "",
                         valueColor: weekDeltaUp ? Brand.success : Brand.danger)
            Spacer(minLength: 4)
            Text(refreshedAgo)
                .font(EType.micro).tracking(0.3).fontWeight(.heavy)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(palette.bgCardSoft))
        }
        .padding(.horizontal, Space.s3)
        .frame(height: 48)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func bandStat_396(label: String, value: String, unit: String,
                              valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro).tracking(0.8).foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.trailing, 14)
    }

    private var bandDivider_396: some View {
        Rectangle().fill(palette.borderFaint)
            .frame(width: 1, height: 24)
            .padding(.trailing, 14)
    }

    // MARK: Hero — blended RPM vs market (gradient-rim card)

    private var heroCard_396: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard).padding(1.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BLENDED RPM · 90-DAY · ALL-IN")
                        .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(blendedRPM)
                            .font(.system(size: 38, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("/mi").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    (Text("market clears ")
                        + Text(marketClears).fontWeight(.bold).foregroundColor(palette.textPrimary)
                        + Text(" · \(activeLanes) active lanes"))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    spreadChip_396(pct: blendedSpreadPct)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TENDER WIN-COVER").font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(winCover)
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 104)
    }

    private func spreadChip_396(pct: Double) -> some View {
        let up = pct >= 0
        let color = up ? Brand.success : Brand.warning
        return HStack(spacing: 4) {
            Image(systemName: "triangle.fill")
                .rotationEffect(.degrees(up ? 0 : 180))
                .font(.system(size: 7, weight: .black)).foregroundStyle(color)
            Text(String(format: "%+.1f%% mkt", pct))
                .font(.system(size: 11, weight: .heavy).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: Lanes section — your rate vs market spread rows

    private var lanesSection_396: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LANES · YOUR RATE vs MARKET").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("See all (\(activeLanes))").font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(lanes.enumerated()), id: \.element.id) { idx, lane in
                    laneRow_396(lane)
                    if idx < lanes.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
                HStack {
                    Text(underMarketNote).font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text("+ ADD LANE").font(EType.micro).tracking(0.4).fontWeight(.heavy)
                        .foregroundStyle(LinearGradient.primary)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func laneRow_396(_ lane: LaneRate_396) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Space.s3) {
                equipmentChip_396(lane.equipment)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lane.lane).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(lane.spec).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "$%.2f/mi", lane.yourRate))
                        .font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(String(format: "mkt $%.2f", lane.marketRate))
                        .font(EType.caption).monospacedDigit().foregroundStyle(palette.textTertiary)
                }
            }
            spreadBar_396(lane)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lane.lane), your rate \(String(format: "%.2f", lane.yourRate)) per mile, "
            + "\(lane.isAbove ? "above" : "below") market by \(String(format: "%.1f", abs(lane.spreadPct))) percent")
    }

    // Center-zero spread bar: market = mid; fill from mid toward the marker.
    private func spreadBar_396(_ lane: LaneRate_396) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let mid = w / 2
            let frac = min(abs(lane.spreadPct) / 10.0, 1.0)   // clamp ±10% across half-width
            let markerX = lane.isAbove ? mid + (w / 2 - 14) * frac
                                       : mid - (w / 2 - 14) * frac
            let color = lane.isAbove ? Brand.success : Brand.warning
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textTertiary.opacity(0.18)).frame(height: 4)
                Path { p in
                    let lo = min(mid, markerX), hi = max(mid, markerX)
                    p.addRoundedRect(in: CGRect(x: lo, y: 8, width: hi - lo, height: 4),
                                     cornerSize: CGSize(width: 2, height: 2))
                }.fill(color)
                Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 10)
                    .position(x: mid, y: 10)
                Circle().fill(color).frame(width: 8, height: 8).position(x: markerX, y: 10)
                Text(String(format: "%+.1f%%", lane.spreadPct))
                    .font(.system(size: 9, weight: .heavy).monospacedDigit())
                    .foregroundStyle(color)
                    .position(x: w - 16, y: -2)
            }
        }
        .frame(height: 12)
        .padding(.leading, 48)
    }

    @ViewBuilder
    private func equipmentChip_396(_ eq: LaneEquipment_396) -> some View {
        let icon = equipmentIcon_396(eq)
        let tint = equipmentTint_396(eq)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(tint.opacity(0.16))
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
    }

    private func equipmentIcon_396(_ eq: LaneEquipment_396) -> String {
        switch eq {
        case .dryVan:  return "box.truck"
        case .reefer:  return "thermometer.snowflake"
        case .tanker:  return "drop.triangle"
        case .flatbed: return "rectangle.compress.vertical"
        }
    }

    private func equipmentTint_396(_ eq: LaneEquipment_396) -> Color {
        switch eq {
        case .dryVan:  return Brand.rail
        case .reefer:  return Brand.info
        case .tanker:  return Brand.warning
        case .flatbed: return palette.textPrimary
        }
    }

    // MARK: CTA pair + legend

    private var ctaRow_396: some View {
        HStack(spacing: Space.s2) {
            Button {
                // WIRE: rateSheet.calculateRate (rateSheet.ts:812) —
                // recompute every lane RPM against the live diesel/FSC peg.
                NotificationCenter.default.post(
                    name: .eusoCatalystRateRecalculate_396, object: nil,
                    userInfo: ["source": "396_CatalystLaneRateSheet"])
            } label: {
                Text("Recalculate rates").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recalculate all lane rates")

            Button {
                // WIRE: rateSheet.saveRateSheet (rateSheet.ts:1370) +
                // getVersionHistory (rateSheet.ts:1578) — edit + version bump.
                NotificationCenter.default.post(
                    name: .eusoCatalystRateEditSheet_396, object: nil,
                    userInfo: ["source": "396_CatalystLaneRateSheet"])
            } label: {
                Text("Edit sheet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit rate sheet")
        }
    }

    private var legend_396: some View {
        HStack(spacing: Space.s4) {
            legendDot_396(color: Brand.success, label: "above market")
            legendDot_396(color: Brand.warning, label: "below market")
            HStack(spacing: 6) {
                Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 8)
                Text("market clearing").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func legendDot_396(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Network
    //
    // getCurrentDiesel EXISTS on the iOS RateSheetAPI → hydrates the DOE
    // diesel band live (price · 1-week change · source freshness). The
    // hero blended-RPM-vs-market spread, the FSC peg, and the per-lane
    // spread rows come from rateSheet.getPlatformRateIntelligence, which
    // the iOS client does not yet expose — those keep the Code/ seeds
    // (overwritten on hydrate once the method ships) and carry the WIRE
    // markers below.

    private func loadAll() async {
        do {
            let diesel = try await EusoTripAPI.shared.rateSheet.getCurrentDiesel()
            self.doeDiesel = String(format: "$%.3f", diesel.price)
            if let w = diesel.change1w {
                self.weekDeltaUp = w >= 0
                self.weekDelta = String(format: "%@$%.2f", w >= 0 ? "+" : "−", abs(w))
            }
            // Source/freshness chip: "EIA" when live-fed, report date otherwise.
            if diesel.source.uppercased() == "EIA" {
                self.refreshedAgo = "EIA live"
            } else if let r = diesel.reportDate, !r.isEmpty {
                self.refreshedAgo = String(r.prefix(10))
            }
        } catch {
            // Keep the representative seed band — honest, not a crash.
        }

        // WIRE: rateSheet.getPlatformRateIntelligence (rateSheet.ts:706)
        //   → blendedRPM · marketClears · activeLanes · blendedSpreadPct
        //     · winCover · per-lane yourRate/marketRate spread board.
        // WIRE: rateSheet.getRateSheet (rateSheet.ts:1425)
        //     + rateSheet.listMyRateSheets (rateSheet.ts:1618)
        //   → the carrier's active sheet id + version eyebrow for the lane rows.
        // (Both kept seeded — the iOS RateSheetAPI does not yet expose the
        //  platform-rate-intelligence projection; getRateSheet returns BBL
        //  mileage tiers, not lane RPM-vs-market pairs.)
    }
}

// MARK: - Notifications (no dead buttons per §20.4 doctrine)

extension Notification.Name {
    static let eusoCatalystRateRecalculate_396 = Notification.Name("eusoCatalystRateRecalculate_396")
    static let eusoCatalystRateEditSheet_396   = Notification.Name("eusoCatalystRateEditSheet_396")
}

// MARK: - Previews

#Preview("396 · Catalyst · Lane Rate Sheet · Night") {
    CatalystLaneRateSheetScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("396 · Catalyst · Lane Rate Sheet · Afternoon") {
    CatalystLaneRateSheetScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
