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
//  ZERO-FALLBACK WIRING (2026-06-09 · audit M5):
//    LIVE — getCurrentDiesel (DOE band), listMyRateSheets + getRateSheet
//    (sheet identity + real version), getPlatformRateIntelligence (market
//    clearing RPM from real completed loads).
//    HONEST EM-DASH / EMPTY — blended RPM, win-cover, FSC peg, and the
//    per-lane spread board: getRateSheet carries BBL mileage tiers, not
//    lane RPM-vs-market pairs, so the board renders an EusoEmptyState
//    until a per-lane rate-intelligence projection ships. No seeds remain.
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

    // ----- Diesel / FSC band (getCurrentDiesel — LIVE; em-dash until it answers) -----
    @State private var doeDiesel: String   = "—"
    @State private var fscPeg: String      = "—"     // no live peg source → honest em-dash
    @State private var weekDelta: String   = "—"
    @State private var refreshedAgo: String = "—"
    @State private var weekDeltaUp: Bool   = true

    // ----- Hero (live platform-rate intelligence; em-dash where no source) -----
    @State private var blendedRPM: String  = "—"     // carrier's own blended RPM — no live source yet
    @State private var marketClears: String = "—"    // LIVE: rateSheet.getPlatformRateIntelligence
    @State private var blendedSpreadPct: Double? = nil
    @State private var winCover: String    = "—"     // no live source → honest em-dash

    // ----- Sheet identity (LIVE: listMyRateSheets + getRateSheet) -----
    @State private var lanes: [LaneRate_396] = []
    @State private var underMarketNote: String = ""
    @State private var version: String = "—"
    @State private var sheetName: String? = nil
    @State private var loadingSheet: Bool = true

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
                    Text("CATALYST · RATE SHEET")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text("\(version) · \(sheetName?.uppercased() ?? "NO SHEET")")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                        + Text(" · \(lanes.count) lanes on sheet"))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    if let pct = blendedSpreadPct {
                        spreadChip_396(pct: pct)
                    }
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
                Text("See all (\(lanes.count))").font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if lanes.isEmpty {
                    // Honest: the per-lane RPM-vs-market projection has no
                    // live source (getRateSheet carries BBL mileage tiers,
                    // not lane RPM pairs) — never a seeded spread board.
                    EusoEmptyState(
                        systemImage: "chart.bar.xaxis",
                        title: loadingSheet ? "Loading rate sheet…" : "No lane spread data yet",
                        subtitle: loadingSheet ? "" : "Per-lane rate-vs-market rows aren't connected to mobile yet - sheet identity and the diesel band above are live."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { idx, lane in
                        laneRow_396(lane)
                        if idx < lanes.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.leading, 48)
                        }
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

    // MARK: - Network (zero-fallback · audit M5)
    //
    // LIVE: getCurrentDiesel (band), listMyRateSheets + getRateSheet (sheet
    // identity + version), getPlatformRateIntelligence (market clearing RPM).
    // Honest em-dash: blended RPM, win-cover, FSC peg and the per-lane spread
    // board — none has a live per-lane source on mobile yet (getRateSheet
    // carries BBL mileage tiers, not lane RPM pairs).

    private struct RateIntelWire_396: Decodable {
        let totalLoads: Int
        let avgRatePerMile: Double
        let lastUpdated: String?
    }
    private struct RateIntelInput_396: Encodable { let state: String? }

    private func loadAll() async {
        loadingSheet = true
        defer { loadingSheet = false }

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
            // Band stays em-dash — honest, not a crash.
        }

        // Sheet identity + version — LIVE (already-bridged client methods).
        if let sheets = try? await EusoTripAPI.shared.rateSheet.listMyRateSheets(),
           let first = sheets.first {
            sheetName = first.name ?? "Sheet \(first.id)"
            // `try?` flattens the client's RateSheetDetail? — one bind suffices.
            if let d = try? await EusoTripAPI.shared.rateSheet.getRateSheet(id: first.id) {
                version = "v\(d.version)"
            }
        } else {
            sheetName = nil
            version = "—"
        }

        // Market clearing RPM — LIVE platform aggregate (real completed loads).
        if let intel: RateIntelWire_396 = try? await EusoTripAPI.shared.query(
            "rateSheet.getPlatformRateIntelligence", input: RateIntelInput_396(state: nil)
        ), intel.totalLoads > 0, intel.avgRatePerMile > 0 {
            marketClears = String(format: "$%.2f/mi", intel.avgRatePerMile)
        } else {
            marketClears = "—"
        }
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
