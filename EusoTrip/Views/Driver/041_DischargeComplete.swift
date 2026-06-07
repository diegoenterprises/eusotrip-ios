//
//  041_DischargeComplete.swift
//  EusoTrip — Lifecycle screen 041 · Discharge Complete.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `041 Discharge Complete.png`. Pump off, valve closed, scrubber
//  vented. Hero shows total transferred + 100% gauge, flow rate
//  averages, settled gauge pair, post-flow checklist (3 of 3
//  confirmed), ESANG custody seal hash row, Share / Disconnect &
//  verify CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DischargeComplete: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverShareLink) private var share
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isAdvancing: Bool = false

    // 041 is now hydrated from `loadLifecycleTanker.getDischargeSummary`
    // (post-discharge roll-up over the `phase="meter"` rows on
    // `bay_ops_events`). `summary` is `nil` while loading and carries the
    // honest-empty / real shape once the proc returns. No fabricated
    // total / started / ended / elapsed / peak-rate / avg-rate / receiver-
    // fill literals remain — when there are no meter rows the screen
    // renders "—" / "-" rather than a seeded reading.
    @State private var summary: LoadLifecycleTankerAPI.DischargeSummary?

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let emDash = "—"

    /// True once the proc has returned a real discharge summary (first +
    /// last meter frame present). While `false`, hero / time row / gauges /
    /// rates render "—" / "-".
    private var hasSummary: Bool { summary?.hasSummary == true }

    /// Total transferred gallons (MAX cumulative across meter frames), or
    /// nil when no summary. Hero number + receiver-gauge sub bind to this.
    private var totalGallonsDisplay: String {
        guard hasSummary, let s = summary else { return emDash }
        return Int(s.totalGallons.rounded()).formatted()
    }

    /// `HH:MM:SS` elapsed between first + last meter frame, or "—".
    private var elapsedDisplay: String {
        guard hasSummary, let s = summary else { return emDash }
        let total = Int(max(0, s.elapsedSeconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    /// First meter-frame wall-clock `HH:MM:SS`, parsed from the ISO-8601
    /// `startedAt`, or "—". Renders in the device's local time zone.
    private var startedDisplay: String {
        clockString(summary?.startedAt)
    }

    /// Last meter-frame wall-clock `HH:MM:SS` from `endedAt`, or "—".
    private var endedDisplay: String {
        clockString(summary?.endedAt)
    }

    /// Peak flow rate (integer), or "-" when no summary.
    private var peakRateDisplay: String {
        guard hasSummary, let s = summary else { return "-" }
        return String(Int(s.peakFlowRateGpm.rounded()))
    }

    /// Average flow rate (integer), or "-" when no summary.
    private var avgRateDisplay: String {
        guard hasSummary, let s = summary else { return "-" }
        return String(Int(s.avgFlowRateGpm.rounded()))
    }

    /// Final receiver fill % (0…100), 0 while loading / no summary.
    private var receiverFillPct: Double {
        guard hasSummary, let s = summary else { return 0 }
        return min(100, max(0, s.receiverFillPct))
    }

    /// Hero completion badge — the real final receiver fill rendered as
    /// "NN% COMPLETE" ("100% COMPLETE" only when the proc reports a full
    /// receiver), or "—" when no summary has landed. Never a fabricated
    /// 100%.
    private var completeBadge: String {
        guard hasSummary else { return emDash }
        return "\(Int(receiverFillPct.rounded()))% COMPLETE"
    }

    /// `HH:MM:SS` local wall clock from an ISO-8601 instant, or "—" when
    /// the timestamp is nil / unparseable (honest empty).
    private func clockString(_ iso: String?) -> String {
        guard let iso else { return emDash }
        let date = Self.isoParser.date(from: iso) ?? Self.isoParserNoFrac.date(from: iso)
        guard let date else { return emDash }
        return Self.clockFormatter.string(from: date)
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserNoFrac = ISO8601DateFormatter()
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                timeRow
                gaugePair
                postFlowChecklist
                custodyRow
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // 100th firing · ledger-hygiene sweep — wired no-op chevron.
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
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Text("DISCHARGE COMPLETE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Discharge complete · \(ctx.dischargeFacilityLine)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(ctx.dischargeCompleteSubtitle)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(elapsedDisplay)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("TOTAL TIME")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TRANSFERRED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline) {
                Text(totalGallonsDisplay)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(ctx.dischargeUnit)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                // Completion badge binds to the real final receiver fill.
                // "100% COMPLETE" only when the summary reports a full
                // receiver; otherwise the honest fill %, or "—" with no
                // summary yet (never a fabricated 100%).
                Text(completeBadge)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(receiverFillPct / 100), height: 6)
                }
            }
            .frame(height: 6)
            Text(ctx.dischargeBolSummary)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var timeRow: some View {
        HStack(spacing: Space.s2) {
            cell(label: "STARTED", value: startedDisplay)
            cell(label: "ENDED",   value: endedDisplay)
            cell(label: "PEAK RATE", value: rateCell(peakRateDisplay))
            cell(label: "AVG RATE",  value: rateCell(avgRateDisplay))
        }
    }

    /// Flow-rate cell value — "NNN gpm" when a rate is present, bare "-"
    /// when no summary (no fabricated unit on an empty value).
    private func rateCell(_ rate: String) -> String {
        rate == "-" ? "-" : "\(rate) \(ctx.unloadRateLabel.lowercased())"
    }

    private func cell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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

    private var gaugePair: some View {
        // Truck (source) is physically empty at discharge-complete — a
        // settled 0% is the terminal truth of this screen, not telemetry.
        // The receiver gauge binds to the real final fill % + transferred
        // gallons from the proc, rendering "—" until the summary lands.
        let receiverSub = hasSummary
            ? "SEALED · FILLED \(totalGallonsDisplay) \(ctx.dischargeUnit.uppercased())"
            : "SEALED · \(emDash)"
        return HStack(spacing: Space.s2) {
            settledGauge(label: "TRUCK (SETTLED)",    value: "0%",
                         barFraction: 0, sub: "STOPPED · TANK EMPTY", color: Brand.warning)
            settledGauge(label: "RECEIVER (SETTLED)",
                         value: hasSummary ? "\(Int(receiverFillPct.rounded()))%" : emDash,
                         barFraction: receiverFillPct / 100,
                         sub: receiverSub, color: Brand.success)
        }
    }

    private func settledGauge(label: String, value: String, barFraction: Double, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(sub)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.bgCardSoft).frame(height: 8)
                    Rectangle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, barFraction))), height: 8)
                }
            }
            .frame(height: 8)
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

    private var postFlowChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("POST-FLOW CHECKLIST · \(ctx.dischargeWatchdogLabel.replacingOccurrences(of: "ESANG WATCHDOG · ", with: ""))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("3 OF 3 CONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            ForEach(Array(ctx.dischargePostFlow.enumerated()), id: \.offset) { _, row in
                postRow(title: row.title, time: row.time)
            }
        }
    }

    private func postRow(title: String, time: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.success)
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(time)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var custodyRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                Text("ESANG CUSTODY · BOL SEALED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("YRA-77419 · A8E2 · 91D0")
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text("SIGNED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // 100th firing · ledger-hygiene sweep — wires "Share" to the
            // env-injected `driverShareLink` closure with the active load
            // number as the share payload (driver shares delivery confirm
            // to dispatch / shipper). Falls through if env not registered
            // or no active load is loaded yet.
            Button {
                if let payload = activeLoad?.loadNumber, !payload.isEmpty {
                    share?(payload)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                    Text("Share")
                        .font(EType.body.weight(.semibold))
                }
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
                title: "Disconnect & verify",
                action: { Task { await advanceToVerify() } },
                trailingIcon: "arrow.right",
                isLoading: isAdvancing
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Post-discharge summary off the `phase="meter"` rows on
        // `bay_ops_events`. Honest-empty (no meter rows) leaves `summary`
        // with null timestamps, so `hasSummary` stays false and every
        // bound field renders "—" / "-" rather than a fabricated reading.
        summary = try? await EusoTripAPI.shared.loadLifecycleTanker
            .getDischargeSummary(loadId: n)
    }

    private func advanceToVerify() async {
        isAdvancing = true
        defer { isAdvancing = false }
        let keys = ["disconnect", "verify", "purged"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct DischargeCompleteScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DischargeComplete(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_041(),
                      trailing: driverNavTrailing_041(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_041() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_041() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("041 · Discharge Complete · Dark") {
    DischargeCompleteScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("041 · Discharge Complete · Light") {
    DischargeCompleteScreen(theme: Theme.light).preferredColorScheme(.light)
}
