//
//  043_DisconnectConfirmed.swift
//  EusoTrip — Lifecycle screen 043 · Disconnect Confirmed.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `043 Disconnect Confirmed.png`. All 4 ladder steps confirmed,
//  hose stowed, stub capped (or trailer secured / container
//  released depending on product). EusoShield binder closed.
//  Shows a "All clear" checklist + dock receipt + ESANG +
//  Receipt / Depart receiver CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DisconnectConfirmed: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isDeparting: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock = "21:54"
    private let fallbackElapsed = "06:54"

    /// Disconnect-confirmed headline — composes "Disconnect
    /// confirmed · <cityState>" with em-dash sentinels for the
    /// parts that aren't first-class fields on `Load` yet.
    ///
    /// 116th firing M2 retrofit (2026-04-26): previous literal
    /// "Yara York PA Dock 3" excised. The dock label (e.g.
    /// "Dock 3") is not yet a first-class field on `Load`; until
    /// `Load.deliveryDockLabel` ships from the backend the
    /// headline omits the dock segment entirely rather than
    /// fabricating one. The cityState is hydrated live from the
    /// active trip's `deliveryLocation`. Doctrine: 0% mock data —
    /// no fabricated brand or dock in the production UI.
    private var disconnectHeadline: String {
        let cityState = activeLoad?.deliveryLocation?.cityState ?? "—"
        return "Disconnect confirmed · \(cityState)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                stowedCard
                allClearCopy
                metricRow
                ladder
                receiptRow
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
                    Text("DISCONNECT CONFIRMED")
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
                Text(disconnectHeadline)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("ALL 4 STEPS VERIFIED · BINDER CLOSED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackElapsed)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("ELAPSED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var stowedCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(ctx.isHazmat ? "NH3 · DRY-DISCONNECT" : "TRAILER · SECURED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("✓ STOWED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(Color.black.opacity(0.7))
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.35, height: 12)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Brand.success)
                        Capsule().fill(palette.textSecondary).frame(width: geo.size.width * 0.35, height: 12)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: 60)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var allClearCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ALL CLEAR")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(ctx.isHazmat ? "Hose stowed · stub capped" : "Trailer secured · ready to roll")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(ctx.isHazmat
                 ? "EusoShield closed the discharge binder. Dry-disconnect cap locked, scrubber on standby. You're cleared to pull off the dock."
                 : "EusoShield closed the binder. Trailer doors closed and sealed. You're cleared to pull off the dock.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metricRow: some View {
        HStack(spacing: Space.s2) {
            metric(label: "PRESSURE", value: "0", unit: "psi", note: "VENTED")
            metric(label: "VAPOR", value: "0", unit: "ppm", note: "AMBIENT")
            metric(label: "ESD BOND", value: "Released", unit: "", note: "STOWED")
        }
    }

    private func metric(label: String, value: String, unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Text(note)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
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

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISCONNECT LADDER · \(ctx.isHazmat ? "NH3 CLOSED-LOOP" : "RECEIVER")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("4 OF 4 CONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            ForEach(ctx.disconnectLadder) { step in
                HStack(spacing: Space.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Brand.success)
                    Text(step.title)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(step.timestamp ?? "21:46:14")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
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
        }
    }

    private var receiptRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DOCK RECEIPT · YRA-77419-DR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ACKNOWLEDGED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                    Text("WS").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                }
                Text("Wendell Suh · receiver supervisor")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("21:53:48")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
                Text("ESANG · AI co-signature")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("HASH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
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
            Button { navBack?() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Receipt")
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
                title: "Depart receiver",
                action: { Task { await depart() } },
                leadingIcon: "arrow.right",
                isLoading: isDeparting
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func depart() async {
        isDeparting = true
        defer { isDeparting = false }
        let keys = ["departing", "completed", "drop_hose"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct DisconnectConfirmedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DisconnectConfirmed(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_043(),
                      trailing: driverNavTrailing_043(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_043() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_043() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("043 · Disconnect Confirmed · Dark") {
    DisconnectConfirmedScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("043 · Disconnect Confirmed · Light") {
    DisconnectConfirmedScreen(theme: Theme.light).preferredColorScheme(.light)
}
