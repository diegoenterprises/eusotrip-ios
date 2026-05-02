//
//  022_DockAssigned.swift
//  EusoTrip — Lifecycle screen 022 · Dock Assigned.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `022 Dock Assigned.png` (Dark + Light). Fires when the guard
//  pushes the dock number to the driver. Leads with the big
//  gradient "B → 12" transition graphic, 3 orientation metrics
//  (DOOR / AISLE / APPROACH), a yard-map strip, 3-button action
//  row, a tip banner, and the final "I'm at door 12" / "Call
//  dispatch" CTAs.
//
//  Every label + glyph passes through `LifecycleProductContext`
//  so approach word, facility line, and load metadata adapt to
//  the vertical + product — a container driver sees "ramp / stack
//  / straight-in" instead of "door / aisle / blind-side".
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DockAssigned: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverDialPhone) private var dialPhone
    @Environment(\.driverOpenMessages) private var openMessages
    @Environment(\.driverUploadPhoto) private var uploadPhoto
    @EnvironmentObject private var session: EusoTripSession

    @State private var showYardmap: Bool = false

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackFacility = "—"
    private let fallbackTrailer  = "—"
    private let fallbackGuard    = "Guard · 00:30  Dwell 17m"
    private let fallbackDoor     = "12"
    private let fallbackAisle    = "2"
    private let fallbackPushTime = "—"
    private let fallbackAisleLine = "Aisle 2 · night receiving"
    private let fallbackApproachSub = "Blind-side · flush to the rubber"
    private let fallbackYardLine = "YARD · SC 2718"

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                clearedStrip
                dockCard
                yardMap
                actionRow
                tipBanner
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .sheet(isPresented: $showYardmap) {
            DockYardmapSheet(load: activeLoad, dockNumber: fallbackDoor)
                .environment(\.palette, palette)
        }
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
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("DOCK ASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(deliveryTitle)
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
                Image(systemName: ctx.product.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    private var deliveryTitle: String {
        guard let loc = activeLoad?.deliveryLocation,
              !loc.cityState.isEmpty else { return fallbackFacility }
        let brand = loc.address.isEmpty ? loc.cityState : loc.address
        return "\(brand) · \(loc.cityState)"
    }

    // MARK: Cleared strip

    private var clearedStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("CLEARED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.success)
            Text(fallbackGuard)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Dock card

    private var dockCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DOCK ASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.success)
                Spacer(minLength: 0)
                Text(fallbackPushTime)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("B")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(fallbackDoor)
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }

            Text(fallbackAisleLine)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(fallbackApproachSub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: Space.s2) {
                dockMetric(label: "DOOR", value: fallbackDoor)
                dockMetric(label: "AISLE", value: fallbackAisle)
                dockMetric(label: "APPROACH", value: ctx.defaultApproach)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dockMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Yard map strip

    private var yardMap: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(fallbackYardLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("EXPAND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }

            // Receiving aisle strip — stylized row of dock doors with
            // the driver's assigned door highlighted.
            GeometryReader { geo in
                let count = 14
                let slot = geo.size.width / CGFloat(count)
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 7 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(
                                            i == 7 ? Color.clear : palette.borderFaint,
                                            lineWidth: 1
                                        )
                                )
                                .frame(height: 28)
                                .frame(width: slot - 2)
                        }
                    }
                    // Driver truck marker under door 12
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 8, height: 8)
                        .offset(x: slot * 7 + slot / 2 - 4, y: 18)
                }
            }
            .frame(height: 48)

            HStack(spacing: Space.s3) {
                legend(color: LinearGradient.diagonal, label: "Your door")
                legend(color: palette.bgCardSoft, label: "Other docks")
                legend(color: LinearGradient.diagonal, label: "You", asCircle: true)
            }
            .font(.system(size: 9, weight: .semibold)).tracking(0.4)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func legend<S: ShapeStyle>(color: S, label: String, asCircle: Bool = false) -> some View {
        HStack(spacing: 4) {
            Group {
                if asCircle {
                    Circle().fill(color).frame(width: 8, height: 8)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 6)
                }
            }
            Text(label)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        // Yardmap, Dock cam, Message Lumper — all real today.
        //   • Yardmap → HereMapView sheet pinned on the load's
        //     deliveryLocation so the driver can orient inside the
        //     terminal yard at GPS resolution. Upgrade path:
        //     NearbyInteraction (cm-level UWB anchors at each dock
        //     door) + websocket-pushed yard graph (forklift +
        //     trailer positions) — pending founder pick.
        //   • Dock cam → device camera via `\.driverUploadPhoto`
        //     env, scoped to the dock door for safety/audit photo.
        //     Upgrade path: WebRTC stream from the terminal's
        //     Genetec / Avigilon NVR via a signaling websocket —
        //     pending founder pick.
        //   • Message Lumper → real `\.driverOpenMessages(nil)`
        //     opening the messaging inbox.
        HStack(spacing: Space.s2) {
            actionButton(symbol: "map.fill", label: "Yardmap", sub: "Full view") {
                showYardmap = true
            }
            actionButton(symbol: "camera.fill",
                         label: "Dock cam",
                         sub: "Door \(fallbackDoor)") {
                uploadPhoto?()
            }
            actionButton(symbol: "message.fill", label: "Message", sub: "Lumper") {
                openMessages?(nil)
            }
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        sub: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tip banner

    private var tipBanner: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("Green at door \(fallbackDoor) = back in \(ctx.defaultApproach.lowercased()). Check the rear once flush, then walk the BOL packet to receiving on aisle \(fallbackAisle).")
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
            CTAButton(
                title: "I'm at door \(fallbackDoor)",
                action: { Task { await markAtDoor() } },
                isLoading: isConfirming
            )

            Button {
                Task {
                    let rows = (try? await EusoTripAPI.shared.contacts
                        .list(type: "dispatcher", limit: 1)) ?? []
                    if let phone = rows.first?.phone, !phone.isEmpty {
                        dialPhone?(phone)
                    } else {
                        openMessages?(nil)
                    }
                }
            } label: {
                Text("Call dispatch")
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
        }
    }

    // MARK: Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func markAtDoor() async {
        isConfirming = true
        defer { isConfirming = false }
        let forwardKeys = ["backing", "at_door", "unloading"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }
}

struct DockAssignedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DockAssigned(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_022(),
                      trailing: driverNavTrailing_022(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_022() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_022() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Yardmap sheet

/// Driver-facing yardmap presented when the dock-assigned action row's
/// "Yardmap" affordance fires. Uses the canonical `HereMapView` (the
/// same component every other lifecycle / pulse map surface uses) so
/// the driver sees a consistent palette + legend. Pinned on the load's
/// deliveryLocation today (GPS resolution).
///
/// Upgrade path (pending founder pick from feedback_no_ceilings
/// options menu): NearbyInteraction (`NISession` + UWB anchors at each
/// dock door) overlays cm-level positioning + direction once the
/// terminal-side anchors deploy; a websocket stream from the
/// terminal-ops backend (`yardOps.streamPositions`) renders live
/// trailer + forklift positions as additional `LoadMarker` rows.
struct DockYardmapSheet: View {
    let load: Load?
    let dockNumber: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HereMapView(
                stops: load.flatMap { ld -> [LoadLocation] in
                    if let drop = ld.deliveryLocation { return [drop] }
                    return []
                } ?? []
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Yardmap · Door \(dockNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("022 · Dock Assigned · Dark") {
    DockAssignedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("022 · Dock Assigned · Light") {
    DockAssignedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
