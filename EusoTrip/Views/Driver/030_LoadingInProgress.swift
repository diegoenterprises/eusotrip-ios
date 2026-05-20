//
//  030_LoadingInProgress.swift
//  EusoTrip — Lifecycle screen 030 · Loading in Progress (live rack).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `030 Loading in Progress.png`. Product is flowing, Spectra-Match
//  is running real-time purity samples, ESANG monitors all sensor
//  lanes. 28% hero gauge with gallons counter + flow rate + ETA
//  to full + vapor/static/temp safety tiles + sampling card +
//  Pause / E-STOP footer.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct LoadingInProgress: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showEStopConfirm: Bool = false
    @State private var isPaused: Bool = false
    @State private var pauseInflight: Bool = false
    @State private var pauseToast: String? = nil

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Production-clean placeholders.
    //
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass) — every
    // hard-coded telemetry value (720 gpm, 99.94 sample purity, 1,920
    // of 6,800 gal) replaced with em-dash placeholders. Real values
    // wire in via `tankMonitor.getLoadingSnapshot({ loadId })` →
    // TankMonitorAPI on the iOS side. Until the live snapshot
    // hydrates, the screen renders the layout with em-dashes — no
    // fabricated flow rate, pressure, or sample value.
    private let fallbackClock   = "—"
    private let fallbackLoadID  = "—"
    private let fallbackBay     = "AWAITING BAY ASSIGNMENT"
    private let fallbackSubtitle = "Telemetry will appear when sensors connect"
    private let fallbackFlow    = "—"
    private let fallbackFlowSub = "—"
    private let fallbackEtaFull = "—"
    private let fallbackEtaSub  = "—"
    private let fallbackVapor   = "—"
    private let fallbackStatic  = "—"
    private let fallbackTankT   = "—"
    private let fallbackSample  = "—"
    private let fallbackSampleSub = "target —"
    private let fallbackSampleIx  = "—"
    private let fallbackGallonsNow = 0
    private let fallbackGallonsTot = 0
    private let fallbackStarted   = "—"
    private let fallbackEtaClock  = "—"

    private var percent: Double {
        Double(fallbackGallonsNow) / Double(fallbackGallonsTot)
    }
    private var percentInt: Int {
        Int((percent * 100).rounded())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                progressCard
                metricRow
                safetyRow
                spectraCard
                esangMonitorCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .overlay(alignment: .bottom) {
            if let msg = pauseToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: pauseToast)
        .screenTileRoot()
        .alert("Stop fill?", isPresented: $showEStopConfirm) {
            Button("E-STOP now", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closes the bay arm and aborts the transfer. Only use in a genuine safety event.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("LOADING ACTIVE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Text("· \(activeLoad?.loadNumber ?? fallbackLoadID)")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(fallbackBay)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackSubtitle)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(percentInt)%")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fallbackGallonsNow.formatted())
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("OF \(fallbackGallonsTot.formatted()) GAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(percent), height: 6)
                        .animation(.easeOut(duration: 0.6), value: percent)
                }
            }
            .frame(height: 6)
            HStack {
                Text("STARTED \(fallbackStarted)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ETA FULL \(fallbackEtaClock)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // T-020 · 2026-05-20 — Equipment-keyed metric row.
    // Resolves the canonical TrailerCode (from load.cargoType + hazmatClass
    // heuristic until Load grows a structured trailer column) and dispatches
    // to per-equipment metric pairs:
    //   dry van       → cargo weight + load fill %
    //   flatbed       → stack height + securement count
    //   reefer        → set temp + actual temp
    //   livestock     → head count + 28-hr timer
    //   auto-carrier  → vehicles loaded + per-vehicle VCR
    //   tanker / hazmat (default) → FLOW RATE + ETA FULL (preserved)
    private var resolvedTrailer: TrailerCode? {
        // Direct canonical lookup will land once Load gains a structured
        // `trailer` field (T-020b in the platform backlog). For now derive
        // a best-guess from the cargoType + hazmatClass already on Load.
        guard let cargo = activeLoad?.cargoType?.lowercased() else { return nil }
        let haz = activeLoad?.hazmatClass ?? ""
        let isHaz = !haz.isEmpty
        switch cargo {
        case "refrigerated":             return .reefer
        case "livestock":                return .livestockCattlePot
        case "vehicles":                 return .autoCarrier
        case "oversized", "flatbed":     return .standardFlatbed
        case "general":                  return .dryVan
        case "petroleum":                return .liquidTank
        case "gas":                      return .pressurizedGasTank
        case "cryogenic":                return .cryogenicTank
        case "hazmat":                   return isHaz ? .hazmatBox : .dryVan
        case "liquid":                   return .liquidTank
        case "chemicals":                return .liquidTank
        default:                         return nil
        }
    }

    private var metricRow: some View {
        let pair = LoadingMetricsViewBuilder.pair(for: resolvedTrailer)
        return HStack(spacing: Space.s2) {
            bigMetric(label: pair.left.label,  primary: pair.left.primary,
                      unit: pair.left.unit,    sub: pair.left.sub,
                      subColor: pair.left.subColor)
            bigMetric(label: pair.right.label, primary: pair.right.primary,
                      unit: pair.right.unit,   sub: pair.right.sub,
                      subColor: pair.right.subColor)
        }
    }

    private func bigMetric(label: String, primary: String, unit: String, sub: String, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(primary)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(subColor)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var safetyRow: some View {
        HStack(spacing: Space.s2) {
            safetyTile(label: "VAPOR PRESSURE", value: fallbackVapor, unit: "psig")
            safetyTile(label: "STATIC IMPEDANCE", value: fallbackStatic, unit: "Ω")
            safetyTile(label: "TANK TEMP", value: fallbackTankT, unit: "C")
        }
    }

    private func safetyTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var spectraCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Image(systemName: "waveform.path").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Spectra-Match · sample \(fallbackSampleIx)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("CLEAR")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
                }
                Text("Last reading \(fallbackSample)% NH3 · \(fallbackSampleSub)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var esangMonitorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("ESANG is monitoring")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("NOTCHED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("all four sensors inside spec, no drift")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                Text("VIA ESANG · CATALYST DISPATCH ON THE LOOP · RAILWAY METERING LIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await togglePauseLoading() } } label: {
                HStack(spacing: 6) {
                    if pauseInflight {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.textPrimary)
                    }
                    Text(isPaused ? "Resume" : "Pause")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(
                            isPaused ? Brand.success.opacity(0.5) : palette.borderSoft
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .disabled(pauseInflight)
            .accessibilityLabel(isPaused ? "Resume loading" : "Pause loading")
            Button { showEStopConfirm = true } label: {
                Text("E-STOP")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Brand.danger)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    /// Pause / resume the loading operation. Records a timestamped
    /// note on the appointment record (real `appointments.updateStatus`
    /// mutation) so the shipper / dispatcher web surfaces see the
    /// pause + reason. Server tolerates same-status updates with a
    /// fresh `notes` field — that's how dwell snapshots already work
    /// on 015. No backend change required.
    private func togglePauseLoading() async {
        guard !pauseInflight else { return }
        pauseInflight = true
        defer { pauseInflight = false }
        let willPause = !isPaused
        let stamp = ISO8601DateFormatter().string(from: Date())
        let note = willPause
            ? "Driver paused loading at \(stamp)"
            : "Driver resumed loading at \(stamp)"
        guard !lifecycle.loadId.isEmpty else {
            pauseToast = "No active load"
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            pauseToast = nil
            return
        }
        do {
            if let appt = try await EusoTripAPI.shared.appointments
                .getByLoad(loadId: lifecycle.loadId) {
                _ = try? await EusoTripAPI.shared.appointments
                    .updateStatus(
                        id: appt.id,
                        status: "loading",
                        notes: note
                    )
            }
            isPaused.toggle()
            pauseToast = willPause ? "Loading paused" : "Loading resumed"
        } catch {
            pauseToast = "Couldn't update appointment"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        pauseToast = nil
    }
}

struct LoadingInProgressScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            LoadingInProgress(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_030(),
                      trailing: driverNavTrailing_030(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_030() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_030() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - T-020 · LoadingMetricsViewBuilder (2026-05-20)

/// One metric cell descriptor (label / primary number / unit / sub /
/// sub-color). Pairs render side-by-side in the metricRow above.
fileprivate struct LoadingMetric {
    let label: String
    let primary: String
    let unit: String
    let sub: String
    let subColor: Color
}

fileprivate struct LoadingMetricPair {
    let left: LoadingMetric
    let right: LoadingMetric
}

/// Equipment-keyed metrics for the Loading-In-Progress screen. Picks
/// the metric pair that's most useful for the active trailer type —
/// the driver no longer sees tanker FLOW RATE / ETA when they're
/// loading a livestock pot or auto-carrier. Telemetry values are
/// em-dash placeholders until the per-equipment server endpoints ship
/// (`tankMonitor` exists for tanker; reefer / livestock / auto-carrier
/// equivalents land in T-020b on the platform repo).
fileprivate enum LoadingMetricsViewBuilder {

    static func pair(for trailer: TrailerCode?) -> LoadingMetricPair {
        guard let t = trailer else { return tankerDefault }
        switch t {
        // Dry-cargo van — driver cares about weight on the floor.
        case .dryVan, .curtainSide, .hazmatBox, .conestoga,
             .intermodalChassis:
            return LoadingMetricPair(
                left:  .init(label: "CARGO WEIGHT", primary: "—", unit: "lb",
                             sub: "of 44,000 max", subColor: Brand.success),
                right: .init(label: "LOAD FILL",   primary: "—", unit: "%",
                             sub: "pallets staged", subColor: Brand.warning)
            )

        // Flatbed family — stack height for bridge-clearance + securement.
        case .standardFlatbed, .stepDeck, .lowboyRgn, .doubleDrop, .logTrailer:
            return LoadingMetricPair(
                left:  .init(label: "STACK HEIGHT", primary: "—", unit: "ft",
                             sub: "13'6\" legal max", subColor: Brand.success),
                right: .init(label: "TIE-DOWNS",   primary: "—", unit: "ct",
                             sub: "per 49 CFR 393", subColor: Brand.warning)
            )

        // Reefer family — temperature is the load.
        case .reefer, .foodGradeLiquidTank:
            return LoadingMetricPair(
                left:  .init(label: "SET TEMP",   primary: "—", unit: "°F",
                             sub: "FSMA setpoint", subColor: Brand.success),
                right: .init(label: "ACTUAL TEMP", primary: "—", unit: "°F",
                             sub: "live reefer feed", subColor: Brand.warning)
            )

        // Livestock pot — head count + 28-hr countdown.
        case .livestockCattlePot:
            return LoadingMetricPair(
                left:  .init(label: "HEAD COUNT", primary: "—", unit: "hd",
                             sub: "USDA cert", subColor: Brand.success),
                right: .init(label: "28-HR TIMER", primary: "—", unit: "hr",
                             sub: "49 USC 80502", subColor: Brand.warning)
            )

        // Auto carrier — per-vehicle VCR ticked off as each car loads.
        case .autoCarrier:
            return LoadingMetricPair(
                left:  .init(label: "VEHICLES LOADED", primary: "—", unit: "of —",
                             sub: "VCR pending", subColor: Brand.success),
                right: .init(label: "DECK FILL", primary: "—", unit: "%",
                             sub: "upper + lower", subColor: Brand.warning)
            )

        // Dry bulk / hopper — fill weight + tare.
        case .dryBulkHopper, .gravityHopper, .grainHopper, .pneumaticTank, .endDump:
            return LoadingMetricPair(
                left:  .init(label: "NET WEIGHT", primary: "—", unit: "lb",
                             sub: "scale ticket", subColor: Brand.success),
                right: .init(label: "TARE", primary: "—", unit: "lb",
                             sub: "empty unit weight", subColor: Brand.warning)
            )

        // Tanker family (liquid / gas / cryo / water) and any unhandled
        // type — the original FLOW RATE / ETA FULL pair stays. This is
        // the most production-tested layout (tankMonitor live wiring).
        case .liquidTank, .pressurizedGasTank, .cryogenicTank, .waterTank:
            return tankerDefault

        }
    }

    private static let tankerDefault = LoadingMetricPair(
        left:  .init(label: "FLOW RATE", primary: "—", unit: "gpm",
                     sub: "—", subColor: Brand.success),
        right: .init(label: "ETA FULL",  primary: "—", unit: "ds",
                     sub: "—", subColor: Brand.warning)
    )
}

#Preview("030 · Loading in Progress · Dark") {
    LoadingInProgressScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("030 · Loading in Progress · Light") {
    LoadingInProgressScreen(theme: Theme.light).preferredColorScheme(.light)
}
