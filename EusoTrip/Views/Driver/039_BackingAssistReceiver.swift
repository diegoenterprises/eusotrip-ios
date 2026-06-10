//
//  039_BackingAssistReceiver.swift
//  EusoTrip — Lifecycle screen 039 · Backing Assist · Receiver.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `039 Backing Assist Receiver.png`. Driver is reversing onto the
//  receiver's dock with ESANG + supervisor live-mic support. Rear
//  cam cone field + mirror pair + parking-brake countdown ring +
//  left/right clearance tiles + supervisor live-mic card + Hold /
//  Set parking brake CTAs.
//
//  De-fabrication (2026-06-07): every Figma literal that leaked onto
//  the live path was excised, mirroring the proven sibling 037
//  Approaching-Receiver + 024 Unloading de-fabrications:
//    • header clock "21:18" → the live device wall clock, refreshed
//      every minute via TimelineView(.everyMinute);
//    • "Dock 3" (header title + ASSIGNED badge) → the real assigned
//      dock door from `appointments.getByLoad.dockNumber`, the same
//      read 024's detention lane + 037 hydrate; em-dash "-" when no
//      appointment / no door is assigned (no fabricated bay);
//    • header sub "SPOTTER ACTIVE · SCRUBBED GREEN" → honest em-dash
//      "-" (no live spotter/scrub-state feed);
//    • ins-to-pad "8" / brake-at "4" / approach-rate "0.4" / left
//      "22" / right "9" → em-dash "-" (no live proximity / clearance
//      sensor feed reaches this screen; these were Figma readouts);
//    • supervisor "Reg Hammond · night supervisor" + the canned
//      transcript "Two more inches…" → an honest EMPTY STATE that
//      keeps the card chrome but reads "No spotter connected" with no
//      invented person or transcript and no live-mic indicator.
//  No telemetry/proximity source feeds the cone field, the mirror
//  pair, the brake ring, or the clearance tiles, so they render the
//  em-dash sentinel until a real sensor lane lands. Layout, chrome,
//  and nav are preserved verbatim.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BackingAssistReceiver: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isSetting: Bool = false

    /// The most-recent appointment row for this load (assigned dock
    /// door + receiving window) — the same `appointments.getByLoad`
    /// read the sibling lifecycle screens (024/037) hydrate. Nil until
    /// it resolves (or when no door is assigned) → the dock slots fall
    /// through to the em-dash sentinel, never a fabricated "Dock 3".
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// The canonical honest sentinel. No live source → "-" (parity with
    /// 018/024/037/038/051/055). NOT a seeded literal.
    private let dash = "-"

    /// Live wall-clock formatter for the header "now" clock. Device
    /// local time, "HH:mm". Re-evaluated every minute by the header's
    /// TimelineView(.everyMinute), so it is a real clock, not "21:18".
    private func clockText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Bare assigned dock-door label from the live appointment, else "-".
    /// No mode-faked "Spur 3" / "Berth 3" fabrication — when the wire
    /// carries no assigned door the screen reads the honest sentinel.
    private var dockDoor: String {
        guard let d = appointment?.dockNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else {
            return dash
        }
        return d
    }

    /// Mode-aware prefix for the assigned berthing point ("Dock" /
    /// "Spur" / "Berth") — terminology only, never an invented number.
    private var dockKindLabel: String {
        switch ctx.vertical {
        case .truck:  return "Dock"
        case .rail:   return "Spur"
        case .vessel: return "Berth"
        }
    }

    /// "Dock 3" composed from the mode prefix + the LIVE door; collapses
    /// to the bare prefix (no trailing em-dash) when no door is assigned.
    private var dockLabel: String {
        dockDoor == dash ? dockKindLabel : "\(dockKindLabel) \(dockDoor)"
    }

    private var headerTitle: String {
        "Backing into \(dockLabel) · \(receiverCity)"
    }

    private var receiverCity: String {
        // 116th firing M2 retrofit (2026-04-26): replaced fixture
        // fallback "Yara York PA" with the canonical em-dash sentinel.
        // The screen now renders an honest "-" when the active trip
        // hasn't hydrated yet, never a fabricated city. Doctrine:
        // 0% mock data — sentinel parity with 018/024/038/051/055.
        activeLoad?.deliveryLocation?.cityState ?? "-"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                cameraPane
                brakeRing
                clearancePair
                supervisorCard
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
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BACKING ASSIST")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(headerTitle)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                // No live spotter / scrub-state feed reaches this screen —
                // the "SPOTTER ACTIVE · SCRUBBED GREEN" string was a Figma
                // fixture. Render the honest em-dash sentinel.
                Text(dash)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // Live device wall clock, refreshed every minute — never
                // the seeded "21:18".
                TimelineView(.everyMinute) { ctxClock in
                    Text(clockText(ctxClock.date))
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                }
                // ASSIGNED badge shows the real assigned door when the
                // appointment carries one; collapses to a neutral
                // "DOCK ASSIGNMENT PENDING" when no door is assigned,
                // never a fabricated "DOCK 3 ASSIGNED".
                Text(dockDoor == dash
                     ? "\(dockKindLabel.uppercased()) ASSIGNMENT PENDING"
                     : "\(dockLabel.uppercased()) ASSIGNED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(dockDoor == dash ? palette.textTertiary : Brand.success)
            }
        }
        .padding(.top, 4)
    }

    private var cameraPane: some View {
        VStack(spacing: Space.s2) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.black)
                    .frame(height: 200)
                GeometryReader { geo in
                    // Target-line + cones
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.35, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.50, y: geo.size.height))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.8), lineWidth: 2)
                    Path { p in
                        p.move(to: CGPoint(x: geo.size.width * 0.65, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width * 0.50, y: geo.size.height))
                    }
                    .stroke(LinearGradient.diagonal.opacity(0.8), lineWidth: 2)
                    Text("TARGET LINE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.75))
                        .position(x: geo.size.width * 0.50, y: geo.size.height * 0.44)
                }
                .frame(height: 200)
                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Brand.danger).frame(width: 5, height: 5)
                        Text("REAR CAM · CONE FIELD")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    // No live proximity sensor feed → em-dash, not "8 in".
                    Text("\(dash) in")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s2)
            }

            HStack(spacing: Space.s2) {
                // No live mirror-clearance sensor feed → em-dash readouts.
                mirrorBox(label: "LEFT MIRROR", value: dash, color: palette.textTertiary)
                mirrorBox(label: "RIGHT MIRROR", value: dash, color: palette.textTertiary)
            }
        }
    }

    private func mirrorBox(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("\(value) in")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.25))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    /// Brake-ring arc fraction. There is NO live proximity feed reaching
    /// this screen (the center value is the em-dash sentinel), so the
    /// arc renders the honest EMPTY track — never the decorative 0.55
    /// trim the Figma frame baked around a "8 in" readout (Wave-A1
    /// fabrication kill, 2026-06-10). When a real proximity lane lands,
    /// bind this to inches-remaining ÷ approach envelope and the ring
    /// lights up with the same stroke.
    private var brakeRingFraction: CGFloat { 0 }

    private var brakeRing: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().stroke(palette.bgCardSoft, lineWidth: 6).frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: brakeRingFraction)
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                VStack(spacing: -2) {
                    // No live proximity sensor feed → em-dash, not "8".
                    Text(dash)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("IN TO PAD")
                        .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                // Brake-at distance is a live sensor threshold — em-dash
                // until a real proximity feed lands, never "4 in".
                Text("Set parking brake at \(dash) in")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                // Approach rate has no live feed → em-dash; the product-
                // aware caption is honest static guidance, kept.
                Text("\(dash) ft/s APPROACH · \(approachCaption)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                // No live approach-rate sensor feed → em-dash, not "0.4 ft/s".
                Text("\(dash) ft/s")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("APPROACH")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
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

    /// Approach caption changes with product — hazmat tanker has
    /// scrubber post language; dry-van mentions dock plate etc.
    private var approachCaption: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:   return "scrubber side clear · inches to pad"
        case .reefer:                        return "cold door framed · inch to pad"
        case .flatbed:                       return "crane lane clear · straight-in"
        case .container, .railIntermodal, .vesselContainer:
                                             return "twistlocks aligned · straight-in"
        case .railBulk, .vesselBulk:         return "spur guides aligned · inch to pad"
        case .dryVan:                        return "dock plate ready · inches to rubber"
        }
    }

    private var clearancePair: some View {
        // No live left/right clearance sensor feed → em-dash readouts,
        // never the seeded "22"/"9". Neutral color until a real feed lands.
        HStack(spacing: Space.s2) {
            clearanceCell(label: "LEFT CLEARANCE", value: dash, color: palette.textTertiary)
            clearanceCell(label: "RIGHT CLEARANCE", value: dash, color: palette.textTertiary)
        }
    }

    private func clearanceCell(label: String, value: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                    Text("in")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // Honest EMPTY STATE. No live spotter-mic lane feeds this screen,
    // so the fabricated supervisor "Reg Hammond · night supervisor",
    // the canned transcript "Two more inches…", the "LIVE MIC"
    // indicator, and the stylized waveform (which implied an active
    // feed) are all excised. The card chrome — gradient border, avatar
    // slot, container — is preserved verbatim; the avatar shows a
    // neutral person glyph (no invented "RH" initials) and the copy
    // reads "No spotter connected" with no person and no transcript.
    private var supervisorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.bgCardSoft).frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("No spotter connected")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("A spotter's live mic will appear here when one connects.")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Hold")
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
                title: "Set parking brake",
                action: { Task { await setBrake() } },
                trailingIcon: "arrow.right",
                isLoading: isSetting
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Assigned dock door (header title + ASSIGNED badge) — the same
        // `appointments.getByLoad` read 024's detention lane + 037 use.
        // nil-tolerant: no row / no door → the dock slots fall through
        // to the em-dash sentinel rather than a fabricated "Dock 3".
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
    }

    private func setBrake() async {
        isSetting = true
        defer { isSetting = false }
        let keys = ["discharge", "unloading", "connect"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct BackingAssistReceiverScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BackingAssistReceiver(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_039(),
                      trailing: driverNavTrailing_039(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_039() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_039() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("039 · Backing Assist · Dark") {
    BackingAssistReceiverScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("039 · Backing Assist · Light") {
    BackingAssistReceiverScreen(theme: Theme.light).preferredColorScheme(.light)
}
