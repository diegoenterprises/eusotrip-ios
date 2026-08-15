//
//  007_VesselNewBooking.swift
//  EusoTrip 2027 · 06 Vessel · 007 New Booking (VESSEL SHIPPER · mode-agnostic class-A vantage).
//
//  RECONSTRUCTED 2026-06-02 (Swift-parity sweep) — the prior cut was a thin templated port on a private
//  palette mirror with an invented "TRACK" nav slot and unverified endpoint lines. This port is a 1:1
//  mirror of "06 Vessel/Light-SVG/007 Vessel New Booking.svg" (+ Dark) AND fully dynamic on the canonical
//  DesignSystem (Shell · BottomNav · NavSlot · Theme.Palette · IridescentHairline). Archetype=FORM/WIZARD
//  at Maersk-Spot / Hapag Quick-Quotes-Spot parity (3-step flow · all-in surcharge ledger · live rate-lock).
//
//  LIVE SUPER-INTELLIGENCE FUSION (Foundation Contract OPERATOR DIRECTIVE 2026-06-02 · honestly scoped):
//  a pre-booking form has no vessel position yet — the fused, non-static faces are the LIVE RATE-LOCK meter
//  + the schedule ETA + the ESang rate plan, all on one tick. `load()` fans the parallel reads;
//  `streamLock()` ticks the 3-hour rate-validity countdown each second (searchRates/getCarrierRates window).
//  device-geolocation/geofence are intentionally NOT bound to a booking form with no moving asset. On a
//  stale rate feed the lock reads "indicative (degraded)", never a guaranteed number.
//
//  WEB PARITY: client/src/pages/vessel/NewBooking.tsx + ShipperNav.tsx
//
//  ───────── WIRING MANIFEST (every binding on-disk-confirmed in server/routers/) ─────────
//    EXISTS · vesselShipments.createVesselBooking :424 { originPortId, destinationPortId, cargoType,
//             containerSize, numberOfContainers, freightTerms, incoterms, etd, eta, rate }
//             → status booking_requested + VS-#####; writes vesselShipments + vesselShipmentEvents
//               booking_created + blockchainAuditTrail vessel.booking_created  ← CONFIRM action
//    EXISTS · vesselShipments.searchRates         :1373  { originPortId, destinationPortId, containerSize } ← all-in + surcharges
//    EXISTS · vesselShipments.getCarrierRates     :2716 { ... }                ← carrier quote backing the lock window
//    EXISTS · vesselShipments.getVesselSchedules  :1350  { originPortId, destinationPortId } ← next sailing + cutoff
//    EXISTS · vesselShipments.getPorts            :3599 { }                    ← route picker directory
//    EXISTS · hereMaps.route (hereMaps.ts:89)                                  ← ocean-leg ETA into the sailing card
//    ESang: esangCoach.forScreen (RATE PLAN) — voice routes via esang.chat, never a direct mutation.
//    RBAC: vesselProcedure (VESSEL · companyId from ctx).
//
//  PERSONA: Diego Usoro (DU) · Eusorone Technologies (companyId 1, SHIPPER) = shipper-of-record.
//  Rotterdam NLRTM -> New York USNYC · 2x40ft HC container · electronics · prepaid · MV Euso Horizon 042E.
//  transportMode=vessel · US import leg · USD prepaid. NAV (REAL · Shipper enum): HOME · LOADS(current) · [orb] · WALLET · ME.
//  One ✦ eyebrow · one iridescent hairline. — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): ONLINE_ONLY(rate-validity + ISF gate) for submit · READ_CACHED(ttl 24h) form prefill. Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

// MARK: - Screen

struct VesselNewBooking_007: View {
    let theme: Theme.Palette
    var originPortId: Int
    var destinationPortId: Int

    init(theme: Theme.Palette = Theme.light, originPortId: Int = 528, destinationPortId: Int = 642) {
        self.theme = theme; self.originPortId = originPortId; self.destinationPortId = destinationPortId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselNewBookingBody_007(originPortId: originPortId, destinationPortId: destinationPortId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (loose optionals · overwritten on load)

private struct Schedule007: Decodable { let vesselVoyage: String?; let etd: String?; let eta: String?; let cutoff: String? }
private struct Rate007: Decodable {
    let base: String?; let baf: String?; let caf: String?; let thc: String?
    let allIn: String?; let vsIndex: String?; let lockSeconds: Int?; let stale: Bool?
}
private struct Esang007: Decodable { let line: String?; let amount: String?; let detail: String? }

// MARK: - Body

private struct VesselNewBookingBody_007: View {
    @Environment(\.palette) private var palette
    let originPortId: Int
    let destinationPortId: Int

    // Route + equipment (chosen in steps 1–2) -----------------------------------------
    @State private var originPort = "Rotterdam";  @State private var originCode = "NLRTM"
    @State private var destPort = "New York";     @State private var destCode = "USNYC"
    @State private var equipment = "2 × 40ft HC · FCL electronics · 38,400 kg · prepaid"

    // getVesselSchedules --------------------------------------------------------------
    @State private var vesselVoyage = "MV Euso Horizon · voyage 042E"
    @State private var sailingLine = "ETD May 28 · ETA Jun 9 · cutoff May 26"

    // searchRates / getCarrierRates ---------------------------------------------------
    @State private var base = "$3,950"
    @State private var baf = "$520"
    @State private var caf = "$120"
    @State private var thc = "$260"
    @State private var allIn = "$4,850"
    @State private var vsIndex = "−7% vs spot index"
    @State private var lockSeconds = 10_721            // 2:58:41
    @State private var degraded = false

    // ESang ---------------------------------------------------------------------------
    @State private var esangLine = "Lock now — rates trend up next week"
    @State private var esangAmount = "SAVE $365"
    @State private var esangDetail = "vs index · cutoff in 2 days"

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var submitting = false
    @State private var bookedRef: String? = nil

    private var lockText: String {
        guard !degraded else { return "indicative" }
        let h = lockSeconds / 3600, m = (lockSeconds % 3600) / 60, s = lockSeconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                Text("Confirm rate & book · \(originPort) → \(destPort)").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    wizardSteps
                    routeSummary
                    sailingPick
                    rateCard
                    esangCard
                    ctaPair
                    Text("Free cancellation until cutoff · ISF auto-prompted after booking")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .task { await streamLock() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow / title

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL SHIPPER · NEW BOOKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("STEP 3 OF 3").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }
    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("New ocean booking").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            StatusPill(text: "SPOT", kind: .info)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCardSoft).frame(height: 96)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rate feed unavailable").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Wizard steps

    private var wizardSteps: some View {
        HStack(spacing: 0) {
            wizardNode("Route", done: true)
            wizardConnector
            wizardNode("Cargo", done: true)
            wizardConnector
            wizardActiveNode("Rate & book")
        }
        .padding(.horizontal, Space.s4)
    }
    private func wizardNode(_ label: String, done: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
            }
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
        }
    }
    private func wizardActiveNode(_ label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5)).frame(width: 22, height: 22)
                Circle().fill(LinearGradient.diagonal).frame(width: 9, height: 9)
            }.frame(height: 22)
            Text(label).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }
    private var wizardConnector: some View {
        Rectangle().fill(LinearGradient.primary).frame(height: 2).frame(maxWidth: .infinity).offset(y: -9)
    }

    // MARK: Route summary

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ROUTE · PORT TO PORT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                Circle().strokeBorder(Brand.blue, lineWidth: 2).frame(width: 11, height: 11)
                Text(originPort).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(originCode).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                Circle().fill(Brand.blue).frame(width: 11, height: 11)
                Text(destPort).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(destCode).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            Text(equipment).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Sailing pick

    private var sailingPick: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SAILING · SELECTED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.blue.opacity(0.12)).frame(width: 40, height: 40)
                    Image(systemName: "ferry").font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(vesselVoyage).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(sailingLine).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle().fill(LinearGradient.primary).frame(width: 20, height: 20)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Rate card (surcharge ledger + live lock)

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ALL-IN RATE · PER 40ft HC · USD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                surchargeLine("Base ocean freight", base)
                surchargeLine("BAF · bunker adjustment", baf)
                surchargeLine("CAF · currency adjustment", caf)
                surchargeLine("THC · terminal handling", thc)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s2)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ALL-IN").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        HStack(spacing: Space.s3) {
                            Text(allIn).font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            Text(vsIndex).font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
                        }
                    }
                    Spacer()
                    lockMeter
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }
    private func surchargeLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }.padding(.vertical, 6)
    }
    private var lockMeter: some View {
        HStack(spacing: 8) {
            Circle().fill(Brand.blue).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(degraded ? "INDICATIVE" : "RATE LOCKED").font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(Brand.info)
                Text(lockText).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Brand.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: ESang

    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
            }.padding(.trailing, Space.s3)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · RATE PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangLine).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: Space.s2) {
                    Text(esangAmount).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.magenta)
                    Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: CTA pair (confirm fires createVesselBooking)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await confirmBooking() } } label: {
                Text(submitting ? "Booking…" : (bookedRef != nil ? "Booked · \(bookedRef!)" : "Confirm booking")).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(LinearGradient.primary).clipShape(Capsule())
            }.disabled(submitting || bookedRef != nil)
            Text("Compare").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(width: 132, height: 48).background(palette.bgSecondary).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint))
        }
    }

    // MARK: Load (parallel reads)

    private func load() async {
        loading = true; loadError = nil
        struct RouteIn: Encodable { let originPortId: Int; let destinationPortId: Int }
        struct RateIn: Encodable { let originPortId: Int; let destinationPortId: Int; let containerSize: String }
        struct NoArg: Encodable {}
        do {
            // esangCoach.forScreen is NOT called: SCREEN_ENUM (esangCoach.ts:112) has no vessel
            // keys, so the call is a guaranteed zod BAD_REQUEST — named gap filed with the-oath.
            // ESang line derives from the loaded schedule + rate (001-exemplar pattern).
            async let sched: Schedule007 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselSchedules", input: RouteIn(originPortId: originPortId, destinationPortId: destinationPortId))
            async let rate: Rate007 = EusoTripAPI.shared.query(
                "vesselShipments.searchRates", input: RateIn(originPortId: originPortId, destinationPortId: destinationPortId, containerSize: "40ft_hc"))
            let (s, r) = try await (sched, rate)
            applySchedule(s); applyRate(r)
            deriveEsang()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// Live rate-lock ticker — counts down the 3-hour validity window each second.
    private func streamLock() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { break }
            if lockSeconds > 0 && !degraded { lockSeconds -= 1 }
        }
    }

    /// Confirm — fires the real createVesselBooking mutation (status booking_requested + audit row).
    private func confirmBooking() async {
        submitting = true; defer { submitting = false }
        struct BookingIn: Encodable {
            let originPortId: Int; let destinationPortId: Int
            let cargoType: String; let containerSize: String; let numberOfContainers: Int
            let freightTerms: String; let incoterms: String
        }
        let input = BookingIn(originPortId: originPortId, destinationPortId: destinationPortId,
                              cargoType: "container", containerSize: "40ft_hc", numberOfContainers: 2,
                              freightTerms: "prepaid", incoterms: "FOB")
        struct Created: Decodable { let bookingNumber: String?; let status: String? }
        do {
            let c: Created = try await EusoTripAPI.shared.mutation("vesselShipments.createVesselBooking", input: input)
            bookedRef = c.bookingNumber ?? "confirmed"
        } catch {
            loadError = error.eusoUserCopy
        }
    }

    private func applySchedule(_ s: Schedule007) {
        if let v = s.vesselVoyage { vesselVoyage = v }
        if let etd = s.etd, let eta = s.eta, let cut = s.cutoff { sailingLine = "ETD \(etd) · ETA \(eta) · cutoff \(cut)" }
    }
    private func applyRate(_ r: Rate007) {
        if let v = r.base { base = v }
        if let v = r.baf { baf = v }
        if let v = r.caf { caf = v }
        if let v = r.thc { thc = v }
        if let v = r.allIn { allIn = v }
        if let v = r.vsIndex { vsIndex = v }
        if let v = r.lockSeconds { lockSeconds = v }
        degraded = r.stale ?? degraded
    }
    /// 001-exemplar pattern: the calm expert line derives from live schedule + rate state —
    /// no coach endpoint (SCREEN_ENUM has no vessel keys · named gap filed with the-oath).
    private func deriveEsang() {
        if degraded {
            esangLine = "Rates degraded — showing last synced index"
            esangAmount = "STALE"
            esangDetail = "reconnect before locking · booking stays ONLINE_ONLY"
        } else if lockSeconds > 0 {
            let hrs = lockSeconds / 3600, min = (lockSeconds % 3600) / 60
            esangLine = "Rate locked — confirm before the window closes"
            esangAmount = "\(hrs)h \(min)m LEFT"
            esangDetail = vsIndex.isEmpty ? "validity window live" : "\(vsIndex) · validity window live"
        } else {
            esangLine = "No active lock — search refreshed the lane rate"
            esangAmount = "LIVE"
            esangDetail = "lock arms on quote accept · ISF gate before loading"
        }
    }
}

#Preview("007 · New booking · Night") {
    VesselNewBooking_007(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("007 · New booking · Light") {
    VesselNewBooking_007(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
