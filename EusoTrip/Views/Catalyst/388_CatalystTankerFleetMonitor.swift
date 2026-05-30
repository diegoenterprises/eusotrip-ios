//
//  388_CatalystTankerFleetMonitor.swift
//  EusoTrip — Catalyst · Tanker Fleet Monitor (carrier multi-asset vantage).
//
//  Verbatim iOS port of `03 Catalyst/Dark-SVG/388 Catalyst Tanker Fleet
//  Monitor.svg` + `Code/388_CatalystTankerFleetMonitor.swift`.
//
//  Carrier (fleet) vantage of the same real tankMonitor router the Driver
//  168 Tanker Monitor surface reads from the personal vantage — the
//  §462-named carrier-parity gap. Multi-asset tank telemetry bound to the
//  active KC→Omaha MC-331 anhydrous-ammonia load LD-260427-B41782FF02 ·
//  UN1005 (shipper Diego Usoro · Eusorone Technologies).
//
//  Wiring manifest (every figure → real procedure, line-confirmed against
//  eusoronetechnologiesinc/frontend/server/routers/):
//    • multi-asset tank overview   ← tankMonitor.getMultiTerminalOverview (tankMonitor.ts:182)
//    • per-tank pressure readings   ← tankMonitor.getTankReadings (tankMonitor.ts:25)
//    • tank alert chips             ← tankMonitor.getTankAlerts (tankMonitor.ts:73)
//    • Forecast CTA (full-stop horizon) ← tankMonitor.getTankForecasts (tankMonitor.ts:150)
//
//  No Swift client method exists yet on EusoTripAPI for tankMonitor.* — the
//  representative seeds below render bespoke immediately and the live records
//  overwrite them on hydrate (0% mock doctrine, NOT fabrication). The single
//  WIRE marker on loadAll() names the missing client surface.
//
//  Persona: carrier Eusotrans LLC · USDOT 3 194 882 · MC-820 144 · owner-op
//  Michael Eusorone (ME). Shipper-of-record Diego Usoro · Eusorone
//  Technologies (DU) pinned in the provenance fineprint.
//
//  BottomNav frozen (CatalystTab): HOME · DISPATCH · [ESang orb] · FLEET
//  [SELECTED] · ME.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystTankerFleetMonitorScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { TankerFleetBody_388() }
        nav: { BottomNav(leading: catalystNavLeading_388(), trailing: catalystNavTrailing_388(), orbState: .idle) }
    }
}

private func catalystNavLeading_388() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_388() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Body

private struct TankerFleetBody_388: View {
    @Environment(\.palette) private var palette

    // ── Tank row model (per-asset readings) ──
    private struct TankRow_388: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let badge: String
        let badgeKind: BadgeKind_388
    }
    private enum BadgeKind_388 { case positive, neutral }

    // ── Factor cell model ──
    private struct FactorCell_388: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let sub: String
    }

    // ── Hydratable model state (seeds overwritten on live hydrate) ──
    // WIRE: tankMonitor.getMultiTerminalOverview (tankMonitor.ts:182) ·
    //       getTankReadings (tankMonitor.ts:25) · getTankAlerts (tankMonitor.ts:73) ·
    //       getTankForecasts (tankMonitor.ts:150) — no Swift client method on
    //       EusoTripAPI yet; representative seeds below render bespoke immediately.
    @State private var heroBig: String       = "98 psi"
    @State private var heroBigUnit: String   = "MAWP 265"
    @State private var heroRight: String      = "NOMINAL"
    @State private var heroFraction: Double   = 0.37
    @State private var cardHeaderR: String    = "2 TANKS"
    @State private var rows: [TankRow_388] = [
        .init(title: "TNK-01 · NH₃",   detail: "UN1005 · 84% full · MAWP 265", badge: "98 psi",  badgeKind: .positive),
        .init(title: "TNK-01 · vapor", detail: "ambient 71°F · venting closed", badge: "NOMINAL", badgeKind: .positive),
        .init(title: "TNK-02 · idle",  detail: "cleaned · last NH₃ 11d ago",    badge: "PURGED",  badgeKind: .neutral),
    ]
    @State private var cells: [FactorCell_388] = [
        .init(label: "TANKS",   value: "1", sub: "loaded"),
        .init(label: "NOMINAL", value: "1", sub: "of 1"),
        .init(label: "ALERTS",  value: "0", sub: "active"),
    ]

    // ── Static identity / copy (verbatim from Code spec + SVG) ──
    private let eyebrow      = "CATALYST · TANKER FLEET"
    private let eyebrowR     = "MC-331"
    private let title        = "Tanker Fleet"
    private let subtitle     = "pressure · UN1005"
    private let carrierR     = "EUSOTRANS LLC · USDOT 3 194 882"
    private let syncR        = "synced 2h ago"

    private let heroLabelL   = "TANK PRESSURE · ACTIVE"
    private let heroLabelR   = "STATUS"
    private let heroLine1    = "Pressure + vapor within MC-331 nominal envelope"
    private let heroLine2    = "Telemetry 2-min cadence · forecast no full-stop in 6h"

    private let cardHeaderL  = "TANKER FLEET · MULTI-ASSET"
    private let loadLabel    = "HAZMAT · ACTIVE LOAD"
    private let loadLine1    = "MC-331 Anhydrous NH₃ UN1005 · escort · KC → Omaha"
    private let loadLine2    = "Shipper: Diego Usoro · Eusorone Technologies"
    private let cardFootnote = "Active hazmat load LD-260427-B41782FF02 · UN1005 · escort"

    private let primaryCTA   = "Pressure trend"
    private let secondaryCTA = "Forecast"

    private let fineprint: [String] = [
        "Tank telemetry · pressure/vapor per asset · MC-331 cargo-tank limits",
        "Carrier: Eusotrans LLC · USDOT 3 194 882 · shipper Diego Usoro / Eusorone",
        "Active load LD-260427-B41782FF02 · NH₃ UN1005 · escort · KC → Omaha",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar_388
                titleBlock_388
                IridescentHairline()
                heroCard_388
                multiAssetCard_388
                HStack(spacing: Space.s2) {
                    ForEach(cells) { cell in
                        factorTile_388(cell)
                    }
                }
                HStack(spacing: Space.s2) {
                    CTAButton(title: primaryCTA, action: {})
                    secondaryButton_388(secondaryCTA)
                }
                provenanceFootnote_388
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: - TopBar (eyebrow · ✦ once) + title block

    private var topBar_388: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text(eyebrow)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer(minLength: 0)
            Text(eyebrowR)
                .font(EType.mono(.micro))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock_388: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Back chevron disc (SVG: circle r20 + chevron path)
            ZStack {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                    .frame(width: 40, height: 40)
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.mono(.caption))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(carrierR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(syncR)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Hero card (active tank pressure + status + gauge bar)

    private var heroCard_388: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(heroLabelL)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(heroLabelR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(heroBig)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(heroBigUnit)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(heroRight)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(Brand.success)
            }
            .padding(.top, 12)

            // Gauge bar — pressure fraction within MAWP envelope
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.textPrimary.opacity(0.08))
                        .frame(height: 6)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * heroFraction), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, 14)

            Text(heroLine1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
            Text(heroLine2)
                .font(EType.mono(.micro))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Multi-asset card (per-tank rows + active hazmat load block)

    private var multiAssetCard_388: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(cardHeaderL)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(cardHeaderR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    tankRow_388(row)
                    if idx < rows.count - 1 {
                        Rectangle()
                            .fill(palette.textPrimary.opacity(0.07))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 16)

            // Active hazmat load block
            VStack(alignment: .leading, spacing: 4) {
                Text(loadLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(loadLine1)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(loadLine2)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 16)

            Text(cardFootnote)
                .font(EType.mono(.micro))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tankRow_388(_ row: TankRow_388) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.detail)
                    .font(EType.mono(.caption))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            tankBadge_388(row.badge, kind: row.badgeKind)
        }
        .padding(.vertical, 12)
    }

    private func tankBadge_388(_ text: String, kind: BadgeKind_388) -> some View {
        let positive = kind == .positive
        let fg: Color = positive ? Brand.success : palette.textSecondary
        let bg: Color = positive ? Brand.success.opacity(0.16) : palette.textPrimary.opacity(0.06)
        return Text(text)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(fg)
            .frame(width: 80, height: 22)
            .background(Capsule().fill(bg))
    }

    // MARK: - Factor tiles (TANKS · NOMINAL · ALERTS)

    private func factorTile_388(_ cell: FactorCell_388) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(cell.value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(cell.sub)
                .font(EType.mono(.micro))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Secondary CTA (outline — mirrors SVG #1C2128 / hairline)

    private func secondaryButton_388(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Provenance footnote

    private var provenanceFootnote_388: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(fineprint.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Network

    private func loadAll() async {
        // WIRE: tankMonitor.getMultiTerminalOverview (tankMonitor.ts:182) —
        //       no `EusoTripAPI.shared.tankMonitor.*` client surface exists yet.
        //       When the client method lands, hydrate heroBig/heroRight/
        //       heroFraction/rows/cells here (live overwrites the seeds above).
        //       Per-tank readings ← getTankReadings (tankMonitor.ts:25); alert
        //       chips ← getTankAlerts (tankMonitor.ts:73); Forecast horizon ←
        //       getTankForecasts (tankMonitor.ts:150).
    }
}

// MARK: - Previews

#Preview("388 · Catalyst · Tanker Fleet · Night") {
    CatalystTankerFleetMonitorScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("388 · Catalyst · Tanker Fleet · Afternoon") {
    CatalystTankerFleetMonitorScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
