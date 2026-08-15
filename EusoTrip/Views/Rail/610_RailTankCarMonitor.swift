//
//  610_RailTankCarMonitor.swift
//  EusoTrip — Rail Engineer · Tank Car Monitor (HAZMAT · INSTRUMENT archetype).
//
//  Reconstructed from the stamped gauge+3KPI+3row skeleton into a purpose-built
//  hazmat INSTRUMENT surface: a radial vapor-pressure DIAL hero (green nominal
//  zone + red redline arc + gradient needle at the live reading), a CARS/NOMINAL/
//  ALERTS strip, per-car SAFETY-ENVELOPE rows (each reading plotted vs its redline
//  in a bullet bar), and an ALERTS ledger where every alert routes through a
//  confirm-gated Acknowledge sign-off. The dial reads vapor pressure vs MAWP for
//  pressurized tanks and falls back to fill-level vs the overfill redline for
//  atmospheric tanks — bound to the real reading, never fabricated.
//
//  Live wiring:
//   • dial + envelope rows  → tankMonitor.getTankReadings  ({terminalId})
//   • alerts ledger         → tankMonitor.getTankAlerts     ({terminalId})
//   • Acknowledge (each + hero review) → tankMonitor.acknowledgeTankAlert
//     (mutation · confirm:true human-gate → tank_acks row + blockchain audit)
//   • Trend & forecast CTA  → tankMonitor.getTankTrend + getTankForecasts
//  Honest: an empty terminal renders a real empty state, never a dressed-up gauge.
//

import SwiftUI

struct RailTankCarMonitorScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailTankCarMonitorBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable models (match tankMonitor.getTankReadings / getTankAlerts)

private struct TankReading610: Decodable, Identifiable {
    var id: String { tankId }
    let tankId: String
    let terminalId: Int
    let terminalName: String
    let tankNumber: Int
    let product: String
    let capacityGallons: Double
    let currentLevelGallons: Double
    let percentFull: Double
    let temperatureF: Double
    let pressurePsi: Double
    let mawpPsi: Double
    let apiGravity: Double
    let bswPercent: Double
    let ullageGallons: Double
    let status: String
    let lastGaugedAt: String?
}

private struct TerminalSummaryAlerts610: Decodable {
    let critical: Int
    let warning: Int
    let info: Int
}

private struct TerminalSummary610: Decodable {
    let terminalId: Int
    let terminalName: String
    let totalTanks: Int
    let totalCapacity: Double
    let totalInventory: Double
    let overallUtilization: Int
    let alerts: TerminalSummaryAlerts610
}

private struct TankReadingsResponse610: Decodable {
    let readings: [TankReading610]
    let summary: TerminalSummary610?
}

private struct TankAlert610: Decodable, Identifiable {
    let id: String
    let tankId: String
    let terminalId: Int
    let terminalName: String
    let tankNumber: Int
    let product: String
    let severity: String
    let type: String
    let message: String
    let currentLevel: Double
    let threshold: Double
    let triggeredAt: String
    let acknowledged: Bool
}

private struct AckResult610: Decodable {
    let success: Bool
    let tankAckId: String?
    let alertKey: String?
    let acknowledgedAt: String?
}

private struct TrendPoint610: Decodable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let levelGallons: Double
    let percentFull: Double
    let temperatureF: Double
}

private struct TrendResponse610: Decodable {
    let trend: [TrendPoint610]?
}

private struct Forecast610: Decodable, Identifiable {
    var id: String { tankId }
    let tankId: String
    let product: String
    let daysUntilReorder: Double
    let daysUntilEmpty: Double
    let confidence: Double
}

// MARK: - Acknowledge target (drives the confirm-gated sheet for both alerts + hero review)

private struct AckTarget610: Identifiable {
    let id: String          // alertKey
    let title: String
    let subtitle: String
    let terminalId: Int
    let tankNumber: String?
    let severity: String?
    let metric: String?
}

// MARK: - Body

private struct RailTankCarMonitorBody: View {
    @Environment(\.palette) private var palette

    @State private var terminalId: Int = 1
    @State private var readings: [TankReading610] = []
    @State private var summary: TerminalSummary610? = nil
    @State private var alerts: [TankAlert610] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Acknowledge flow (confirm-gated sheet)
    @State private var ackTarget: AckTarget610? = nil
    @State private var ackNote: String = ""
    @State private var ackSubmitting = false
    @State private var ackedKeys: Set<String> = []
    @State private var toast: String? = nil

    // Trend & forecast sheet
    @State private var showTrend = false
    @State private var trend: [TrendPoint610] = []
    @State private var forecasts: [Forecast610] = []
    @State private var trendLoading = false

    // MARK: Derived

    /// Hero tank = the pressurized car closest to (or over) its MAWP redline;
    /// otherwise the fullest tank (level-based safety envelope).
    private var heroReading: TankReading610? {
        guard !readings.isEmpty else { return nil }
        let pressurized = readings.filter { $0.mawpPsi > 0 }
        if !pressurized.isEmpty {
            return pressurized.max { ($0.pressurePsi / max($0.mawpPsi, 1)) < ($1.pressurePsi / max($1.mawpPsi, 1)) }
        }
        return readings.max { $0.percentFull < $1.percentFull }
    }

    private var heroIsPressure: Bool { (heroReading?.mawpPsi ?? 0) > 0 }
    private var heroValue: Double { heroIsPressure ? (heroReading?.pressurePsi ?? 0) : (heroReading?.percentFull ?? 0) }
    private var heroRedline: Double { heroIsPressure ? (heroReading?.mawpPsi ?? 0) : 95 }
    private var heroUnit: String { heroIsPressure ? "psi" : "%" }
    private var heroLabel: String { heroIsPressure ? "VAPOR PRESSURE" : "TANK LEVEL" }
    private var withinLimit: Int { readings.filter { $0.status == "normal" }.count }

    // MARK: Helpers

    private func productLabel(_ p: String) -> String {
        p.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func titleize(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "_", with: " ").lowercased()
        return t.isEmpty ? t : t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Real 49 CFR dangerous-goods context per product (UN number + class).
    private func hazmatContext(_ product: String) -> String {
        switch product {
        case "unleaded", "premium": return "UN1203 · class 3"
        case "diesel", "heating_oil": return "UN1202 · class 3"
        case "jet_fuel", "kerosene": return "UN1863 · class 3"
        case "ethanol": return "UN1170 · class 3"
        case "crude_oil": return "UN1267 · class 3"
        case "propane": return "UN1075 · class 2.1"
        case "biodiesel": return "combustible · non-DG"
        default: return "class 3"
        }
    }

    private func statusBadge(_ status: String) -> (String, Color) {
        switch status {
        case "normal":         return ("NOMINAL",  Brand.success)
        case "low":            return ("LOW",      Brand.warning)
        case "high":           return ("HIGH",     Brand.warning)
        case "maintenance":    return ("SERVICE",  Brand.warning)
        case "critical_low":   return ("CRIT LOW", Brand.danger)
        case "overfill_risk":  return ("OVERFILL", Brand.danger)
        case "leak_suspected": return ("LEAK",     Brand.danger)
        case "offline":        return ("OFFLINE",  palette.textTertiary)
        default:               return (status.uppercased(), Brand.info)
        }
    }

    private func statusSeverity(_ status: String) -> String {
        switch status {
        case "critical_low", "leak_suspected": return "emergency"
        case "overfill_risk": return "critical"
        case "low", "high", "maintenance": return "warning"
        default: return "info"
        }
    }

    private func severityColor(_ s: String?) -> Color {
        switch s {
        case "emergency", "critical": return Brand.danger
        case "warning": return Brand.warning
        case "info": return Brand.info
        default: return Brand.info
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                subheader
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading tank telemetry…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    terminalSelector
                    if readings.isEmpty {
                        LifecycleCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No live tank readings for terminal #\(terminalId).").font(EType.caption).foregroundStyle(palette.textSecondary)
                                Text("Ingest an ATG / SCADA gauge or select another terminal.").font(EType.caption).foregroundStyle(palette.textTertiary)
                            }
                        }
                    } else {
                        dialHero
                        kpiStrip
                        if !alerts.isEmpty { alertsSection } else { allClearCard }
                        envelopeSection
                        CTAButton(title: "Acknowledge tank review", action: { openReviewAck() }, leadingIcon: "checkmark.shield.fill")
                        CTAButton(title: "View trend & forecast", action: { showTrend = true }, leadingIcon: "chart.xyaxis.line")
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $ackTarget) { target in ackSheet(target) }
        .sheet(isPresented: $showTrend) { trendSheet }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · TANK CAR MONITOR").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("HAZMAT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.warning)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tank cars")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var subheader: some View {
        Group {
            if let h = heroReading {
                Text("\(productLabel(h.product)) · \(hazmatContext(h.product)) · \(summary?.terminalName ?? h.terminalName)")
                    .font(.system(size: 12, weight: .regular)).foregroundStyle(palette.textSecondary)
            } else {
                Text("Hazmat vapor-pressure + level safety monitor")
                    .font(.system(size: 12, weight: .regular)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Terminal selector

    private var terminalSelector: some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TERMINAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Text(summary?.terminalName ?? "Terminal #\(terminalId)")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
            }
            Spacer()
            Button {
                if terminalId > 1 { terminalId -= 1; Task { await load() } }
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(terminalId > 1 ? AnyShapeStyle(palette.textSecondary) : AnyShapeStyle(palette.textTertiary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(terminalId <= 1)
            Text("#\(terminalId)")
                .font(.system(size: 17, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                .frame(minWidth: 42)
            Button {
                terminalId += 1; Task { await load() }
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Dial hero

    private var dialHero: some View {
        let color = statusBadge(heroReading?.status ?? "normal").1
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(heroReading.map { productLabel($0.product) } ?? "—")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text(heroReading.map { "\($0.tankId) · \(hazmatContext($0.product))" } ?? "")
                            .font(.system(size: 10.5, weight: .semibold)).monospaced().foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(heroLabel)
                            .font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                        if heroReading?.status == "offline" {
                            Text("pressure est. (degraded)")
                                .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.warning.opacity(0.16)))
                        }
                    }
                }
                PressureDial610(value: heroValue, redline: heroRedline, unit: heroUnit, color: color, palette: palette)
                    .frame(height: 156)
                if let h = heroReading {
                    HStack(spacing: Space.s2) {
                        instrumentChip("LADING", "\(Int(h.temperatureF))°F")
                        instrumentChip("LEVEL", "\(Int(h.percentFull))%")
                        instrumentChip("OUTAGE", "\(Int(max(0, 100 - h.percentFull)))%")
                    }
                }
            }
            .padding(Space.s4)
        }
    }

    private func instrumentChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(palette.textTertiary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "CARS", value: "\(readings.count)", gradientNumeral: true)
            MetricTile(label: "NOMINAL", value: "\(withinLimit)/\(readings.count)", accent: Brand.success)
            MetricTile(label: "ALERTS", value: "\(alerts.count)", accent: alerts.isEmpty ? Brand.success : Brand.danger)
        }
    }

    // MARK: Alerts section

    private var allClearCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("All tanks within safety envelope").font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.success)
                Text("No vapor-pressure, level, or leak alerts on this terminal").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.success.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TANK ALERTS · acknowledge required")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(alerts.count)")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
            }
            VStack(spacing: Space.s2) {
                ForEach(alerts) { a in alertRow(a) }
            }
        }
    }

    private func alertRow(_ a: TankAlert610) -> some View {
        let c = severityColor(a.severity)
        let done = ackedKeys.contains(a.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(c)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(titleize(a.type)).font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text(a.severity.uppercased())
                            .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(c)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(c.opacity(0.16)))
                    }
                    Text(a.message).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                Spacer()
            }
            HStack {
                Text("tank \(a.tankNumber) · \(productLabel(a.product))")
                    .font(.system(size: 10.5, weight: .semibold)).monospaced().foregroundStyle(palette.textTertiary)
                Spacer()
                Button {
                    ackNote = ""
                    ackTarget = AckTarget610(
                        id: a.id, title: titleize(a.type), subtitle: a.message,
                        terminalId: a.terminalId, tankNumber: String(a.tankNumber),
                        severity: a.severity, metric: a.type)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: done ? "checkmark.circle.fill" : "checkmark.shield.fill").font(.system(size: 10, weight: .heavy))
                        Text(done ? "Acknowledged" : "Acknowledge").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(done ? Brand.success : c)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill((done ? Brand.success : c).opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(done)
            }
        }
        .padding(Space.s3)
        .background(c.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(c.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Envelope section

    private var envelopeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CAR READINGS · SAFETY ENVELOPE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(readings.count) car\(readings.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(readings) { r in envelopeRow(r) }
            }
        }
    }

    private func envelopeRow(_ r: TankReading610) -> some View {
        let isPressure = r.mawpPsi > 0
        let value = isPressure ? r.pressurePsi : r.percentFull
        let redline = isPressure ? r.mawpPsi : 95.0
        let unit = isPressure ? "psi" : "%"
        let maxScale = isPressure ? (redline > 0 ? redline / 0.75 : max(value * 1.15, 1)) : 100.0
        let valueFrac = maxScale > 0 ? min(value / maxScale, 1.0) : 0
        let redlineFrac = maxScale > 0 ? min(redline / maxScale, 1.0) : 0.75
        let badge = statusBadge(r.status)
        let metricLabel = isPressure ? "Vapor pressure" : "Level / outage"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Space.s3) {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(badge.1.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: 16, weight: .semibold)).foregroundStyle(badge.1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(metricLabel) · \(r.tankId)")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(productLabel(r.product)) · \(hazmatContext(r.product))")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(badge.0)
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(badge.1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(badge.1.opacity(0.14)))
                    Text("\(Int(value)) \(unit)")
                        .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
            }
            EnvelopeBar610(valueFrac: valueFrac, redlineFrac: redlineFrac, color: badge.1, palette: palette)
            HStack {
                Text("0 \(unit)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("redline \(Int(redline)) \(unit)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger.opacity(0.85))
            }
        }
        .padding(Space.s3)
        .background(r.status == "normal" ? palette.bgCard : badge.1.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(r.status == "normal" ? palette.borderFaint : badge.1.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Acknowledge sheet (confirm-gated)

    private func openReviewAck() {
        guard let h = heroReading else { return }
        let isP = h.mawpPsi > 0
        ackNote = ""
        ackTarget = AckTarget610(
            id: "tank_review:\(h.tankId)",
            title: "Tank status review · \(h.tankId)",
            subtitle: isP
                ? "\(productLabel(h.product)) · \(Int(h.pressurePsi)) psi vs redline \(Int(h.mawpPsi))"
                : "\(productLabel(h.product)) · \(Int(h.percentFull))% level",
            terminalId: h.terminalId,
            tankNumber: String(h.tankNumber),
            severity: statusSeverity(h.status),
            metric: isP ? "vapor_pressure" : "level")
    }

    private func ackSheet(_ target: AckTarget610) -> some View {
        let c = severityColor(target.severity)
        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ACKNOWLEDGE · HAZMAT SIGN-OFF").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(target.title)
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text(target.subtitle)
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            HStack(spacing: Space.s2) {
                if let sev = target.severity {
                    Text(sev.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(c)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(c.opacity(0.16)))
                }
                if let tn = target.tankNumber {
                    Text("TANK \(tn)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(palette.textTertiary.opacity(0.12)))
                }
                if let m = target.metric {
                    Text(m.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(palette.textTertiary.opacity(0.12)))
                }
            }

            Text("Confirming records an immutable acknowledgment (tank_acks + blockchain audit) that you have reviewed this reading against its safety redline.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("NOTE (optional)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                TextField("e.g. ambient tracked, holding nominal to Tulsa", text: $ackNote, axis: .vertical)
                    .font(.system(size: 14, weight: .regular)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2...4)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            Button {
                Task { await confirmAck(target) }
            } label: {
                HStack {
                    Spacer()
                    if ackSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm acknowledgment").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(ackSubmitting)

            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: Trend & forecast sheet

    private var trendSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("TREND & FORECAST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(heroReading.map { "\(productLabel($0.product)) · \($0.tankId)" } ?? "Tank telemetry")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)

            if trendLoading {
                LifecycleCard { Text("Loading telemetry…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("HISTORICAL TREND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    if trend.isEmpty {
                        LifecycleCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No historical trend yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
                                Text("Awaiting SCADA / ATG telemetry for this tank.").font(EType.caption).foregroundStyle(palette.textTertiary)
                            }
                        }
                    } else {
                        VStack(spacing: Space.s2) {
                            ForEach(trend.prefix(8)) { p in
                                HStack {
                                    Text(p.timestamp).font(.system(size: 11, weight: .semibold)).monospaced().foregroundStyle(palette.textSecondary).lineLimit(1)
                                    Spacer()
                                    Text("\(Int(p.percentFull))% · \(Int(p.temperatureF))°F")
                                        .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                                }
                                .padding(Space.s2)
                                .background(palette.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("DEMAND FORECAST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    if forecasts.isEmpty || forecasts.allSatisfy({ $0.confidence == 0 }) {
                        LifecycleCard { Text("Forecast pending real consumption history.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        VStack(spacing: Space.s2) {
                            ForEach(forecasts) { f in
                                HStack {
                                    Text(productLabel(f.product)).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    Text("reorder \(Int(f.daysUntilReorder))d · empty \(Int(f.daysUntilEmpty))d")
                                        .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(palette.textSecondary)
                                }
                                .padding(Space.s2)
                                .background(palette.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task { await loadTrend() }
    }

    // MARK: Toast

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        struct ReadingsInput: Encodable { let terminalId: Int }
        struct AlertsInput: Encodable { let terminalId: Int; let severityFilter: String }
        do {
            let resp: TankReadingsResponse610 = try await EusoTripAPI.shared.query(
                "tankMonitor.getTankReadings", input: ReadingsInput(terminalId: terminalId))
            self.readings = resp.readings
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let a: [TankAlert610] = try await EusoTripAPI.shared.query(
                "tankMonitor.getTankAlerts", input: AlertsInput(terminalId: terminalId, severityFilter: "all"))
            self.alerts = a
        } catch {
            self.alerts = []
        }
        loading = false
    }

    private func confirmAck(_ target: AckTarget610) async {
        struct AckInput: Encodable {
            let confirm: Bool
            let terminalId: Int
            let alertKey: String
            let tankNumber: String?
            let severity: String?
            let metric: String?
            let note: String?
        }
        ackSubmitting = true
        do {
            let _: AckResult610 = try await EusoTripAPI.shared.mutation(
                "tankMonitor.acknowledgeTankAlert",
                input: AckInput(
                    confirm: true, terminalId: target.terminalId, alertKey: target.id,
                    tankNumber: target.tankNumber, severity: target.severity, metric: target.metric,
                    note: ackNote.isEmpty ? nil : ackNote))
            ackedKeys.insert(target.id)
            ackTarget = nil
            showToast("Acknowledged · \(target.title)")
            await load()
        } catch {
            showToast((error as? EusoTripAPIError)?.errorDescription ?? "Acknowledge failed")
        }
        ackSubmitting = false
    }

    private func loadTrend() async {
        guard let hero = heroReading else { return }
        struct TrendInput: Encodable { let terminalId: Int; let tankNumber: Int; let hours: Int }
        struct FcInput: Encodable { let terminalId: Int }
        trendLoading = true
        do {
            let resp: TrendResponse610? = try await EusoTripAPI.shared.query(
                "tankMonitor.getTankTrend", input: TrendInput(terminalId: terminalId, tankNumber: hero.tankNumber, hours: 24))
            self.trend = resp?.trend ?? []
        } catch {
            self.trend = []
        }
        do {
            let fc: [Forecast610] = try await EusoTripAPI.shared.query(
                "tankMonitor.getTankForecasts", input: FcInput(terminalId: terminalId))
            self.forecasts = fc
        } catch {
            self.forecasts = []
        }
        trendLoading = false
    }
}

// MARK: - Vapor-pressure dial (semicircular instrument)
//
// A top-semicircle gauge with a green nominal arc [0 … redline] and a red redline
// arc [redline … full]. The gradient needle sweeps from empty up to the live
// value's position (value / maxScale, where the redline sits at 75% of the sweep,
// reproducing the wireframe's proportions for any MAWP). The needle winds up on
// appear with a decelerating settle spring; Reduce Motion snaps straight to final.
// Honest: a zero redline collapses the red zone and the dial scales to the value.
private struct PressureDial610: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    let redline: Double
    let unit: String
    let color: Color
    let palette: Theme.Palette

    @State private var shown: Double = 0   // animated value fraction along the sweep

    private var maxScale: Double { redline > 0 ? redline / 0.75 : max(value * 1.15, 1) }
    private var nominalFrac: Double { redline > 0 ? 0.75 : 1.0 }
    private var valueFrac: Double { maxScale > 0 ? min(value / maxScale, 1.0) : 0 }

    // Point on the top semicircle at sweep fraction f (0 = left, 0.5 = top, 1 = right).
    private func pointAt(_ f: Double, rect: CGRect, radius: CGFloat) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.maxY - 8)
        let theta = Double.pi * (1 - f)
        return CGPoint(x: center.x + CGFloat(cos(theta)) * radius,
                       y: center.y - CGFloat(sin(theta)) * radius)
    }

    private func arcPath(rect: CGRect, radius: CGFloat, from f0: Double, to f1: Double) -> Path {
        var p = Path()
        let steps = 48
        for i in 0...steps {
            let f = f0 + (f1 - f0) * Double(i) / Double(steps)
            let pt = pointAt(f, rect: rect, radius: radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let radius = min(rect.width / 2 - 14, rect.height - 20)
            let center = CGPoint(x: rect.midX, y: rect.maxY - 8)
            ZStack {
                arcPath(rect: rect, radius: radius, from: 0, to: nominalFrac)
                    .stroke(Brand.success, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                if nominalFrac < 1 {
                    arcPath(rect: rect, radius: radius, from: nominalFrac, to: 1.0)
                        .stroke(Brand.danger, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
                Path { p in
                    p.move(to: center)
                    p.addLine(to: pointAt(shown, rect: rect, radius: radius - 6))
                }
                .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                Circle().fill(LinearGradient.diagonal).frame(width: 13, height: 13).position(center)
                VStack(spacing: 1) {
                    Text("\(Int(value))")
                        .font(.system(size: 30, weight: .heavy)).monospacedDigit().foregroundStyle(color)
                    Text("\(unit) · redline \(Int(redline))")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
                .position(x: center.x, y: center.y - 30)
            }
            .onAppear { settle() }
            .onChange(of: value) { _, _ in settle() }
        }
    }

    private func settle() {
        if reduceMotion { shown = valueFrac }
        else { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = valueFrac } }
    }
}

// MARK: - Safety-envelope bullet bar (reading plotted vs its redline)
//
// A track with a translucent red redline zone from redlineFrac → 1.0 and a marker
// dot that settles to the reading's valueFrac. The marker takes the reading's
// status color so a car nearing its redline reads hot at a glance. Reduce Motion
// snaps straight to final.
private struct EnvelopeBar610: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let valueFrac: Double
    let redlineFrac: Double
    let color: Color
    let palette: Theme.Palette
    @State private var shown: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.10)).frame(height: 6)
                Capsule().fill(Brand.danger.opacity(0.30))
                    .frame(width: max(2, w * CGFloat(1 - redlineFrac)), height: 6)
                    .offset(x: w * CGFloat(redlineFrac))
                Capsule().fill(color).frame(width: max(4, w * shown), height: 6)
                Circle().fill(color).frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(palette.bgCard, lineWidth: 2))
                    .offset(x: max(0, w * shown - 5.5))
            }
        }
        .frame(height: 12)
        .onAppear { animate() }
        .onChange(of: valueFrac) { _, _ in animate() }
    }

    private func animate() {
        if reduceMotion { shown = CGFloat(valueFrac) }
        else { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = CGFloat(valueFrac) } }
    }
}

#Preview("610 · Rail Tank Car Monitor · Night") { RailTankCarMonitorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("610 · Rail Tank Car Monitor · Light") { RailTankCarMonitorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
