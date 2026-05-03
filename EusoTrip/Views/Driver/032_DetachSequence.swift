//
//  032_DetachSequence.swift
//  EusoTrip — Lifecycle screen 032 · Detach Sequence.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `032 Detach Sequence.png`. Fill is locked, Spectra-Match certified;
//  now ESANG leads the 6-step detach choreography — close liquid,
//  close vapor, purge hose with N2, disconnect, remove grounding,
//  sign BOL + Spectra cert.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DetachSequence: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false
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
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass).
    // Live values come from `tankMonitor.getDetachSnapshot` once the
    // bay-ops sensor stack ships — until then, em-dashes only.
    private let fallbackClock  = "—"
    private let fallbackLoadID = "—"
    private let fallbackHosePressure = "—"
    private let fallbackN2Flow       = "—"
    private let fallbackVaporTemp    = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                esangStepLead
                sequenceList
                certStrip
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
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("FILL LOCKED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· DETACH SEQUENCE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("NH3 detach in progress")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Step 3 of 6 · ~4 min remaining · rig still grounded")
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

    private var esangStepLead: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
                Text("ESANG · step lead")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("STEP 3 / 6")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("HAZMAT SAFETY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            Divider().overlay(palette.borderFaint)

            Text("Purge hose with N2")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)

            Text("Both bay valves are shut. ESANG is sweeping the loading hose with nitrogen — pulling residual NH3 back into the bay vapor return so the line is safe to break. Hold position. Do not touch the couplers yet.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s2) {
                miniMetric(label: "HOSE PRESSURE", value: fallbackHosePressure, unit: "psig")
                miniMetric(label: "N2 FLOW", value: fallbackN2Flow, unit: "scfm")
                miniMetric(label: "VAPOR TEMP", value: fallbackVaporTemp, unit: "C")
            }

            // Quote bubble
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hose is at \(fallbackHosePressure) psig and falling fast — almost zero. About 30 seconds. When I call clear, you crack the liquid coupler first, then the vapor return.")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                    Text("VIA ESANG · HAZMAT SAFETY")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s2)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func miniMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var sequenceList: some View {
        VStack(spacing: 4) {
            seqRow(title: "Close liquid valve at bay", timestamp: "18:29", state: .done)
            seqRow(title: "Close vapor return valve",   timestamp: "18:30", state: .done)
            seqRow(title: "Purge hose with N2",         timestamp: "NOW",   state: .now)
            seqRow(title: "Disconnect liquid + vapor hoses", timestamp: "STEP 4", state: .next)
            seqRow(title: "Remove grounding strap",     timestamp: "STEP 5", state: .next)
            seqRow(title: "Sign BOL + Spectra cert",    timestamp: "STEP 6", state: .next)
        }
    }

    private enum SeqState { case done, now, next }

    private func seqRow(title: String, timestamp: String, state: SeqState) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Brand.success.opacity(0.2))
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.success)
                case .now:
                    Circle().fill(LinearGradient.diagonal.opacity(0.2))
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 1.5).frame(width: 12, height: 12)
                case .next:
                    Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
                }
            }
            .frame(width: 20, height: 20)
            Text(title)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(state == .next ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Text(timestamp)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(state == .now ? Brand.warning : palette.textTertiary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var certStrip: some View {
        // 140th firing M3 retrofit — per-load Spectra-Match identifiers
        // (sample id + purity readout) now read off
        // `LifecycleProductContext.facets`. Both are backend-stub gaps
        // today (only `LoadDetail.spectraMatchVerified` ships). Each
        // facet collapses to em-dash until the column lands on
        // `loads.getById`; the chip drops the missing segment from its
        // string instead of voicing fabricated lab data.
        HStack(spacing: Space.s2) {
            certChip(
                label: "BOL \(activeLoad?.loadNumber ?? fallbackLoadID)",
                sub: "PRE-FILLED · AWAITS DRIVER"
            )
            certChip(
                label: spectraCertLabel,
                sub: spectraCertSub
            )
        }
    }

    /// Spectra-Match cert chip label — appends the live sample id when
    /// the backend ships one, otherwise just "Spectra cert".
    private var spectraCertLabel: String {
        let id = ctx.facets.spectraMatchSampleId
        return id == LiveLoadFacets.dash
            ? "Spectra cert"
            : "Spectra cert \(id)"
    }

    /// Spectra-Match cert chip sub-line — prepends the live purity
    /// readout (e.g. "99.94% NH3") when the backend ships one;
    /// otherwise the lineage stamp stands alone.
    private var spectraCertSub: String {
        let purity = ctx.facets.spectraMatchPurity
        return purity == LiveLoadFacets.dash
            ? "SIGNED BY ESANG AI LINEAGE"
            : "\(purity) · SIGNED BY ESANG AI LINEAGE"
    }

    private func certChip(label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await togglePauseDetach() } } label: {
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
            .accessibilityLabel(isPaused ? "Resume detach sequence" : "Pause detach sequence")
            CTAButton(
                title: "Confirm purge complete",
                action: { Task { await confirmPurge() } },
                trailingIcon: "arrow.right",
                isLoading: isConfirming
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmPurge() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["signoff", "bol", "departing", "in_transit"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    /// Pause / resume the detach sequence — same pattern as
    /// `030_LoadingInProgress.togglePauseLoading`. Records a
    /// timestamped note on the appointment record so the dispatcher
    /// + shipper see why the rig is sitting on the dock past the
    /// usual purge window.
    private func togglePauseDetach() async {
        guard !pauseInflight else { return }
        pauseInflight = true
        defer { pauseInflight = false }
        let willPause = !isPaused
        let stamp = ISO8601DateFormatter().string(from: Date())
        let note = willPause
            ? "Driver paused detach at \(stamp)"
            : "Driver resumed detach at \(stamp)"
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
            pauseToast = willPause ? "Detach paused" : "Detach resumed"
        } catch {
            pauseToast = "Couldn't update appointment"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        pauseToast = nil
    }
}

struct DetachSequenceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DetachSequence(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_032(),
                      trailing: driverNavTrailing_032(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_032() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_032() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("032 · Detach Sequence · Dark") {
    DetachSequenceScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("032 · Detach Sequence · Light") {
    DetachSequenceScreen(theme: Theme.light).preferredColorScheme(.light)
}
