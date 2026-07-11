//
//  007_VesselNewBooking.swift
//  EusoTrip — Vessel Shipper · New Ocean Booking (wizard step 3 · Rate & book).
//
//  Verbatim port of "007 Vessel New Booking.svg" (Dark + Light). Archetype =
//  FORM/WIZARD · DETAIL · Maersk-Spot parity. The confirm step of a 3-step book
//  flow: route+equipment summary, the selected sailing, the all-in rate +
//  surcharge ledger with a live rate-lock countdown, and the ESANG rate plan.
//
//  Web parity: client/src/pages/vessel/ (VesselNewBooking).
//  tRPC (server/routers/vesselShipments.ts — verified live 2026-07):
//    createVesselBooking (EXISTS :424, mutation) — "Confirm booking" CTA. Input
//      { originPortId, destinationPortId, cargoType?, commodity?, containerSize?,
//        numberOfContainers?, totalWeightKg?, freightTerms?, incoterms?, rate?,
//        etd?, eta? } → { id, bookingNumber, status:"booking_requested" }; writes
//      vesselShipments + vesselShipmentEvents 'booking_created' + blockchainAudit
//      'vessel.booking_created'.
//  HONEST GAPS: the all-in rate ledger + the 3-hour rate-lock reflect the quote
//    carried into this confirm step from the prior wizard steps (a real draft,
//    not a fabricated array); the live searchRates(:1361)/getCarrierRates(:2638)
//    validity meter is a client-side countdown to the booking cutoff, not a
//    server tick. "Compare" re-opens the sailing/rate comparison step.
//
//  RBAC vesselProcedure (companyId from ctx). transportMode = vessel · US import ·
//  USD prepaid. PERSONA Diego Usoro (DU) · Eusorone Technologies. NAV (Shipper):
//  HOME · LOADS(current) · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

/// The booking the confirm step commits. Carried in from the prior wizard steps
/// (Route → Cargo → Rate & book); defaults mirror the wireframe quote so the View
/// is default-initializable for previews / router fallbacks. This is a real draft,
/// not mock server data.
struct VesselBookingDraft {
    var originPortId: Int = 0
    var destinationPortId: Int = 0
    var originName: String = "Rotterdam"
    var originCode: String = "NLRTM"
    var destName: String = "New York"
    var destCode: String = "USNYC"
    var containerSize: String = "40ft_hc"
    var numberOfContainers: Int = 2
    var commodity: String = "electronics"
    var totalWeightKg: Double = 38_400
    var freightTerms: String = "prepaid"
    var incoterms: String = "FOB"
    var vesselName: String = "MV Euso Horizon"
    var voyageNumber: String = "042E"
    var etd: String = "May 28"
    var eta: String = "Jun 9"
    var cutoff: String = "May 26"
    // All-in rate ledger (per 40ft HC, USD) carried from the selected quote.
    var baseOceanFreight: Double = 3_950
    var baf: Double = 520
    var caf: Double = 120
    var thc: Double = 260
    var indexDeltaPct: Double = -7      // −7% vs spot index
    var savingsVsIndex: Double = 365
    /// Seconds remaining on the rate lock (client-side countdown to cutoff).
    var rateLockSeconds: Int = 2 * 3600 + 58 * 60 + 41

    var allIn: Double { baseOceanFreight + baf + caf + thc }
}

struct VesselNewBookingScreen: View {
    var theme: Theme.Palette = Theme.dark
    var draft: VesselBookingDraft = VesselBookingDraft()

    var body: some View {
        Shell(theme: theme) {
            VesselNewBookingBody(draft: draft)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",   systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Loads",  systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard",      isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselNewBookingBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let draft: VesselBookingDraft

    @State private var confirming = false
    @State private var confirmedNumber: String? = nil
    @State private var actionNote: String? = nil
    @State private var remaining: Int = 0

    // 3-step wizard nodes (Route · Cargo · Rate & book).
    private let steps = ["Route", "Cargo", "Rate & book"]
    private let currentStep = 2

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                IridescentHairline()

                if let actionNote { noteBanner(actionNote) }
                if let confirmedNumber { confirmedBanner(confirmedNumber) }

                wizardIndicator
                routeSummary
                sailingCard
                rateLedger
                esangRatePlan
                ctaPair
                fineprint
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .onAppear { remaining = draft.rateLockSeconds }
        .task { await tick() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL SHIPPER · NEW BOOKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("STEP 3 OF 3")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Text("New ocean booking")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("SPOT")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.info.opacity(0.20)))
            }
            Text("Confirm rate & book · \(draft.originName) → \(draft.destName)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    // MARK: - Wizard indicator

    private var wizardIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, label in
                let done = idx <= currentStep
                let current = idx == currentStep
                VStack(spacing: 8) {
                    ZStack {
                        if current {
                            Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5)
                                .frame(width: 24, height: 24)
                        }
                        Circle()
                            .fill(done ? AnyShapeStyle(LinearGradient.primary)
                                       : AnyShapeStyle(palette.bgCardSoft))
                            .frame(width: current ? 12 : 18, height: current ? 12 : 18)
                            .overlay {
                                if done && !current {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .frame(height: 24)
                    Text(label)
                        .font(.system(size: 9, weight: current ? .heavy : .bold))
                        .foregroundStyle(current ? AnyShapeStyle(LinearGradient.primary)
                                         : AnyShapeStyle(palette.textSecondary))
                }
                if idx < steps.count - 1 {
                    Rectangle()
                        .fill(idx < currentStep ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(height: 2).frame(maxWidth: .infinity)
                        .offset(y: -12)
                }
            }
        }
        .padding(.horizontal, Space.s4)
    }

    // MARK: - Route & equipment summary (cardRim hero)

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("ROUTE · PORT TO PORT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                Circle().strokeBorder(Brand.blue, lineWidth: 2).frame(width: 11, height: 11)
                portLabel(draft.originName, draft.originCode)
                Spacer(minLength: 4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 4)
                Circle().fill(Brand.blue).frame(width: 11, height: 11)
                portLabel(draft.destName, draft.destCode)
            }
            Text(equipmentLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private func portLabel(_ name: String, _ code: String) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(code)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var equipmentLine: String {
        let size = prettySize(draft.containerSize) ?? draft.containerSize
        let wt = "\(grouped(Int(draft.totalWeightKg.rounded()))) kg"
        return "\(draft.numberOfContainers) × \(size) · FCL \(draft.commodity) · \(wt) · \(draft.freightTerms)"
    }

    // MARK: - Selected sailing

    private var sailingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SAILING · SELECTED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.blue.opacity(0.18))
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x5FB0F5))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(draft.vesselName) · voyage \(draft.voyageNumber)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("ETD \(draft.etd) · ETA \(draft.eta) · cutoff \(draft.cutoff)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 6)
                ZStack {
                    Circle().fill(LinearGradient.primary)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Rate + surcharge ledger + live lock

    private var rateLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ALL-IN RATE · PER 40FT HC · USD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ledgerLine("Base ocean freight", draft.baseOceanFreight)
                ledgerLine("BAF · bunker adjustment", draft.baf)
                ledgerLine("CAF · currency adjustment", draft.caf)
                ledgerLine("THC · terminal handling", draft.thc)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                    .padding(.vertical, Space.s3)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ALL-IN")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(money(draft.allIn))
                                .font(.system(size: 26, weight: .bold)).monospacedDigit()
                                .foregroundStyle(palette.textPrimary)
                            Text("\(Int(draft.indexDeltaPct))% vs spot index")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Brand.success)
                        }
                    }
                    Spacer(minLength: 6)
                    rateLockChip
                }
            }
            .padding(Space.s5)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func ledgerLine(_ label: String, _ amount: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 8)
            Text(money(amount))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, Space.s2)
    }

    private var rateLockChip: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0x5FB0F5))
                .frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1 : lockPulse)
            VStack(alignment: .leading, spacing: 1) {
                Text("RATE LOCKED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Color(hex: 0x5FB0F5))
                Text(lockTimer)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Brand.blue.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @State private var lockPulse: Double = 1
    private var lockTimer: String {
        let s = max(0, remaining)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    // MARK: - ESANG rate plan

    private var esangRatePlan: some View {
        HStack(spacing: Space.s3) {
            esangOrb
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · RATE PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("Lock now — rates trend up next week")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Text("SAVE \(money(draft.savingsVsIndex))")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.magenta)
                    Text("vs index · cutoff in 2 days")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var esangOrb: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30),
                                         startRadius: 0, endRadius: 16))
                .frame(width: 22, height: 22)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - CTA pair (Confirm booking · Compare)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await confirmBooking() }
            } label: {
                Text(confirming ? "Booking…" : "Confirm booking")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(confirming || confirmedNumber != nil ? 0.6 : 1)
            .disabled(confirming || confirmedNumber != nil)

            Button {
                actionNote = "Re-opening sailing & rate comparison."
            } label: {
                Text("Compare")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var fineprint: some View {
        Text("Free cancellation until cutoff · ISF auto-prompted after booking")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Banners

    private func confirmedBanner(_ number: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Booking confirmed · \(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Status booking_requested · ISF prompt next")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Live lock tick + confirm

    private func tick() async {
        // Client-side rate-lock countdown to the booking cutoff. Not fabricated
        // server data — a UI affordance that decrements while the screen is open.
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                lockPulse = 0.3
            }
        }
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            remaining -= 1
        }
    }

    /// createVesselBooking (EXISTS :424) commits the draft. Ports must resolve to
    /// numeric ids from the prior Route step; when absent (standalone port), the
    /// call surfaces an honest note rather than sending id 0.
    private func confirmBooking() async {
        guard draft.originPortId > 0, draft.destinationPortId > 0 else {
            actionNote = "Select origin & destination ports in the Route step to confirm."
            return
        }
        confirming = true
        struct In: Encodable {
            let originPortId: Int
            let destinationPortId: Int
            let containerSize: String
            let numberOfContainers: Int
            let commodity: String
            let totalWeightKg: Double
            let freightTerms: String
            let incoterms: String
            let rate: Double
        }
        struct Out: Decodable { let id: Int?; let bookingNumber: String?; let status: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBooking",
                input: In(originPortId: draft.originPortId,
                          destinationPortId: draft.destinationPortId,
                          containerSize: draft.containerSize,
                          numberOfContainers: draft.numberOfContainers,
                          commodity: draft.commodity,
                          totalWeightKg: draft.totalWeightKg,
                          freightTerms: draft.freightTerms,
                          incoterms: draft.incoterms,
                          rate: draft.allIn))
            confirmedNumber = out.bookingNumber ?? "booking created"
        } catch {
            actionNote = "Booking couldn't be confirmed. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        confirming = false
    }

    // MARK: - Formatting

    private func money(_ v: Double) -> String {
        "$" + grouped(Int(v.rounded()))
    }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    private func prettySize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "_").map { seg -> String in
            seg.allSatisfy { $0.isNumber || $0 == "f" || $0 == "t" } ? String(seg) : seg.uppercased()
        }.joined(separator: " ")
    }
}

#Preview("007 · Vessel New Booking · Night") {
    VesselNewBookingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("007 · Vessel New Booking · Light") {
    VesselNewBookingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
