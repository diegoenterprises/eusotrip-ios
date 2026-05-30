//
//  021_AtReceiverGate.swift
//  EusoTrip — Lifecycle screen 021 · At Receiver Gate.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `021 At Receiver Gate.png` (Dark + Light). Fires when the
//  driver's inside the geofence, dash-cam armed, sitting at the
//  guard shack waiting for a dock push. Anchored by a big gradient
//  guard-check card + a 3-button action row (Call Guard / Open BOL
//  / Message Receiver) + a product-aware advisory + "I'm checked
//  in" / "Call dispatch" footer.
//
//  Composition:
//    • Header — back chevron + "AT RECEIVER GATE" kicker +
//      facility title + trailer / seal subline + brand badge.
//    • Geofence pill — "0.0 MI · DASH-CAM ARMED".
//    • Guard check card — load id kicker, huge gradient "B" block
//      letter + "Checking in" + gate address, 3-metric row
//      (ARRIVED / QUEUE / APPT).
//    • Guard note — product-aware advisory explaining what the
//      guard is doing + expected wait.
//    • 3-button action row — Call Guard / Open BOL / Message
//      Receiver, each with a glyph + label.
//    • Advisory banner (green) — yard-lights protocol.
//    • Footer CTAs — "I'm checked in" gradient + "Call dispatch"
//      outline.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct AtReceiverGate: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverDialPhone) private var dialPhone
    @Environment(\.driverOpenMessages) private var openMessages
    @Environment(\.driverOpenDocDrawer) private var openDocDrawer
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?
    @State private var didHydrate: Bool = false
    @State private var isCheckingIn: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Em-dash sentinels
    //
    // 113th-firing M2 retrofit: the gate metrics were Figma literals
    // ("00:15" / "#1" / "23:30") that leaked onto the live path. They
    // now resolve from live state where a backend source exists, and
    // hold the universal em-dash sentinel otherwise — never a faked
    // value. ARRIVED (a geofence-entry timestamp) and QUEUE (a guard
    // shack queue position) have no column on loads.getById or
    // appointments.getByLoad, so they stay em-dash until those land.
    private let dash              = "—"
    private let fallbackFacility  = "—"
    private let fallbackTrailer   = "—"
    private let fallbackLoadID    = "—"

    /// Gate address line — delivery facility from the live load
    /// (address > cityState), em-dash until the load hydrates.
    private var gateLine: String { ctx.facets.deliveryFacility }

    /// ARRIVED — geofence-entry wall-clock. No backend column yet, so
    /// em-dash on the live path.
    private var arrivedMetric: String { dash }

    /// QUEUE — guard-shack position. No backend column yet, em-dash.
    private var queueMetric: String { dash }

    /// APPT — live scheduled appointment time, rendered HH:mm local.
    /// Source: appointments.getByLoad → scheduledAt, falling through
    /// to the load's deliveryDate. Em-dash when neither is set.
    private var apptMetric: String {
        if let t = formatTime(appointment?.scheduledAt) { return t }
        if let t = formatTime(activeLoad?.deliveryDate) { return t }
        return dash
    }

    private func formatTime(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if !didHydrate && activeLoad == nil {
                    loadingState
                } else if activeLoad == nil {
                    emptyState
                } else {
                    header
                    geofencePill
                    guardCard
                    actionRow
                    advisoryBanner
                    footerActions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Loading / empty

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
                .tint(palette.textSecondary)
            Text("Locating your active load…")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "house.fill",
            title: "No active gate check-in",
            subtitle: "When you reach a receiver geofence, your guard-check card lands here."
        )
        .frame(maxWidth: .infinity, minHeight: 320)
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
                HStack(spacing: 6) {
                    Text("AT RECEIVER GATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(deliveryTitle)
                    .font(.system(size: 22, weight: .heavy))
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
                Image(systemName: "house.fill")
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

    // MARK: Geofence

    private var geofencePill: some View {
        HStack(spacing: 6) {
            Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
            Text("0.0 MI · DASH-CAM ARMED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Guard card

    private var guardCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("GUARD CHECK")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(activeLoad?.loadNumber ?? fallbackLoadID)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("B")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checking in")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(gateLine)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            // 3-metric row
            HStack(spacing: Space.s2) {
                metric(label: "ARRIVED", value: arrivedMetric)
                metric(label: "QUEUE",   value: queueMetric)
                metric(label: "APPT",    value: apptMetric)
            }

            Text(ctx.guardCheckNote)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: 3-button action row

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            actionButton(symbol: "phone.fill", label: "Call", sub: "Guard") {
                Task {
                    let rows = (try? await EusoTripAPI.shared.contacts
                        .list(type: "shipper", limit: 1)) ?? []
                    if let phone = rows.first?.phone, !phone.isEmpty {
                        dialPhone?(phone)
                    } else {
                        openMessages?(nil)
                    }
                }
            }
            actionButton(symbol: "doc.fill", label: "Open BOL", sub: "PDF · 3p") {
                openDocDrawer?()
            }
            actionButton(symbol: "message.fill", label: "Message", sub: "Receiver") {
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

    // MARK: Advisory banner

    private var advisoryBanner: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("Watch the yard lights. Amber over your gate means advance to dock; green at the dock door means back in. Don't wait for a second call.")
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
                title: "I'm checked in",
                action: { Task { await markCheckedIn() } },
                isLoading: isCheckingIn
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

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else {
            didHydrate = true
            return
        }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Live appointment (gate APPT metric + status sync), mirroring
        // the 024 Unloading hydrate path.
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
        didHydrate = true
    }

    private func markCheckedIn() async {
        isCheckingIn = true
        defer { isCheckingIn = false }
        let forwardKeys = ["checked_in", "dock_assigned", "at_dock", "unloading"]
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

// MARK: - Wrapper

struct AtReceiverGateScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            AtReceiverGate(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_021(),
                      trailing: driverNavTrailing_021(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_021() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_021() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("021 · At Receiver Gate · Dark") {
    AtReceiverGateScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("021 · At Receiver Gate · Light") {
    AtReceiverGateScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
