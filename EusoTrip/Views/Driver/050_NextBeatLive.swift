//
//  050_NextBeatLive.swift
//  EusoTrip — Lifecycle screen 050 · Next Beat Live (off-duty reset).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `050 Next Beat Live.png`. DVIR submitted, sleeper bay keyed,
//  34-hour reset clock running. Resting hero ring + off-duty
//  card + 3 amenity tiles + product-aware ESANG-holds list +
//  ESANG voice strip + Amenities / Set do-not-disturb CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

struct NextBeatLive: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isMutingDND: Bool = false
    /// Toggle for the "Amenities" sheet — surfaces nearby parking +
    /// fuel via the HERE clients. Replaces the prior dead `navBack()`
    /// secondary CTA per the no-dead-buttons sweep.
    @State private var showAmenities: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock        = "23:30"
    private let fallbackHoursRemain  = "34:00"
    private let fallbackEndsAt       = "Sun 09:30"
    private let fallbackBayLabel     = "Bay 14 keyed"
    private let fallbackPrePing      = "ESANG pre-trip ping queued for 09:30"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                restingCard
                offDutyCard
                amenityTiles
                holdsCard
                esangFooter
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
        .sheet(isPresented: $showAmenities) {
            AmenitiesNearbySheet(palette: palette)
                .presentationDetents([.large])
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
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("LIVE RESET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var restingCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().stroke(palette.bgCardSoft, lineWidth: 6).frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0, to: 0.99)
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                VStack(spacing: -2) {
                    Text(fallbackHoursRemain)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("HOURS REMAINING")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("OFF-DUTY · 34-HOUR RESET")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Resting. Clock running.")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Ends \(fallbackEndsAt) · \(fallbackBayLabel)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                Text(fallbackPrePing)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var offDutyCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 1) {
                Text("Off-duty · 49 CFR 395.3(c) reset")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Sleeper \(ctx.vertical.bayWord) 14 · key pushed to smart lock")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("RESTING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var amenityTiles: some View {
        HStack(spacing: Space.s2) {
            tile(label: "BAY 14 TEMP",   value: "21°C", sub: "QUIET")
            tile(label: "DND",            value: "0H",   sub: "ALERTS SILENCED")
            tile(label: "BREAKFAST",      value: "06:30", sub: "SLOT MGR")
        }
    }

    private func tile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
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

    private var holdsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT ESANG HOLDS THROUGH THE RESET")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            ForEach(ctx.nextBeatHolds) { hold in
                HStack(spacing: Space.s3) {
                    Image(systemName: holdIcon(hold))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(holdColor(hold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hold.title)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(hold.subtitle)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(hold.tail)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(holdColor(hold))
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

    private func holdIcon(_ hold: LifecycleProductContext.ResetHold) -> String {
        if hold.tail == "ACCEPTED" { return "checkmark.circle.fill" }
        if hold.tail == "QUEUED"   { return "clock.fill" }
        return "doc.fill"
    }
    private func holdColor(_ hold: LifecycleProductContext.ResetHold) -> Color {
        if hold.tail == "ACCEPTED" { return Brand.success }
        if hold.tail == "QUEUED"   { return Brand.warning }
        return palette.textSecondary
    }

    private var esangFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · REST WELL · I'LL WAKE YOU 09:30 SUNDAY · TENDER LOCKED · WEATHER CHECK AT 06:00")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button {
                MeAction.fire("050.amenities-requested",
                              userInfo: ["loadId": lifecycle.loadId])
                showAmenities = true
            } label: {
                Text("Amenities")
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
                title: "Set do-not-disturb",
                action: { Task { await setDND() } },
                trailingIcon: "arrow.right",
                isLoading: isMutingDND
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func setDND() async {
        isMutingDND = true
        defer { isMutingDND = false }
        let keys = ["dnd", "rest", "completed"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct NextBeatLiveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            NextBeatLive(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_050(),
                      trailing: driverNavTrailing_050(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_050() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_050() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Amenities sheet
//
// Surfaces nearby parking + fuel for the driver's current fix. Lives
// inside 050 because it's a Next-Beat companion, but the implementation
// is generic enough that other lifecycle screens (045 DepartingReceiver,
// 053 Dispatch chat) can present the same sheet by calling the same
// view directly.

private struct AmenitiesNearbySheet: View {
    let palette: Theme.Palette
    @Environment(\.dismiss) private var dismiss

    @State private var coord: CLLocationCoordinate2D?
    @State private var parking: [HereBrowseParkingItem] = []
    @State private var fuel: [HereFuelStation] = []
    @State private var isLoading: Bool = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AMENITIES NEAR YOU")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("Parking · diesel · truck stops")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                SheetCloseButton { dismiss() }
            }
            .padding(Space.s4)

            if isLoading {
                VStack(spacing: Space.s3) {
                    ProgressView()
                    Text("Pulling fresh HERE data…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = error {
                VStack(spacing: Space.s3) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        if !parking.isEmpty {
                            sectionHeader("PARKING + TRUCK STOPS")
                            VStack(spacing: 6) {
                                ForEach(parking.prefix(8)) { p in
                                    parkingRow(p)
                                }
                            }
                        }
                        if !fuel.isEmpty {
                            sectionHeader("DIESEL · NEAREST 8")
                            VStack(spacing: 6) {
                                ForEach(fuel.prefix(8), id: \.id) { f in
                                    fuelRow(f)
                                }
                            }
                        }
                        if parking.isEmpty && fuel.isEmpty {
                            Text("No amenities found within 25 miles. Try widening the radius from Settings.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(Space.s4)
                }
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await load() }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    private func parkingRow(_ p: HereBrowseParkingItem) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "p.square.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(p.address?.label ?? "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let m = p.distance {
                Text("\(Int(round(Double(m) / 1609.344))) mi")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func fuelRow(_ f: HereFuelStation) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(f.name ?? "Diesel")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(f.address?.oneLine ?? "—")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let p = f.cheapestDieselPrice {
                Text(String(format: "$%.2f", p.price))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let c = await DriverLocationResolver.shared.currentCoordinate()
        guard let c else {
            error = "Couldn't get a location fix. Enable Location Services and try again."
            return
        }
        coord = c
        async let parkingTask: [HereBrowseParkingItem] = (try? await HereParkingClient().parkingNearby(center: c)) ?? []
        async let fuelTask: [HereFuelStation] = (try? await HereFuelPricesClient().nearby(center: c)) ?? []
        let (p, f) = await (parkingTask, fuelTask)
        parking = p
        fuel = f
        if p.isEmpty && f.isEmpty {
            error = nil
        }
    }
}

#Preview("050 · Next Beat Live · Dark") {
    NextBeatLiveScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("050 · Next Beat Live · Light") {
    NextBeatLiveScreen(theme: Theme.light).preferredColorScheme(.light)
}
