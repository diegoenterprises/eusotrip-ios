//
//  388_CatalystTankerFleetMonitor.swift
//  EusoTrip — Catalyst · Tanker Fleet Monitor (carrier multi-asset vantage).
//
//  Verbatim iOS port of `03 Catalyst/Dark-SVG/388 Catalyst Tanker Fleet
//  Monitor.svg` + `Code/388_CatalystTankerFleetMonitor.swift`.
//
//  Carrier (fleet) vantage of the real tankMonitor router — the same
//  bulk/cargo-tank telemetry the Driver tanker monitor reads from the
//  personal vantage (the §462-named carrier-parity gap).
//
//  Server wiring — LIVE: this surface reads the real tank-monitoring router
//  via `EusoTripAPI.shared.tankMonitor.*`
//  (`frontend/server/routers/tankMonitor.ts`, projection
//  `services/TankLevelMonitor.ts`):
//    • getMultiTerminalOverview({ terminalIds? }) → fleet roll-up; its first
//      active terminal resolves the terminalId scope for the per-tank read.
//    • getTankReadings({ terminalId })            → per-tank latest readings
//      (level / percentFull / temperatureF / pressurePsi / mawpPsi / status)
//      + the terminal summary. Each reading is the latest persisted
//      tank_readings row, or an honest OFFLINE reading (zeros, status
//      "offline") until a real gauge row is ingested.
//    • getTankAlerts({ terminalId?, severityFilter }) → live tank alert feed.
//
//  There is NO fabricated telemetry. `state` starts at `.loading`; `data` is
//  empty until `loadAll()` returns, flips to `.ready` only when at least one
//  real reading exists, else `.empty`. Every gauge figure (pressure, MAWP,
//  level, temp, the pressure-within-MAWP fraction) is bound from the live
//  readings; when a field is nil/offline it renders an honest "—" rather than
//  a fabricated value. `pressurePsi`/`mawpPsi` are decoded OPTIONAL so the
//  surface is correct whether or not the paired server change has shipped.
//
//  Persona: carrier Eusotrans LLC · USDOT 3 194 882.
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

// MARK: - Typed telemetry model

private enum TankLoadState_388 { case loading, ready, empty }

/// One per-tank ledger row in the multi-asset card — built entirely from a
/// live `TankMonitorAPI.TankReading`. The badge carries the pressure (psi)
/// when a real pressure reading exists, else the tank status string; never a
/// fabricated psi/level.
private struct TankRow_388: Identifiable {
    enum BadgeKind_388 { case positive, neutral }
    let id = UUID()
    let title: String   // "TNK-0N · <product>" from a live reading
    let detail: String  // only the fields that carry a real value (pct/temp/MAWP)
    let badge: String   // "<psi> psi" | status band | "OFFLINE" — never invented
    let badgeKind: BadgeKind_388
}

/// One factor tile (TANKS · NOMINAL · ALERTS).
private struct FactorCell_388: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let sub: String
}

/// The whole-surface telemetry envelope — built entirely from the live
/// tankMonitor.* projections. Never seeded with fabricated readings. The
/// `.ready` branch (the ONLY place these render) is reached solely after
/// `loadAll()` populates a real envelope from at least one reading, so the
/// empty defaults never paint on screen.
private struct TankTelemetry_388 {
    let heroBig: String        // "<psi> psi" | "—"  (active tank pressure)
    let heroBigUnit: String    // "MAWP <psi>" | "MAWP —"
    let heroRight: String      // status band, e.g. "NOMINAL" | "LOW" | "OFFLINE"
    let heroRightOK: Bool      // tints the status band success vs neutral/danger
    let heroFraction: Double   // pressurePsi ÷ mawpPsi, clamped [0,1]; 0 when unknown
    let heroHasPressure: Bool  // a real pressure reading backs the hero
    let cardHeaderR: String    // "N TANKS"
    let rows: [TankRow_388]
    let cells: [FactorCell_388]
    let activeLine1: String    // active-load / terminal context (real or neutral)
    let activeLine2: String
    let footnote: String

    static let empty = TankTelemetry_388(
        heroBig: "—", heroBigUnit: "MAWP —", heroRight: "—", heroRightOK: true,
        heroFraction: 0, heroHasPressure: false, cardHeaderR: "0 TANKS",
        rows: [], cells: [], activeLine1: "", activeLine2: "", footnote: ""
    )
}

// MARK: - Body

private struct TankerFleetBody_388: View {
    @Environment(\.palette) private var palette

    @State private var state: TankLoadState_388 = .loading
    @State private var data: TankTelemetry_388 = .empty

    /// Relative "synced …" label off the freshest live reading's
    /// `lastGaugedAt`. Empty until a real reading lands (no fabricated time).
    @State private var syncedLabel: String = ""

    // ── Static identity / copy (verbatim from Code spec + SVG) ──
    private let eyebrow      = "CATALYST · TANKER FLEET"
    private let eyebrowR     = "MC-331"
    private let title        = "Tanker Fleet"
    private let subtitle     = "pressure · cargo tanks"
    private let carrierR     = "EUSOTRANS LLC · USDOT 3 194 882"

    private let heroLabelL   = "TANK PRESSURE · ACTIVE"
    private let heroLabelR   = "STATUS"

    private let cardHeaderL  = "TANKER FLEET · MULTI-ASSET"
    private let loadLabel    = "HAZMAT · ACTIVE LOAD"

    private let primaryCTA   = "Pressure trend"
    private let secondaryCTA = "Forecast"

    private let fineprint: [String] = [
        "Tank telemetry · pressure/vapor per asset · MC-331 cargo-tank limits",
        "Carrier: Eusotrans LLC · USDOT 3 194 882 · live tank telemetry feed",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar_388
                titleBlock_388
                IridescentHairline()

                switch state {
                case .loading:
                    skeletonBody_388
                case .empty:
                    emptyBody_388
                case .ready:
                    heroCard_388
                    multiAssetCard_388
                    HStack(spacing: Space.s2) {
                        ForEach(data.cells) { cell in
                            factorTile_388(cell)
                        }
                    }
                    HStack(spacing: Space.s2) {
                        CTAButton(title: primaryCTA, action: {})
                        secondaryButton_388(secondaryCTA)
                    }
                    provenanceFootnote_388
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
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
                Text(syncedLabel.isEmpty ? "—" : syncedLabel)
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
                Text(data.heroBig)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(data.heroBigUnit)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(data.heroRight)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(data.heroRightOK ? Brand.success : palette.textSecondary)
            }
            .padding(.top, 12)

            // Gauge bar — pressure fraction within MAWP envelope. When no real
            // pressure backs the hero, the fill collapses to 0 (faint track
            // only) rather than painting a fabricated position.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.textPrimary.opacity(0.08))
                        .frame(height: 6)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * data.heroFraction), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, 14)

            Text(data.heroHasPressure
                 ? "Pressure + vapor within MC-331 nominal envelope"
                 : "No live tank-pressure reading on the active asset")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
            Text(data.heroHasPressure
                 ? "Live tankMonitor.* feed · pressure within MAWP limit"
                 : "Awaiting a gauge reading from the cargo-tank monitor")
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
                Text(data.cardHeaderR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(data.rows.enumerated()), id: \.element.id) { idx, row in
                    tankRow_388(row)
                    if idx < data.rows.count - 1 {
                        Rectangle()
                            .fill(palette.textPrimary.opacity(0.07))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.top, 16)

            // Active hazmat / terminal context block — populated from the
            // resolved terminal + active load context, neutral when none.
            VStack(alignment: .leading, spacing: 4) {
                Text(loadLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(data.activeLine1)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(data.activeLine2)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 16)

            Text(data.footnote)
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

    private func tankBadge_388(_ text: String, kind: TankRow_388.BadgeKind_388) -> some View {
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
            if !data.footnote.isEmpty {
                Text(data.footnote)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Loading / empty

    private var skeletonBody_388: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 150)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 220)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard).frame(height: 72)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyBody_388: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(palette.textPrimary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No live tank telemetry")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("No cargo-tank readings on the active terminal · check the gauge/SCADA monitoring link")
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

    // MARK: - Network (tankMonitor.* — no fabricated readings)

    @MainActor
    private func loadAll() async {
        let api = EusoTripAPI.shared

        // 1) Resolve the terminal scope from the company-scoped overview. Its
        //    first active terminal is the terminalId we read per-tank from.
        var overview: TankMonitorAPI.OverviewEnvelope? = nil
        do {
            overview = try await api.tankMonitor.getMultiTerminalOverview()
        } catch {
            state = .empty
            return
        }
        guard let terminalId = overview?.terminals.first?.terminalId else {
            data = .empty
            state = .empty
            return
        }

        // 2) Per-tank readings + the terminal summary for that terminal.
        var env: TankMonitorAPI.ReadingsEnvelope
        do {
            env = try await api.tankMonitor.getTankReadings(terminalId: terminalId)
        } catch {
            state = .empty
            return
        }

        // No live readings → honest empty state, no fabricated rows.
        guard !env.readings.isEmpty else {
            data = .empty
            state = .empty
            return
        }

        // 3) Live alerts for this terminal (best-effort; [] tolerated).
        let alerts = (try? await api.tankMonitor.getTankAlerts(terminalId: terminalId)) ?? []

        let readings = env.readings
        let summary = env.summary ?? overview?.terminals.first
        let terminalName = summary?.terminalName ?? readings.first?.terminalName ?? "Terminal #\(terminalId)"

        // ── Hero: the "active" tank is the first reading carrying a real
        //    pressure value; else the first reading overall. Pressure / MAWP
        //    are OPTIONAL — render "—" when nil, and only compute the
        //    fraction when BOTH are present and MAWP > 0. ──
        let active = readings.first(where: { ($0.pressurePsi ?? 0) > 0 }) ?? readings[0]
        let pressure = active.pressurePsi
        let mawp = active.mawpPsi
        let hasPressure = (pressure ?? 0) > 0

        let heroBig = hasPressure ? "\(intStr(pressure!)) psi" : "—"
        let heroBigUnit = (mawp ?? 0) > 0 ? "MAWP \(intStr(mawp!))" : "MAWP —"
        let fraction: Double = {
            guard let p = pressure, let m = mawp, m > 0 else { return 0 }
            return min(1.0, max(0.0, p / m))
        }()
        let heroStatusBand = statusBand(active.status)

        // ── Per-tank ledger rows from the real readings (capped to the SVG's
        //    3-row chrome to preserve layout). Every datum is real or "—". ──
        let rows: [TankRow_388] = readings.prefix(3).map { r in
            let badge: String
            let kind: TankRow_388.BadgeKind_388
            if let p = r.pressurePsi, p > 0 {
                badge = "\(intStr(p)) psi"
                kind = isNominal(r.status) ? .positive : .neutral
            } else {
                badge = statusBand(r.status)
                kind = isNominal(r.status) ? .positive : .neutral
            }
            return TankRow_388(
                title: "TNK-\(String(format: "%02d", r.tankNumber)) · \(productLabel(r.product))",
                detail: rowDetail(r),
                badge: badge,
                badgeKind: kind
            )
        }

        // ── Factor tiles from the summary + alert feed. ──
        let totalTanks = summary?.totalTanks ?? readings.count
        let nominalCount = readings.filter { isNominal($0.status) }.count
        let activeAlerts = alerts.count
        let cells: [FactorCell_388] = [
            .init(label: "TANKS",   value: "\(totalTanks)",   sub: "monitored"),
            .init(label: "NOMINAL", value: "\(nominalCount)", sub: "of \(readings.count)"),
            .init(label: "ALERTS",  value: "\(activeAlerts)", sub: "active"),
        ]

        // ── Active-load / terminal context — neutral, derived, never the old
        //    fabricated LD-260427 / NH₃ specifics. ──
        let util = summary?.overallUtilization
        let line1 = util != nil
            ? "\(terminalName) · \(util!)% utilized · \(readings.count) cargo tanks"
            : "\(terminalName) · \(readings.count) cargo tanks"
        let line2 = "Carrier-monitored cargo-tank telemetry · MC-331 limits"
        let footnote = "Terminal #\(terminalId) · live tank telemetry feed · \(readings.count) tanks"

        data = TankTelemetry_388(
            heroBig: heroBig,
            heroBigUnit: heroBigUnit,
            heroRight: heroStatusBand,
            heroRightOK: isNominal(active.status),
            heroFraction: fraction,
            heroHasPressure: hasPressure,
            cardHeaderR: "\(readings.count) TANK\(readings.count == 1 ? "" : "S")",
            rows: rows,
            cells: cells,
            activeLine1: line1,
            activeLine2: line2,
            footnote: footnote
        )

        // "synced …" off the freshest live reading — never a fixed literal.
        let freshest = readings.compactMap(\.lastGaugedAt).filter { !$0.isEmpty }.max() ?? ""
        syncedLabel = relativeSynced(freshest)

        state = .ready
    }

    // MARK: - Helpers (formatting — all over REAL values; nil → "—")

    /// Integer string from an optional gauge value (already unwrapped > 0 by
    /// callers). Rounds to nearest whole psi for the hero/badge display.
    private func intStr(_ v: Double) -> String { String(Int(v.rounded())) }

    /// Product label — title-cases the server product slug
    /// ("jet_fuel" → "Jet Fuel"), falls back to the raw value.
    private func productLabel(_ raw: String) -> String {
        guard !raw.isEmpty else { return "tank" }
        return raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The status-band display string for the hero/badge — uppercased,
    /// honest "OFFLINE"/"—" when the tank is offline / status missing.
    private func statusBand(_ status: String) -> String {
        let s = status.lowercased()
        if s.isEmpty { return "—" }
        switch s {
        case "normal":          return "NOMINAL"
        case "offline":         return "OFFLINE"
        case "critical_low":    return "CRIT LOW"
        case "overfill_risk":   return "OVERFILL"
        case "leak_suspected":  return "LEAK?"
        default:                return status.uppercased()
        }
    }

    /// A tank is "nominal" only when the server says `normal` — every other
    /// status (low/high/offline/leak/…) is non-nominal and tinted neutral.
    private func isNominal(_ status: String) -> Bool { status.lowercased() == "normal" }

    /// Compact per-tank detail line built only from fields that carry a real
    /// value; nil fields are simply omitted (never shown as a fabricated 0).
    private func rowDetail(_ r: TankMonitorAPI.TankReading) -> String {
        var parts: [String] = []
        if let pct = r.percentFull, pct > 0 {
            parts.append("\(intStr(pct))% full")
        }
        if let t = r.temperatureF, t != 0 {
            parts.append("\(intStr(t))°F")
        }
        if let m = r.mawpPsi, m > 0 {
            parts.append("MAWP \(intStr(m))")
        }
        if parts.isEmpty {
            // No real measurement on this tank — surface the honest status.
            return statusBand(r.status).lowercased()
        }
        return parts.joined(separator: " · ")
    }

    /// "synced HH:mm" / "synced Nm ago" from a reading's ISO lastGaugedAt.
    /// Empty when unparseable so the title falls back to a neutral dash.
    private func relativeSynced(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let mins = Int(max(0, Date().timeIntervalSince(date) / 60))
        if mins < 1 { return "synced just now" }
        if mins < 60 { return "synced \(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "synced \(hrs)h ago" }
        return "synced \(hrs / 24)d ago"
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
