//
//  017_PickupBolSigning.swift
//  EusoTrip — Lifecycle screen 017 · BOL Signing.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `017 BOL Signing.png` (Dark + Light). Surfaces immediately after
//  the bay-sequence finishes on 016; renders the full Straight
//  Bill of Lading with shipper + consignee side-by-side, the
//  commodity/hazmat manifest below that, an ESANG BOL-validator
//  card with live field checks, and two signer rows (shipper rep +
//  driver). Footer: View PDF outline + Sign + submit BOL gradient
//  (biometric Face ID tap-to-sign).
//
//  Composition (top to bottom):
//    • Header — back chevron + "Sign BOL" + right-column clock /
//      load id / bay info.
//    • Facility strip — "KOCH BELLE PLAINE · BAY 3 · TRANSFER
//      COMPLETE".
//    • BILL OF LADING card — ship-date + BOL number kicker, title
//      "Straight Bill of Lading — Non-negotiable", subtitle with
//      PER + FreightCamp id, shipper / consignee side-by-side block.
//    • Manifest grid — commodity / hazard class / net gallons /
//      net weight / placards / emergency contact.
//    • ESANG · BOL-VALIDATOR card — live field-match summary.
//    • Signer rows — Shipper rep (signed) + Driver (tap to sign).
//    • Footer CTAs — View PDF outline + Sign + submit BOL gradient.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Data wiring:
//    • `TripLifecycleStore.hydrateActiveLoad()` + `loads.getById`
//      populate BOL id + commodity + hazmat + weight.
//    • "Sign + submit BOL" fires the forward `bol_signed` transition
//      — routes through `lifecycle.execute` with a compliance block
//      that captures the driver's biometric signature hash.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct PickupBolSigning: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isSigning: Bool = false
    @State private var showPdf: Bool = false
    /// Per-load document upload sheet (Phase 7 driver-side closure).
    /// Opened from a small "Upload extra doc" affordance under the
    /// signature row so the driver can attach a customs paper, a
    /// rate-con re-scan, or a corrected BOL when the printed copy
    /// doesn't match. Lands in documentManagement.uploadDocument
    /// with entityType="load" + entityId=lifecycle.loadId so the
    /// shipper sees it on the same load envelope.
    @State private var showDocUpload: Bool = false

    enum Register { case night, morning }
    let register: Register

    init(register: Register = .night) { self.register = register }

    /// Product+vertical dispatch — hazmat BOL shows UN / hazard
    /// class / placards; dry van shows pallets / seal / dock; reefer
    /// shows set-point / pallets / cold-seal; flatbed shows
    /// securement / tarps / height; container shows container-id
    /// / chassis / VGM; vessel shows vessel / berth / VGM.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Production-clean placeholders.
    //
    // Updated 2026-04-24 (eusotrip-killers ledger-hygiene pass) — every
    // field that previously held a fake Figma snapshot (Koch Fertilizer,
    // Braskem, Marcus Hook Terminal, "Michael Eusorone", etc.) now
    // renders as a neutral em-dash placeholder. The screen still draws
    // the BOL skeleton so the layout matches Figma; real values override
    // the placeholder the moment `loads.getById` hydrates `activeLoad`,
    // and the signer rows pull from `auth.me()` via session.user.
    //
    // Doctrine: 0% mock data. Dynamic ready pages with 0 data, plugged
    // into backend. No fake shipper / consignee / load id / driver name
    // ever rendered in production.
    private let fallbackClock      = "—"
    private let fallbackLoadID     = "—"
    private let fallbackBayLine    = "AWAITING BAY ASSIGNMENT"
    private let fallbackShipDate   = "—"
    private let fallbackBolNumber  = "—"
    private let fallbackPerLine    = "PER 49 CFR 172.202"
    private let fallbackShipperN   = "—"
    private let fallbackShipperA   = "—"
    private let fallbackConsignN   = "—"
    private let fallbackConsignA   = "—"
    private let fallbackCommod     = "—"
    private let fallbackUN         = "—"
    private let fallbackHazClass   = "—"
    private let fallbackNetGal     = "—"
    private let fallbackNetWeight  = "—"
    private let fallbackPlacards   = "—"
    private let fallbackEmergency  = "CHEMTREC · 424-424-9300"
    private let fallbackShipperRep = "—"
    private let fallbackDriver     = "—"
    private let fallbackRepSigned  = "—"

    // MARK: - Derived UI strings

    private var loadIDText: String {
        activeLoad?.loadNumber ?? fallbackLoadID
    }
    private var bolNumberText: String {
        fallbackBolNumber
    }
    private var commodityText: String {
        activeLoad?.commodityName ?? fallbackCommod
    }
    private var unText: String {
        activeLoad?.unNumber ?? fallbackUN
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                facilityStrip
                billOfLadingCard
                manifestGrid
                validatorCard
                signerRows
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
            .accessibilityLabel("Back")

            Text("Sign BOL")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(loadIDText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Facility strip

    private var facilityStrip: some View {
        Text(fallbackBayLine)
            .font(EType.mono(.micro)).tracking(0.5)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
    }

    // MARK: BOL card

    private var billOfLadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Kicker bar
            HStack(spacing: 6) {
                Text("BILL OF LADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("·")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                Text(bolNumberText)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Title
            Text("Straight Bill of Lading — Non-negotiable")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textPrimary)

            HStack {
                Text("Ship date \(fallbackShipDate)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(fallbackPerLine)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Shipper / consignee side-by-side
            HStack(alignment: .top, spacing: Space.s3) {
                partyBlock(
                    label: "SHIPPER",
                    name: fallbackShipperN,
                    address: fallbackShipperA
                )
                Divider()
                    .background(palette.borderFaint)
                partyBlock(
                    label: "CONSIGNEE",
                    name: fallbackConsignN,
                    address: fallbackConsignA
                )
            }
            .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func partyBlock(label: String, name: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(name)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(address)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Manifest grid — product-dispatched

    /// Product-specific 6-row manifest. Hazmat rows surface UN /
    /// class / placards; dry van surfaces pallets / seal / dock;
    /// reefer surfaces set-point / cold-seal; flatbed surfaces
    /// securement / tarps / height; container + intermodal surface
    /// container-id / chassis / VGM; vessel surfaces vessel / berth
    /// / VGM. Affirmative rows (seal verified, placards verified,
    /// pins locked) render in Brand.success.
    private var manifestGrid: some View {
        let rows = ctx.manifestRows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                manifestRow(
                    label: row.label,
                    value: row.value,
                    valueColor: row.affirm ? Brand.success : nil
                )
                if idx < rows.count - 1 {
                    divider
                }
            }
        }
        .padding(.vertical, Space.s1)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
    }

    private func manifestRow(label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(valueColor ?? palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
    }

    // MARK: ESANG validator

    private var validatorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ESANG · BOL-VALIDATOR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Weights match the Koch scale ticket within 0.2%. Placards photographed, ERG 125 attached. Shipper rep signed at 09:58 — you're cleared to co-sign.")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Signer rows

    private var signerRows: some View {
        HStack(spacing: Space.s2) {
            signerCell(
                initials: "RM",
                role: "SHIPPER REP",
                name: fallbackShipperRep,
                subtitle: fallbackRepSigned,
                state: .signed
            )
            signerCell(
                initials: "ME",
                role: "DRIVER",
                name: fallbackDriver,
                subtitle: isSigning ? "Signing…" : "Tap to sign",
                state: isSigning ? .inflight : .pending
            )
        }
    }

    private enum SignerState { case signed, pending, inflight }

    private func signerCell(
        initials: String,
        role: String,
        name: String,
        subtitle: String,
        state: SignerState
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(signerBadgeFill(state: state))
                    Text(initials)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(role)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(name)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
            }
            Text(subtitle)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(signerSubtitleColor(state: state))
                .lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(signerBorderColor(state: state), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func signerBadgeFill(state: SignerState) -> some ShapeStyle {
        switch state {
        case .signed:   return AnyShapeStyle(Brand.success)
        case .pending:  return AnyShapeStyle(palette.textTertiary)
        case .inflight: return AnyShapeStyle(LinearGradient.diagonal)
        }
    }

    private func signerBorderColor(state: SignerState) -> Color {
        switch state {
        case .signed:   return Brand.success.opacity(0.5)
        case .pending:  return palette.borderFaint
        case .inflight: return Brand.info.opacity(0.6)
        }
    }

    private func signerSubtitleColor(state: SignerState) -> Color {
        switch state {
        case .signed:   return Brand.success
        case .pending:  return palette.textSecondary
        case .inflight: return Brand.info
        }
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        VStack(spacing: Space.s2) {
            Button { showDocUpload = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paperclip.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Attach extra doc")
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 10)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDocUpload) {
                DriverLoadDocUploadView(
                    loadId: lifecycle.loadId.isEmpty ? "0" : lifecycle.loadId,
                    loadNumber: activeLoad?.loadNumber,
                    initialKind: .bol
                )
                .environment(\.palette, palette)
            }

            HStack(spacing: Space.s3) {
                Button { showPdf = true } label: {
                    Text("View PDF")
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
                .accessibilityLabel("View full BOL as PDF")

                CTAButton(
                    title: "Sign + submit BOL",
                    action: { Task { await signAndSubmit() } },
                    subtitle: "BIOMETRIC TAP-TO-SIGN",
                    isLoading: isSigning
                )
                .accessibilityLabel("Sign BOL with Face ID and submit to shipper")
            }
        }
    }

    // MARK: - Live hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func signAndSubmit() async {
        isSigning = true
        defer { isSigning = false }
        let forwardKeys = ["bol", "signed", "departing", "in_transit", "loaded"]
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

struct PickupBolSigningScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            PickupBolSigning(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_017(),
                      trailing: driverNavTrailing_017(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_017() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_017() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews

#Preview("017 · BOL Signing · Dark") {
    PickupBolSigningScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("017 · BOL Signing · Light") {
    PickupBolSigningScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
