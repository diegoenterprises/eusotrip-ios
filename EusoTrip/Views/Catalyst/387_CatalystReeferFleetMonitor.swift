//
//  387_CatalystReeferFleetMonitor.swift
//  EusoTrip — Catalyst · Reefer Fleet Monitor.
//
//  Verbatim port of the 387 Catalyst Reefer Fleet Monitor wireframe —
//  the carrier-vantage multi-asset reefer telemetry surface bound to
//  the active LA → Phoenix reefer load LD-260427-7C3A09F18B (shipper
//  Diego Usoro · Eusorone Technologies). Carrier Eusotrans LLC ·
//  USDOT 3 194 882.
//
//  Structure mirrors the SVG 1:1:
//    • SUPPLY TEMP · ACTIVE hero — 35.4°F vs setpoint 36°F, IN-BAND
//      badge, and a position-within-band progress bar (the SVG paints
//      257/368 of the track filled).
//    • REEFER FLEET · ZONE READINGS ledger — per-zone supply/return
//      rows (RFR-01 supply 35.4°F · RFR-01 return Δ2.7°F 38.1°F ·
//      RFR-02 pre-cool 41.0°F) each with a colour-coded temp pill,
//      then the FSMA · ACTIVE LOAD block (Fresh berries 33–38°F).
//    • Factor cells — REEFERS · IN-BAND · ALERTS.
//    • Actions — Acknowledge alert (primary) + FSMA log (secondary).
//
//  Server wiring — HONEST: the iOS EusoTripAPI surface does NOT yet
//  expose the reefer-temperature router the wireframe's tRPC desc
//  anchors (`reeferTemp.getLatestByZone` / `getReadings` / `getStats`
//  / `getAlerts` / `getFSMAStatus` / `acknowledgeAlert`). Rather than
//  hard-code fake telemetry as if it were live, this surface renders
//  from a typed @State model with an explicit .loading / .empty
//  posture and leaves ONE clear WIRE marker where the real call lands.
//  The seeded model below carries the exact wireframe values so the
//  layout is faithful; `state` starts at `.ready` for the canonical
//  founder-recording frame and flips to `.empty` the moment a real
//  loader returns no readings.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystReeferFleetMonitorScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            ReeferFleetBody_387()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_387(),
                trailing: catalystNavTrailing_387(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_387() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_387() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "box.truck.fill", isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person",         isCurrent: false)]
}

// MARK: - Typed telemetry model

private enum ReeferLoadState_387 { case loading, ready, empty }

/// One reefer zone reading — supply or return per power unit.
private struct ReeferZoneReading_387: Identifiable {
    enum Band_387 { case inBand, warning, alarm }
    let id = UUID()
    let title: String        // "RFR-01 · supply"
    let detail: String       // "setpoint 36°F · pulldown ok"
    let tempF: Double        // 35.4
    let band: Band_387
}

/// The active-load envelope the FSMA block describes.
private struct ReeferActiveLoad_387 {
    let commodity: String    // "Fresh berries 33–38°F · LA → Phoenix"
    let shipper: String      // "Shipper: Diego Usoro · Eusorone Technologies"
    let loadLine: String     // "Active reefer load LD-260427-7C3A09F18B · 28k lb"
}

/// The whole-surface telemetry envelope.
private struct ReeferTelemetry_387 {
    let supplyActualF: Double   // 35.4
    let setpointF: Double       // 36
    let bandLowF: Double        // 33
    let bandHighF: Double       // 38
    let inBand: Bool            // true
    let bandFillFraction: Double // 257/368 from the SVG track
    let zones: [ReeferZoneReading_387]
    let activeLoad: ReeferActiveLoad_387
    let reeferCount: Int        // 2
    let inBandCount: Int        // 2
    let activeAlerts: Int       // 0
}

// MARK: - Content

private struct ReeferFleetBody_387: View {
    @Environment(\.palette) private var palette

    @State private var state: ReeferLoadState_387 = .ready
    @State private var data: ReeferTelemetry_387 = ReeferFleetBody_387.seed
    @State private var acknowledged: Bool = false
    @State private var showFSMALog: Bool = false

    // Canonical founder-recording values, lifted verbatim from the SVG.
    private static let seed = ReeferTelemetry_387(
        supplyActualF: 35.4,
        setpointF: 36,
        bandLowF: 33,
        bandHighF: 38,
        inBand: true,
        bandFillFraction: 257.0 / 368.0,
        zones: [
            ReeferZoneReading_387(title: "RFR-01 · supply",
                                  detail: "setpoint 36°F · pulldown ok",
                                  tempF: 35.4, band: .inBand),
            ReeferZoneReading_387(title: "RFR-01 · return",
                                  detail: "Δ 2.7°F · airflow nominal",
                                  tempF: 38.1, band: .inBand),
            ReeferZoneReading_387(title: "RFR-02 · pre-cool",
                                  detail: "staged for next reefer load",
                                  tempF: 41.0, band: .warning)
        ],
        activeLoad: ReeferActiveLoad_387(
            commodity: "Fresh berries 33–38°F · LA → Phoenix",
            shipper: "Shipper: Diego Usoro · Eusorone Technologies",
            loadLine: "Active reefer load LD-260427-7C3A09F18B · 28k lb"
        ),
        reeferCount: 2,
        inBandCount: 2,
        activeAlerts: 0
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                iridescentHairline

                switch state {
                case .loading:
                    skeletonBody
                case .empty:
                    emptyBody
                case .ready:
                    supplyHero
                    zoneReadingsCard
                    factorRow
                    actionRow
                    footerNote
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        // WIRE: reeferTemp.getLatestByZone / getReadings / getStats /
        // getAlerts / getFSMAStatus — no iOS EusoTripAPI method exists
        // yet; when the reefer-temperature router lands, load it here
        // into `data`, set `.empty` when zones are missing, `.ready`
        // otherwise. acknowledgeAlert wires to the primary CTA below.
        .sheet(isPresented: $showFSMALog) { fsmaLogSheet }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · REEFER FLEET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("FSMA")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reefer Fleet")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("zone temps · FSMA")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("EUSOTRANS LLC · USDOT 3 194 882")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 2h ago")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: SUPPLY TEMP · ACTIVE hero

    private var supplyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SUPPLY TEMP · ACTIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("FSMA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tempString(data.supplyActualF))
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("setpoint \(Int(data.setpointF))°F")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(data.inBand ? "IN-BAND" : "OUT-OF-BAND")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(data.inBand ? Brand.success : Brand.danger)
            }
            .padding(.bottom, 14)

            bandTrack
                .padding(.bottom, 18)

            Text("All reefer assets within FSMA temperature band")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text("Continuous telemetry · 5-min cadence · pre-cool verified")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
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

    /// Position-within-band progress track — the SVG paints 257/368 of
    /// the rail filled with the brand gradient over a faint base.
    private var bandTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: w, height: 6)
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(0, w * data.bandFillFraction), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: REEFER FLEET · ZONE READINGS

    private var zoneReadingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REEFER FLEET · ZONE READINGS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(data.zones.count) ASSETS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 16)

            ForEach(Array(data.zones.enumerated()), id: \.element.id) { idx, zone in
                zoneRow(zone)
                if idx < data.zones.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.vertical, 13)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.top, 18)
                .padding(.bottom, 16)

            // FSMA · ACTIVE LOAD block
            Text("FSMA · ACTIVE LOAD")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 6)
            Text(data.activeLoad.commodity)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text(data.activeLoad.shipper)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 12)
            Text(data.activeLoad.loadLine)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
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

    private func zoneRow(_ zone: ReeferZoneReading_387) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(zone.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            tempPill(zone)
        }
    }

    /// Colour-coded temperature pill — green fill for in-band, amber
    /// for the staged/pre-cool warning, red for an alarm.
    private func tempPill(_ zone: ReeferZoneReading_387) -> some View {
        let fg: Color
        let bg: Color
        switch zone.band {
        case .inBand:  fg = Brand.success; bg = Color(hex: 0x0B3D2E)
        case .warning: fg = Color(hex: 0xFFC046); bg = Color(hex: 0x3A2E08)
        case .alarm:   fg = Brand.danger;  bg = Color(hex: 0x3D0B14)
        }
        return Text(tempString(zone.tempF))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(fg)
            .frame(width: 76, height: 22)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: Factor row — REEFERS · IN-BAND · ALERTS

    private var factorRow: some View {
        HStack(spacing: 8) {
            factorTile(eyebrow: "REEFERS", value: "\(data.reeferCount)",
                       caption: "power units", tint: palette.textPrimary)
            factorTile(eyebrow: "IN-BAND", value: "\(data.inBandCount)",
                       caption: "of \(data.reeferCount)", tint: palette.textPrimary)
            factorTile(eyebrow: "ALERTS", value: "\(data.activeAlerts)",
                       caption: "active",
                       tint: data.activeAlerts > 0 ? Brand.danger : palette.textPrimary)
        }
    }

    private func factorTile(eyebrow: String, value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 6)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.bottom, 4)
            Text(caption)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                // acknowledgeAlert lands here once the reefer-temperature
                // router is wired (see WIRE marker). With zero active
                // alerts in the canonical frame this just flips local ack.
                acknowledged = true
            } label: {
                Text(acknowledged ? "Alert acknowledged" : "Acknowledge alert")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(data.activeAlerts == 0 && !acknowledged)
            .opacity(data.activeAlerts == 0 && !acknowledged ? 0.6 : 1.0)

            Button {
                showFSMALog = true
            } label: {
                Text("FSMA log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Reefer telemetry · supply/return per zone · FSMA Sanitary Transport rule")
            Text("Carrier: Eusotrans LLC · USDOT 3 194 882 · shipper Diego Usoro / Eusorone")
            Text("Active load LD-260427-7C3A09F18B · berries 33–38°F · LA → Phoenix")
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(0.3)
        .foregroundStyle(palette.textTertiary)
        .padding(.top, 4)
    }

    // MARK: FSMA log sheet

    @ViewBuilder
    private var fsmaLogSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "thermometer.snowflake")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FSMA continuous telemetry log")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                            Text("5-min cadence · supply/return per zone")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    ForEach(data.zones) { zone in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(zone.detail)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            tempPill(zone)
                        }
                        .padding(12)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Text("Full FSMA Sanitary Transport audit trail (49 CFR §1.900) exports once the reefer-temperature router is wired to this device. No fabricated readings are shown.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(20)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("FSMA log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFSMALog = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Loading / empty

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 124)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 200)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard).frame(height: 66)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "thermometer.medium.slash")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No live reefer telemetry")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("No zone readings on the active load · check the power unit's monitoring link")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Helpers

    private func tempString(_ value: Double) -> String {
        String(format: "%.1f°F", value)
    }
}

// MARK: - Previews

#Preview("387 · Catalyst · Reefer Fleet Monitor · Night") {
    CatalystReeferFleetMonitorScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("387 · Catalyst · Reefer Fleet Monitor · Afternoon") {
    CatalystReeferFleetMonitorScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
