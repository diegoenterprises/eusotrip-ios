//
//  034_DepartingPickup.swift
//  EusoTrip — Lifecycle screen 034 · Departing Pickup.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `034 Departing Pickup.png`. BOL is signed (033), gate is armed,
//  the rig is rolling. Surfaces a mini route map (pickup →
//  receiver), distance/ETA/via tiles, 3 compliance confirmation
//  rows (NET AT FILL, SPECTRA-MATCH FINAL, BOL SIGNED),
//  EusoShield in-transit binder ACTIVE chip, and a first-leg
//  turn card with HOS / fuel / bay-light row.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DepartingPickup: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverOpenTripLog) private var openTripLog
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isStartingNav: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Production-clean placeholders.
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass).
    // Live values come from `loadLifecycle.getCurrentLeg`,
    // `navigation.calculateRoute`, `hos.getStatus`, and
    // `vehicle.getFuelLevel`. Until those resolve, em-dashes only —
    // no fabricated origin/destination/ETA rendered in production.
    private let fallbackClock        = "—"
    private let fallbackLoadID       = "—"
    private let fallbackOriginTag    = "—"
    private let fallbackDestTag      = "—"
    private let fallbackDestName     = "—"
    private let fallbackDestSub      = "Awaiting route"
    private let fallbackDistance     = "—"
    private let fallbackEta          = "—"
    private let fallbackViaRoute     = "—"
    private let fallbackFirstLegSub  = "—"
    private let fallbackHos          = "—"
    private let fallbackFuel         = "—"
    private let fallbackBayLight     = "—"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                routeMapCard
                rowTriplet
                binderRow
                firstLegCard
                vitalRow
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
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("RELEASED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ctx.headerKicker)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Rolling to \(fallbackDestName)")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackDestSub)
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

    /// Stylized map strip with purple polyline from pickup tag to
    /// destination tag. Not a live HERE render — the live map shows
    /// up in 035 when nav is started. This is the handoff card.
    private var routeMapCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                ZStack {
                    Rectangle()
                        .fill(palette.bgCardSoft)
                    // Polyline dots
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.15, y: geo.size.height * 0.70))
                        p.addQuadCurve(
                            to: CGPoint(x: geo.size.width * 0.80, y: geo.size.height * 0.32),
                            control: CGPoint(x: geo.size.width * 0.50, y: geo.size.height * 0.20)
                        )
                    }
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))

                    // Origin (magenta)
                    VStack(spacing: 2) {
                        Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                        Text(fallbackOriginTag)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.80)

                    // Destination (ring)
                    VStack(spacing: 2) {
                        Text(fallbackDestTag)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textPrimary)
                        Circle()
                            .stroke(LinearGradient.diagonal, lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                    .position(x: geo.size.width * 0.82, y: geo.size.height * 0.22)

                    // Miles badge
                    Text(fallbackDistance.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().stroke(palette.borderFaint))
                        .position(x: geo.size.width * 0.82, y: geo.size.height * 0.40)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            HStack(spacing: Space.s2) {
                tile(label: "DISTANCE", value: fallbackDistance)
                tile(label: "ETA",      value: fallbackEta)
                tile(label: "VIA",      value: fallbackViaRoute)
            }
        }
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
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

    /// Product-dispatched compliance strip — 3 rows that change
    /// by product (hazmat tanker: loaded gallons / Spectra / BOL;
    /// dry van: pallets / seal / BOL; reefer: cold pallets /
    /// set-point / temp trace; flatbed: weight / securement / BOL;
    /// container: box+chassis / seal / VGM; rail bulk / vessel
    /// bulk: net / cert / waybill).
    private var rowTriplet: some View {
        VStack(spacing: 4) {
            ForEach(ctx.departingCompliance) { row in
                triRow(icon: row.icon, label: row.label, value: row.value)
            }
        }
    }

    private func triRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
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

    private var binderRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 1) {
                Text("EusoShield in-transit binder $5M active")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("USA EUSOSHIELD · BACKED BY ESANG AI LINEAGE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            HStack(spacing: 3) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var firstLegCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FIRST LEG")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(fallbackFirstLegSub)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(ctx.firstLegTurn)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var vitalRow: some View {
        HStack(spacing: Space.s2) {
            vitalCell(label: "HOS DRIVE LEFT", value: fallbackHos)
            vitalCell(label: "FUEL",            value: fallbackFuel)
            vitalCell(label: "BAY LIGHT",       value: fallbackBayLight, tint: Brand.success)
        }
    }

    private func vitalCell(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(tint ?? palette.textPrimary)
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
            // 100th firing · ledger-hygiene sweep — was no-op. Wires to
            // env-injected `driverOpenTripLog` (DriverNavController L241).
            // Falls through if env not registered (preview-safe).
            Button { openTripLog?() } label: {
                Text("Trip log")
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
                title: "Start nav",
                action: { Task { await startNav() } },
                trailingIcon: "arrow.right",
                isLoading: isStartingNav
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func startNav() async {
        isStartingNav = true
        defer { isStartingNav = false }
        let keys = ["in_transit", "drive", "en_route", "rolling"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct DepartingPickupScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DepartingPickup(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_034(),
                      trailing: driverNavTrailing_034(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_034() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_034() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("034 · Departing Pickup · Dark") {
    DepartingPickupScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("034 · Departing Pickup · Light") {
    DepartingPickupScreen(theme: Theme.light).preferredColorScheme(.light)
}
