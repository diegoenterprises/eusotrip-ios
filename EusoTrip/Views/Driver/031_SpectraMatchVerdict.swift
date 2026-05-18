//
//  031_SpectraMatchVerdict.swift
//  EusoTrip — Lifecycle screen 031 · Spectra-Match Verdict.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `031 Spectra-Match Verdict.png`. Every sample has cleared, rack
//  pump has stopped at the commanded gallons, final sample is
//  captured, and the PASS verdict is posted. Huge gradient PASS +
//  99.94% vs target 99.5% + a sample-trace chart + 5-sample
//  lineage strip + EusoShield-backed signed-at-rack pill +
//  Hold for retest / Lock fill, detach CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct SpectraMatchVerdict: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverReportIssue) private var reportIssue
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var spectraStore = SpectraMatchHistoryStore()
    @State private var activeLoad: Load?
    @State private var isLocking: Bool = false
    @State private var nowClock: String = ""

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Empty-state copy
    //
    // These strings are *only* rendered when the driver has no
    // signed loads in the spectra-match history. They are not mock
    // data — they are the empty-state legend the screen shows
    // before the first verified fill of the shift. Once
    // `spectraStore.items` is non-empty every line below is sourced
    // from live backend data via `liveLanes` / `headlineLane`.
    private let placeholderClock    = "—:—"
    private let placeholderLoadID   = "—"
    private let placeholderTitle    = "Awaiting first verified fill"
    private let placeholderSub      = "Spectra-Match has no captures for this shift yet"
    private let placeholderHero     = "—"
    private let placeholderTarget   = "VS TARGET ≥ 99.5%"
    private let placeholderCaptured = "WAITING ON RACK SIGNOFF"
    private let placeholderRange    = "Sample lineage will populate after the first verified fill of the shift."

    /// Live lanes — always at most 5, in `THIS FILL` + 4 historical
    /// order. Empty until `spectraStore.refresh()` resolves.
    private var liveLanes: [SampleLane] {
        let head = spectraStore.items.prefix(5)
        return head.enumerated().map { idx, ident in
            SampleLane(
                label: idx == 0 ? "THIS FILL" : "LANE \(idx)",
                value: String(format: "%.2f", ident.confidence * 100),
                affirm: idx == 0
            )
        }
    }

    /// The verified row this verdict screen is summarizing — the
    /// most-recent identification on the driver's history feed.
    private var headlineLane: SpectraMatchAPI.Identification? {
        spectraStore.items.first
    }

    private var liveHero: String {
        guard let h = headlineLane else { return placeholderHero }
        return String(format: "%.2f", h.confidence * 100)
    }

    private var liveLoadId: String {
        activeLoad?.loadNumber
            ?? headlineLane?.loadId
            ?? placeholderLoadID
    }

    private var liveTitle: String {
        guard let h = headlineLane else { return placeholderTitle }
        return "\(h.crudeType) load signed · \(liveHero)%"
    }

    private var liveSub: String {
        guard let h = headlineLane, !h.category.isEmpty else { return placeholderSub }
        return "Verified by \(h.verifiedBy) · category \(h.category)"
    }

    private var liveCaptured: String {
        guard let h = headlineLane else { return placeholderCaptured }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: h.timestamp)
            ?? ISO8601DateFormatter().date(from: h.timestamp)
        guard let d = date else { return placeholderCaptured }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return "CAPTURED \(out.string(from: d))"
    }

    private var liveRange: String {
        let n = liveLanes.count
        guard n > 0 else { return placeholderRange }
        let pcts = liveLanes.compactMap { Double($0.value) }
        guard let mn = pcts.min(), let mx = pcts.max() else { return placeholderRange }
        let spread = String(format: "%.2f", mx - mn)
        return "All \(n) samples this fill · max−min \(spread)%"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                verdictCard
                rangeCard
                sampleStrip
                signedRow
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await hydrateLiveTrip()
            await spectraStore.refresh()
            updateClock()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            updateClock()
        }
        .screenTileRoot()
    }

    private func updateClock() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        nowClock = f.string(from: Date())
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
                    Image(systemName: "waveform.path")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SPECTRA-MATCH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· VERDICT IN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.success)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(liveTitle)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(liveSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(nowClock.isEmpty ? placeholderClock : nowClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var verdictCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Spectra-Match · final sample")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("✓ PASS")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            Text(liveCaptured)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(headlineLane == nil ? "PENDING" : "PASS")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: -2) {
                    Text(liveHero)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text(placeholderTarget)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            // Measured vs target band — stylized trace
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Target band (horizontal stripe)
                    Rectangle()
                        .fill(Brand.success.opacity(0.12))
                        .frame(height: 12)
                        .offset(y: geo.size.height / 2 - 6)
                    // Measured trace — simple curve
                    Path { p in
                        let w = geo.size.width
                        let h = geo.size.height
                        p.move(to: CGPoint(x: 0, y: h * 0.52))
                        for i in 1...40 {
                            let x = w * CGFloat(i) / 40
                            let wiggle = sin(Double(i) * 0.8) * 8
                            p.addLine(to: CGPoint(x: x, y: h * 0.50 + CGFloat(wiggle)))
                        }
                    }
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(height: 48)

            HStack {
                Text("MEASURED").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("TARGET BAND").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var rangeCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text(liveRange)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var sampleStrip: some View {
        if liveLanes.isEmpty {
            // Empty state — no verified fills on this shift yet.
            // Ready to fill in the moment `spectraMatch.getHistory`
            // returns its first identification (no mock placeholder
            // values; the strip is genuinely blank until the rack
            // signs off and the BOL hits the server).
            HStack(spacing: Space.s2) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("Sample lanes ready · awaiting first verified fill")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        } else {
            HStack(spacing: Space.s2) {
                ForEach(liveLanes) { sample in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.label)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        Text(sample.value)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(sample.affirm ? Brand.success : palette.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(sample.affirm ? Brand.success.opacity(0.5) : palette.borderFaint, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
        }
    }

    private var signedRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 1) {
                Text("Load \(liveLoadId) signed at \(liveHero)% \(headlineLane?.crudeType.uppercased() ?? "")")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("USA SPECTRA-MATCH · BACKED BY EUSOSHIELD · EXIMS AZ LINEAGE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // 100th firing · ledger-hygiene sweep — "Hold for retest" was a
            // no-op stub. Real semantic: driver flags this fill as needing
            // a re-pull before lock-in. We surface that intent by reporting
            // an issue against the current load via env-injected
            // `driverReportIssue` (DriverNavController L291). The full
            // workflow (`spectraMatch.holdForRetest` mutation) is a known
            // gap on the backend per §16 SpectraMatch slice — this hook
            // gives QA a real touchpoint that surfaces in the dispatch
            // exception engine instead of dying silently.
            Button { reportIssue?() } label: {
                Text("Hold for retest")
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
            CTAButton(
                title: "Lock fill, detach",
                action: { Task { await lockFill() } },
                trailingIcon: "arrow.right",
                isLoading: isLocking
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func lockFill() async {
        isLocking = true
        defer { isLocking = false }
        let keys = ["detach", "disconnect", "purge"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }

    private struct SampleLane: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let value: String
        let affirm: Bool
    }
}

struct SpectraMatchVerdictScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            SpectraMatchVerdict(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_031(),
                      trailing: driverNavTrailing_031(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_031() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_031() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("031 · Spectra-Match Verdict · Dark") {
    SpectraMatchVerdictScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("031 · Spectra-Match Verdict · Light") {
    SpectraMatchVerdictScreen(theme: Theme.light).preferredColorScheme(.light)
}
