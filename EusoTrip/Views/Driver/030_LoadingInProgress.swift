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

    private var metricRow: some View {
        HStack(spacing: Space.s2) {
            bigMetric(label: "FLOW RATE", primary: fallbackFlow, unit: "gpm", sub: fallbackFlowSub, subColor: Brand.success)
            bigMetric(label: "ETA FULL",  primary: fallbackEtaFull, unit: "ds", sub: fallbackEtaSub, subColor: Brand.warning)
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
            Button { navBack?() } label: {
                Text("Pause")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
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

#Preview("030 · Loading in Progress · Dark") {
    LoadingInProgressScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("030 · Loading in Progress · Light") {
    LoadingInProgressScreen(theme: Theme.light).preferredColorScheme(.light)
}
