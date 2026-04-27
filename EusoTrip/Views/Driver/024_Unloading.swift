//
//  024_Unloading.swift
//  EusoTrip — Lifecycle screen 024 · Unloading.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `024 Unloading.png` (Dark + Light). Fires while the trailer is
//  being unloaded at the dock. Surfaces a live pallet map (trailer
//  grid with unloaded squares), a progress counter + rate, a
//  detention ticker (free-time passed → paid), a receiver info
//  row, and an ESANG advisory.
//
//  Adapts to the product — hazmat tanker shows gallons offloaded,
//  reefer shows pallet count (same as dry van), flatbed shows
//  tie-downs released, container shows moves.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct Unloading: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showBol: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackDoor      = "12"
    private let fallbackOff       = 4
    private let fallbackTotal     = 26
    private let fallbackTrailer   = "—"
    private let fallbackStarted   = "00:32"
    private let fallbackEtaRemain = "3:15"
    private let fallbackRate      = "2"
    private let fallbackDetention = "2:47"
    private let fallbackDetRate   = "—"
    private let fallbackDetCharge = "—"
    private let fallbackReceiver  = "—"
    private let fallbackReceiverSub = "dispatch bell · door 12"

    private var percent: Double {
        Double(fallbackOff) / Double(fallbackTotal)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                palletMap
                progressCard
                detentionCard
                receiverRow
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Header

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
                    Text("DETENTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.warning)
                    Text("· PAID TIME")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("Door \(fallbackDoor) · \(fallbackOff) of \(fallbackTotal) \(ctx.unloadUnitLabel) off")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(fallbackTrailer)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 38, height: 38)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Pallet map

    private var palletMap: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PALLET MAP · REFRESHED 03:19")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(palette.textSecondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text("on trailer").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                    Text("unloaded").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }

            // Stylized trailer grid — 110th firing M2 retrofit:
            // hardcoded "TR-2118" excised. Trailer id is not yet a
            // first-class field on Load; until FleetStore.assignedTrailer
            // wires in we render the existing `fallbackTrailer` em-dash
            // sentinel so the layout holds without leaking a fake id.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(fallbackTrailer)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityLabel(fallbackTrailer == "—" ? "Trailer pending" : "Trailer \(fallbackTrailer)")
                    Spacer()
                    Text("DOOR \(fallbackDoor)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    let rows = 2
                    let cols = 13
                    let cellW = (geo.size.width - CGFloat(cols - 1) * 3) / CGFloat(cols)
                    let cellH: CGFloat = 18
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 3) {
                                ForEach(0..<cols, id: \.self) { c in
                                    let idx = r * cols + c
                                    let isOff = idx < fallbackOff
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isOff
                                              ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(palette.bgCardSoft))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(
                                                    isOff ? Color.clear : palette.borderFaint,
                                                    lineWidth: 1
                                                )
                                        )
                                        .frame(width: cellW, height: cellH)
                                }
                            }
                        }
                    }
                }
                .frame(height: 44)

                HStack(spacing: 4) {
                    Text("unload")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(fallbackOff)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("/ \(fallbackTotal) \(ctx.unloadUnitLabel)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("Est. \(fallbackEtaRemain) remaining")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Progress rail
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(percent), height: 5)
                }
            }
            .frame(height: 5)

            HStack {
                Text("STARTED \(fallbackStarted)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("RATE \(fallbackRate) \(ctx.unloadRateLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Detention card

    private var detentionCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DETENTION · PAID")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("PAID")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
            }
            Text(fallbackDetention)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text("Free time ended at 2:00. \(fallbackDetRate) since. Running charge: \(fallbackDetCharge)")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Receiver row

    private var receiverRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(palette.bgCardSoft)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackReceiver)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(fallbackReceiverSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("BACK")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(fallbackDoor)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("Wake the house crew if it stalls. No lumper overnight — they run a two-person crew at 4 \(ctx.unloadUnitLabel)/hr. If detention passes $75, ping dispatch from the Chat button and they'll rebill the shipper.")
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button {
                // Route to the messages tab via the canonical
                // RealtimeService notification — same path the
                // DISPATCH_MESSAGE WS event uses, so the chat
                // surface always resolves the same way regardless
                // of entry point. Was an empty closure (audit hit).
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: nil
                )
            } label: {
                Text("Chat")
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

            CTAButton(title: "View BOL") { showBol = true }
            .sheet(isPresented: $showBol) {
                PickupBolSigning()
                    .environment(\.palette, palette)
                    .eusoSheetX()
            }
        }
    }

    // MARK: Hydration

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }
}

struct UnloadingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            Unloading(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_024(),
                      trailing: driverNavTrailing_024(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_024() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_024() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("024 · Unloading · Dark") {
    UnloadingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("024 · Unloading · Light") {
    UnloadingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
