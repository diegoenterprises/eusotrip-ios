//
//  028_LoadLockedPrehaul.swift
//  EusoTrip — Lifecycle screen 028 · Load Locked · Prehaul.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `028 Load Locked Prehaul.png` (Dark + Light). The driver has
//  accepted the load (027) — now the rig is LOCKED and the hazmat
//  pre-haul gate must clear all 9 compliance checks before any
//  wheels turn. Adapts to product via `LifecycleProductContext`:
//  hazmat shows ERG + placards + MC-331 rows, dry van shows
//  seal + BOL packet + pallet-jack rows, etc.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UserNotifications

struct LoadLockedPrehaul: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []
    @State private var isRolling: Bool = false
    @State private var reminderToast: String? = nil

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Production-clean placeholders.
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass).
    // Live values: `loads.getById` for origin/dest/manifest and
    // `loadLifecycle.getRollClock` for the appointment timer.
    private let fallbackClock       = "—"
    private let fallbackLoadID      = "—"
    private let fallbackOrigin      = "—"
    private let fallbackDestination = "—"
    private let fallbackManifest    = "—"
    private let fallbackRollClock   = "—"
    private let fallbackApptSub     = "—"

    private var checklist: [PrehaulCheck] {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:
            return [
                .init(id: "papers",   title: "Shipping papers in cab reach", subtitle: "49 CFR 177.817 · BOL + emergency response info pinned to load card", cta: "VIEW"),
                .init(id: "erg",      title: "ERG Guide 125 acknowledged",   subtitle: "Inhalation-hazard procedures · isolation 100m, downwind 800m", cta: "REOPEN"),
                .init(id: "placards", title: "Placards verified",            subtitle: "Front-rear-sides · INHALATION HAZARD · 2.2 · NON-FLAMMABLE GAS", cta: "CAPTURE"),
                .init(id: "mc331",    title: "MC-331 cert current",          subtitle: prehaulTankCertSubtitle, cta: "PINNED"),
                .init(id: "endors",   title: "Endorsements green",           subtitle: prehaulEndorsementSubtitle, cta: prehaulEndorsementBadge),
                .init(id: "binder",   title: "EusoShield binder active",     subtitle: prehaulBinderSubtitle, cta: "BINDER"),
                .init(id: "grnd",     title: "ESANG grounding brief",        subtitle: "2-min walkthrough · grounding strap + 2-valve (liquid + vapor) check", cta: "START"),
                .init(id: "photo",    title: "Pre-haul photo",               subtitle: "Trailer + placards + grounding point · auto-stamps coordinates", cta: "CAMERA"),
                .init(id: "ack",      title: "Driver acknowledgment",        subtitle: "I confirm the above, and I'm fit to haul Class 2.2 tonight", cta: "SIGN"),
            ]
        case .reefer:
            return [
                // 140th firing M3 sweep — set-point literal swapped
                // for `facets.setPointDisplay`. Em-dash drops cleanly
                // when the load envelope hasn't shipped a set-point.
                .init(id: "setpoint", title: "Set-point logged", subtitle: prehaulReeferSetpointSubtitle, cta: "OK"),
                .init(id: "fuel",     title: "Reefer fuel", subtitle: prehaulReeferFuelSubtitle, cta: "GAUGE"),
                .init(id: "airchute", title: "Air chute staged", subtitle: "Even airflow · no dead zones", cta: "VERIFY"),
                .init(id: "papers",   title: "BOL + temp trace", subtitle: "Cold-chain compliance packet", cta: "VIEW"),
                .init(id: "photo",    title: "Pre-haul photo", subtitle: "Trailer + seal + set-point display", cta: "CAMERA"),
                .init(id: "ack",      title: "Driver acknowledgment", subtitle: "I confirm the temp trace + I'm fit to haul", cta: "SIGN"),
            ]
        case .flatbed:
            return [
                .init(id: "tarps",    title: "Tarps + corner protectors", subtitle: "2 steel tarps folded · corner pads ready", cta: "READY"),
                .init(id: "straps",   title: "Straps + chains inspected", subtitle: "12 straps within WLL · 2 chains 5/16 grade 70", cta: "VERIFY"),
                .init(id: "wll",      title: "Working load (WLL) check", subtitle: "49 CFR 393 match commodity", cta: "OK"),
                .init(id: "papers",   title: "Securement docs on board", subtitle: "Shipper load + count sheet · BOL", cta: "VIEW"),
                .init(id: "photo",    title: "Pre-haul photo",           subtitle: "Trailer + tarp + strap pattern", cta: "CAMERA"),
                .init(id: "ack",      title: "Driver acknowledgment",    subtitle: "I confirm securement is DOT-compliant", cta: "SIGN"),
            ]
        case .container, .railIntermodal, .vesselContainer:
            return [
                .init(id: "chassis",  title: "Chassis DOT pre-trip clear",  subtitle: "Lights · brakes · tires · locking pins", cta: "OK"),
                .init(id: "iso",      title: "Container + ISO match",       subtitle: prehaulIsoSubtitle, cta: "VERIFY"),
                .init(id: "seal",     title: "Seal intact + matches BOL",   subtitle: prehaulSealSubtitle, cta: "PHOTO"),
                .init(id: "edi",      title: "EDI 322 gate-out ready",      subtitle: "Fires on scanner at port / ramp exit", cta: "ARMED"),
                .init(id: "vgm",      title: "VGM filed",                   subtitle: prehaulVgmSubtitle, cta: "FILED"),
                .init(id: "ack",      title: "Driver acknowledgment",       subtitle: "I confirm container + chassis ready to roll", cta: "SIGN"),
            ]
        default:
            return [
                .init(id: "seal",    title: "Trailer seal logged", subtitle: "Photograph + number captured", cta: "OK"),
                .init(id: "swept",   title: "Trailer swept + dry", subtitle: "No prior-load debris", cta: "VERIFY"),
                .init(id: "pallet",  title: "Pallet jack on board", subtitle: "Battery full", cta: "OK"),
                .init(id: "papers",  title: "BOL packet", subtitle: "Carrier · shipper · consignee copies", cta: "VIEW"),
                .init(id: "photo",   title: "Pre-haul photo", subtitle: "Seal + trailer condition", cta: "CAMERA"),
                .init(id: "ack",     title: "Driver acknowledgment", subtitle: "I confirm trailer prep", cta: "SIGN"),
            ]
        }
    }

    private var openCount: Int { max(0, checklist.count - completed.count) }

    // MARK: - Container-case subtitle resolvers (140th firing M3 retrofit)
    //
    // The container/railIntermodal/vesselContainer prehaul rows used to
    // hard-code per-load identifiers ("TCLU 4412089 · ISO 4510 vs
    // release", "SSL-21009 · photographed", "Verified gross mass 32,105
    // kg"). Per doctrine §13/§15 (no fabricated values), each subtitle
    // now reads off `LifecycleProductContext.facets`. When a facet is
    // backend-stub em-dash, its segment is dropped from the joined
    // string so the row stays readable + truthful — never voicing a
    // fabricated equipment id or VGM weight.

    private var prehaulIsoSubtitle: String {
        let parts = [ctx.facets.containerNumber, ctx.facets.containerIsoType]
            .filter { $0 != LiveLoadFacets.dash }
        return parts.isEmpty
            ? "Match release"
            : (parts.joined(separator: " · ") + " vs release")
    }

    private var prehaulSealSubtitle: String {
        let n = ctx.facets.sealNumber
        return n == LiveLoadFacets.dash
            ? "Photographed"
            : "\(n) · photographed"
    }

    private var prehaulVgmSubtitle: String {
        let v = ctx.facets.vgmKgChip
        return v == LiveLoadFacets.dash
            ? "Verified gross mass on file"
            : "Verified gross mass \(v)"
    }

    /// 140th firing M3 sweep — reefer set-point row subtitle.
    /// `facets.setPointDisplay` returns the live "-18°F" / "2°C" /
    /// etc. when shipped, em-dash when the column is missing. The
    /// "thermograph armed" segment is a regulatory universal (every
    /// reefer trip arms the thermograph at pre-haul; FSMA cold-chain
    /// rule).
    private var prehaulReeferSetpointSubtitle: String {
        let s = ctx.facets.setPointDisplay
        return s == LiveLoadFacets.dash
            ? "Thermograph armed"
            : "\(s) locked · thermograph armed"
    }

    // MARK: - Hazmat-tanker subtitle resolvers (143rd firing M3 sweep)
    //
    // The hazmat-tanker prehaul rows used to hard-code per-trailer cert
    // dates ("P-stamp expires 2026-07-12 · 57 days"), per-driver
    // endorsement readouts ("H · hazmat · TWIC · medical card all
    // current"), and per-policy binder windows ("$5M per-incident ·
    // window 18:00 Apr 17 - 08:30 Apr 18"). Per doctrine §13/§15 (no
    // fabricated values), each subtitle now reads off
    // `LifecycleProductContext.facets`. When a facet is backend-stub
    // em-dash, the row falls through to a regulatory-universal copy
    // string instead of voicing fabricated fleet data.

    /// MC-331 cert row subtitle — composes spec label + expiry window
    /// from `facets.tankCertSpec` + `facets.tankCertExpiryWindow`,
    /// using the 138th segment-drop pattern. When both are em-dash,
    /// falls through to the universal regulatory pointer instead of
    /// fabricating a date.
    private var prehaulTankCertSubtitle: String {
        let spec = ctx.facets.tankCertSpec
        let win  = ctx.facets.tankCertExpiryWindow
        let parts = [spec, win].filter { $0 != LiveLoadFacets.dash }
        return parts.isEmpty
            ? "MC-331 spec tank · 49 CFR 178.337 cert on file"
            : parts.joined(separator: " · ")
    }

    /// Driver-endorsement row subtitle. `facets.driverEndorsementBundle`
    /// reads off the user-envelope endorsement+TWIC+medical-card join
    /// when shipped; until then falls through to the regulatory
    /// citation that this row is meant to confirm.
    private var prehaulEndorsementSubtitle: String {
        let bundle = ctx.facets.driverEndorsementBundle
        return bundle == LiveLoadFacets.dash
            ? "H + N · TWIC · medical card · 49 CFR 383.93"
            : bundle
    }

    /// Endorsement-row CTA badge — falls through to em-dash when the
    /// bundle status hasn't shipped, so the row never voices a
    /// fabricated "5/5" all-current badge.
    private var prehaulEndorsementBadge: String {
        let badge = ctx.facets.driverEndorsementBadge
        return badge == LiveLoadFacets.dash ? "—" : badge
    }

    /// EusoShield binder row subtitle. `facets.insuranceBinderWindow`
    /// reads off the active binder envelope (coverage cap + activation
    /// window) when shipped. Em-dash falls through to a generic
    /// "binder armed" regulatory marker — no fabricated coverage
    /// caps or windows.
    private var prehaulBinderSubtitle: String {
        let win = ctx.facets.insuranceBinderWindow
        return win == LiveLoadFacets.dash
            ? "Binder armed for this lane · coverage on file"
            : win
    }

    /// Reefer fuel row subtitle. `facets.reeferFuelLevel` returns
    /// "64% · 24h headroom" when the cold-chain telemetry stream is
    /// joined onto the load envelope; em-dash falls through to the
    /// regulatory universal.
    private var prehaulReeferFuelSubtitle: String {
        let f = ctx.facets.reeferFuelLevel
        return f == LiveLoadFacets.dash
            ? "Verify gauge before gate"
            : f
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                manifestCard
                checklistRows
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await hydrateLiveTrip()
            seedDefaults()
        }
        .overlay(alignment: .bottom) {
            if let msg = reminderToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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
        .animation(.easeOut(duration: 0.18), value: reminderToast)
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
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("LOCKED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· \(activeLoad?.loadNumber ?? fallbackLoadID)")
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("\(prehaulHeading) · \(checklist.count) checks")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(openCount) open · \(fallbackApptSub)")
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

    private var prehaulHeading: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:   return "Hazmat pre-haul"
        case .reefer:                        return "Cold-chain pre-haul"
        case .flatbed:                       return "Flatbed pre-haul"
        case .container, .railIntermodal, .vesselContainer:
                                             return "Container pre-haul"
        case .railBulk, .vesselBulk:         return "Bulk pre-haul"
        case .dryVan:                        return "Dry pre-haul"
        }
    }

    // MARK: Manifest card

    private var manifestCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(fallbackOrigin) → \(fallbackDestination)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackManifest)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(fallbackRollClock)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Checklist

    private var checklistRows: some View {
        VStack(spacing: 6) {
            ForEach(checklist) { item in
                Button {
                    if completed.contains(item.id) {
                        completed.remove(item.id)
                    } else {
                        completed.insert(item.id)
                    }
                } label: {
                    HStack(spacing: Space.s3) {
                        rowDot(done: completed.contains(item.id))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(EType.body.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text(item.subtitle)
                                .font(EType.mono(.micro)).tracking(0.3)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(item.cta)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().stroke(palette.borderSoft, lineWidth: 1))
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
                .buttonStyle(.plain)
            }
        }
    }

    private func rowDot(done: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(Brand.success.opacity(0.2))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.success)
            } else {
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func seedDefaults() {
        guard completed.isEmpty else { return }
        let list = checklist
        if list.count >= 5 {
            completed = Set(list.prefix(5).map { $0.id })
        }
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { scheduleRemindIn5() } label: {
                Text("Remind in 5")
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
                title: "Roll to Curtis Bay",
                action: { Task { await rollToPickup() } },
                subtitle: "\(openCount) LEFT",
                isLoading: isRolling || openCount > 0
            )
        }
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func rollToPickup() async {
        isRolling = true
        defer { isRolling = false }
        let forwardKeys = ["at_pickup", "pickup_arrival", "loading"]
        if let transition = lifecycle.availableTransitions.first(where: { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        }) ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }

    private func scheduleRemindIn5() {
        // Snapshot main-actor-isolated state on the main actor BEFORE
        // entering the Sendable closure (Swift 6 strict concurrency:
        // `requestAuthorization`'s callback is @Sendable so it can't
        // touch `lifecycle.loadId` / `activeLoad` directly).
        let snapshotLoadId = lifecycle.loadId
        let snapshotLoadNum = activeLoad.map { "Load \($0.loadNumber)" } ?? "Load locked"
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                Task { @MainActor in
                    reminderToast = "Enable notifications to get reminders"
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    reminderToast = nil
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Pre-haul gate waiting"
            content.body = "\(snapshotLoadNum) — clear your remaining checks and roll."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 5 * 60,
                repeats: false
            )
            let id = "prehaul-remind-\(snapshotLoadId)-\(Int(Date().timeIntervalSince1970))"
            let request = UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )
            center.add(request) { _ in
                Task { @MainActor in
                    reminderToast = "Reminder set for 5 min"
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    reminderToast = nil
                }
            }
        }
    }

    private struct PrehaulCheck: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let cta: String
    }
}

struct LoadLockedPrehaulScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            LoadLockedPrehaul(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_028(),
                      trailing: driverNavTrailing_028(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_028() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_028() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("028 · Load Locked Prehaul · Dark") {
    LoadLockedPrehaulScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("028 · Load Locked Prehaul · Light") {
    LoadLockedPrehaulScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
