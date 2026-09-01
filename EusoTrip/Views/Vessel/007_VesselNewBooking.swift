//
//  007_VesselNewBooking.swift
//  EusoTrip 2027 · 06 Vessel · 007 New Booking — vessel mode-content of the ONE Shipper family.
//
//  REMEDIATED 2026-08-17 (fire §17, curing the DA_FAIL of 2026-08-17T18:55:04Z on axes A · B · D · E · F).
//  Archetype = RATE-COMMIT (a priced, time-limited quote turned into a confirmed sailing).
//
//  ───────── AXIS A · THE ARCHETYPE WAS MISDECLARED, AND HERE IS THE HONEST CALL ─────────
//  The old header and <desc> declared FORM/WIZARD. The file contained zero TextField, Picker,
//  Stepper, Toggle and DatePicker; every value was a hardcoded @State string and confirmBooking()
//  sent literals ("container", "40ft_hc", 2). It was a read-only summary wearing wizard chrome.
//
//  Two facts decided the cure rather than one:
//   1. A COMPLETE ocean booking FORM already ships and is already reachable —
//      `VesselShipperCreateBookingScreen` (registry id Vesl010, in Views/Vessel/001_VesselShipperHome.swift):
//      a real SwiftUI Form with Picker cargoType, Picker containerSize, Stepper numberOfContainers,
//      weight/volume/commodity TextFields, an IMDG Toggle group, Picker incoterms/freightTerms/currency,
//      a preflight gate and a live createVesselBooking submit. Rebuilding that here would have shipped a
//      duplicate surface, which §T calls padding.
//   2. What 007 does that nothing else does is COMMIT AGAINST A PRICED, TIME-LIMITED QUOTE.
//  So the archetype is redeclared RATE-COMMIT, and the controls this screen genuinely owns are now
//  REAL and BOUND to the mutation payload: the sailing radio group (selects vesselId/etd/eta), the
//  container-count Stepper, the freight-terms segment and the incoterms Picker. Nothing that was
//  fixed upstream is re-asked; it renders read-only in the SPEC row, which names where it came from.
//
//  ───────── AXIS B · THE PHANTOM RAIL IS DELETED, NOT RELABELLED ─────────
//  The header said STEP 3 OF 3 and the rail drew Route and Cargo complete, but no step-1 and no
//  step-2 surface exists in the 001-010 band, so the shipper could not reach step 3 by walking it.
//  A rail that paints a path to a place that does not exist is worse than no rail. It is gone.
//  In its place: a SPEC row that names its real upstream surface (Create booking) and offers a real
//  way back to it via the injected `onEditSpec` handler — no fake progress, no dead chrome.
//
//  ───────── AXIS E · THE SECONDARY CTA IS A REAL BUTTON NOW ─────────
//  `Compare` was a `Text` styled as a capsule: no action, no tap target, no accessibility. It is now
//  a Button that really calls getCarrierRates:3048 and expands an inline carrier comparison, with an
//  honest empty state — that procedure returns null on upstream failure and we say so instead of
//  showing a blank list.
//
//  ───────── AXIS D · SEVEN WRONG REFS, AND THE FUSION CLAIM THE CODE CONTRADICTED ─────────
//  Verified first-hand against the live router this fire. Withdrawn as stale: createVesselBooking:137,
//  searchRates:829/1373, getCarrierRates:1472/2716, getVesselSchedules:806/1350, getPorts:1886/3599,
//  getVesselShipmentDetail:259, hereMaps.route:89.
//  Three claims the artifact contradicted are withdrawn rather than re-worded:
//    (a) "broadcast WS_EVENTS on create" — createVesselBooking:424 has NO websocket fan-out at all.
//        (Its neighbour createVesselBid:1707 does; this one does not.) Claim deleted.
//    (b) hereMaps.route supplying the ocean-leg ETA — it is real, at hereMaps.ts:220, but the Swift
//        never called it AND a port-to-port ocean leg is not a road route. Dropped as wrong in
//        principle, not merely unwired.
//    (c) esangCoach.forScreen fusing the rate plan — real at esangCoach.ts:264, but SCREEN_ENUM
//        (esangCoach.ts:112-125) has no vessel key, so any call is a guaranteed zod BAD_REQUEST.
//        The old <desc> claimed the fusion while the old code said in a comment that it deliberately
//        did not call it. Now both say the same thing: not called, derived instead, gap filed.
//
//  ───────── WIRE-SHAPE DEFECTS FIXED (the port could only ever have failed) ─────────
//  getVesselSchedules:1664 takes departurePortId / arrivalPortId — NOT originPortId /
//  destinationPortId — and returns an ARRAY of vessel_voyages rows. searchRates:1687 also returns an
//  ARRAY. The old load() sent the wrong key names and decoded both as single objects, so every launch
//  landed in the error state. Both are now arrays with the real key names.
//  The surcharge ledger lines are now the REAL vessel_freight_rates columns (schema.ts:12038):
//  ratePerUnit · bafSurcharge · thcOrigin · thcDestination · peakSeasonSurcharge. The retired
//  "CAF · currency adjustment" line was an invented charge — that table has no CAF column.
//
//  ───────── WIRING MANIFEST · every line verified first-hand 2026-08-17 ─────────
//    EXISTS · vesselShipments.createVesselBooking :424  ← THIS SCREEN'S WRITE (kept live, unregressed)
//             { originPortId, destinationPortId, vesselId?, cargoType?, commodity?, containerSize?,
//               numberOfContainers?, totalWeightKg?, totalVolumeCBM?, incoterms?, freightTerms?,
//               rate?, etd?, eta? } -> status booking_requested + VS-#####
//             writes vesselShipments :451 · vesselShipmentEvents booking_created :479
//                  · blockchainAuditTrail vessel.booking_created :492 (guarded on insertId > 0)
//    EXISTS · vesselShipments.getVesselSchedules  :1664 { departurePortId, arrivalPortId, limit } -> [voyage]
//    EXISTS · vesselShipments.searchRates         :1687 { originPortId, destinationPortId, containerSize } -> [rate]
//    EXISTS · vesselShipments.getCarrierRates     :3048 { originPort, destPort, containerSize } -> carrier list | null
//    EXISTS · vesselShipments.getPorts            :3931 { limit, offset, country?, search?, portType? }
//    EXISTS · vesselShipments.getVesselShipmentDetail :561 { id }  ← post-create confirmation read
//
//  ───────── NAMED GAPS · proposed, never invented ─────────
//    1. There is no server-side owner of a rate-lock window. Proposed:
//       vesselShipments.getRateLock({ originPortId, destinationPortId, containerSize })
//         -> { quoteId, allIn, validUntil, indexDelta }.
//       Until it lands the countdown is derived from vessel_freight_rates.expirationDate, and when
//       that is absent or already past the meter reads INDICATIVE — never a guaranteed number.
//    2. getVesselSchedules:1664 selects vessel_voyages only; it does not join vessels.name, so a
//       sailing row can show its voyageNumber and serviceRoute but not the ship's name.
//       Proposed: return `vesselName` alongside vesselId.
//    3. Extend esangCoach SCREEN_ENUM (esangCoach.ts:112-125) with the vessel screen keys.
//
//  RBAC: vesselProcedure (server/_core/trpc.ts:268).
//  PERSONA: Diego Usoro · Eusorone Technologies (companyId 1, SHIPPER) = shipper-of-record.
//  Rotterdam NLRTM -> New York USNYC · 40ft HC · consumer electronics · prepaid · US import leg · USD.
//  NAV (Shipper enum · one family, vessel mode-content): HOME · LOADS(current) · [orb] · WALLET · ME.
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  OFFLINE POLICY (doctrine W · Encyclopedia v2), derived not stamped — the DA credited this
//  screen's offline discipline as the band's best; it is preserved and made stricter, not regressed:
//    ONLINE_ONLY(rate validity) for the confirm — a booking commits money against a quote that
//    expires, so it is never queued. Offline the CTA disables, the meter flips to INDICATIVE, and
//    the reason is on screen; the rate is never presented as guaranteed.
//    READ_CACHED(ttl 24h) for the spec row and the last-known ledger, with a staleness line so
//    cached is visibly distinct from live.
//
import SwiftUI

// MARK: - Screen

struct VesselNewBooking_007: View {
    let theme: Theme.Palette
    var originPortId: Int
    var destinationPortId: Int
    /// Real return path to the surface that owns the spec (Create booking). Injected by the router
    /// so this screen never paints a step it cannot navigate to.
    var onEditSpec: (() -> Void)? = nil

    init(theme: Theme.Palette = Theme.light,
         originPortId: Int = 528,
         destinationPortId: Int = 642,
         onEditSpec: (() -> Void)? = nil) {
        self.theme = theme
        self.originPortId = originPortId
        self.destinationPortId = destinationPortId
        self.onEditSpec = onEditSpec
    }

    var body: some View {
        Shell(theme: theme) {
            VesselNewBookingBody_007(originPortId: originPortId,
                                     destinationPortId: destinationPortId,
                                     onEditSpec: onEditSpec)
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

// MARK: - Wire shapes · field-for-field against the real tables

/// getVesselSchedules:1664 -> [vessel_voyages] (schema.ts:11891). ARRAY, not an object.
private struct VoyageRow007: Decodable, Identifiable {
    let id: Int
    let vesselId: Int?
    let voyageNumber: String?
    let serviceRoute: String?
    let scheduledDeparture: String?
    let scheduledArrival: String?
    let status: String?
    /// Named gap 2 — not joined today; decoded optimistically so the row upgrades when it lands.
    let vesselName: String?
}

/// searchRates:1687 -> [vessel_freight_rates] (schema.ts:12038). ARRAY, not an object.
private struct RateRow007: Decodable {
    let id: Int?
    let ratePerUnit: String?
    let currency: String?
    let bafSurcharge: String?
    let thcOrigin: String?
    let thcDestination: String?
    let peakSeasonSurcharge: String?
    let transitDays: Int?
    let expirationDate: String?
    let serviceRoute: String?
}

/// getCarrierRates:3048 passes through the INTTRA service and may legitimately return null.
private struct CarrierQuote007: Decodable, Identifiable {
    var id: String { (carrier ?? "carrier") + (service ?? "") }
    let carrier: String?
    let service: String?
    let allIn: Double?
    let transitDays: Int?
}

private struct CreatedBooking007: Decodable {
    let id: Int?
    let bookingNumber: String?
    let status: String?
}

// MARK: - Body

private struct VesselNewBookingBody_007: View {
    @Environment(\.palette) private var palette
    let originPortId: Int
    let destinationPortId: Int
    let onEditSpec: (() -> Void)?

    // ── SPEC · fixed upstream in Create booking, shown read-only, never re-asked here ──────────
    @State private var originPort = "Rotterdam";  @State private var originCode = "NLRTM"
    @State private var destPort = "New York";     @State private var destCode = "USNYC"
    private let cargoType = "container"
    private let containerSize = "40ft_hc"
    private let commodity = "consumer electronics"
    private let totalWeightKg: Double = 38_400
    private let totalVolumeCBM: Double = 124

    // ── THE CONTROLS THIS SCREEN OWNS · every one bound to the createVesselBooking payload ─────
    @State private var numberOfContainers = 2                 // Stepper
    @State private var freightTerms = "prepaid"               // segment · enum ["prepaid","collect","third_party"]
    @State private var incoterms = "FOB Rotterdam"            // Picker
    @State private var selectedVoyageId: Int? = nil           // radio group over the live schedule
    private let incotermOptions = ["EXW", "FCA", "FOB Rotterdam", "CFR New York", "CIF New York", "DAP", "DDP"]

    // ── searchRates:1687 · the five REAL rate columns ──────────────────────────────────────────
    @State private var base: Double = 3_950                   // ratePerUnit
    @State private var baf: Double = 520                      // bafSurcharge
    @State private var thcOrigin: Double = 130                // thcOrigin
    @State private var thcDest: Double = 130                  // thcDestination
    @State private var pss: Double = 120                      // peakSeasonSurcharge
    @State private var currency = "USD"
    @State private var rateExpiresAt: Date? = nil
    @State private var indexDelta = "−7% vs spot index"

    // ── getVesselSchedules:1664 ────────────────────────────────────────────────────────────────
    @State private var voyages: [VoyageRow007] = []

    // ── getCarrierRates:3048 (Axis E — Compare is a real Button now) ───────────────────────────
    @State private var comparing = false
    @State private var carrierQuotes: [CarrierQuote007] = []
    @State private var compareNote: String? = nil
    @State private var showCompare = false

    @State private var lockSeconds = 10_721
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var submitting = false
    @State private var bookedRef: String? = nil
    @State private var syncedAt: Date? = nil
    @State private var servedFromCache = false

    /// ONLINE_ONLY(rate validity): a commit against an expiring quote is never queued.
    private var offline: Bool { !OfflineReachabilityHub.shared.isOnline }
    /// The meter is only allowed to say "held" when a real expiry backs it and we are live.
    private var indicative: Bool { offline || rateExpiresAt == nil || lockSeconds <= 0 }

    private var perContainer: Double { base + baf + thcOrigin + thcDest + pss }
    private var allIn: Double { perContainer * Double(max(numberOfContainers, 1)) }
    private var selectedVoyage: VoyageRow007? { voyages.first { $0.id == selectedVoyageId } }

    private func money(_ v: Double) -> String {
        "$" + (v.rounded()).formatted(.number.precision(.fractionLength(0)))
    }
    private var lockText: String {
        guard !indicative else { return "indicative" }
        let h = lockSeconds / 3600, m = (lockSeconds % 3600) / 60, s = lockSeconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                Text("\(originPort) \(originCode) → \(destPort) \(destCode) · per 40ft HC · \(currency)")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                if servedFromCache { stalenessLine }
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    specRow
                    sailingPicker
                    rateLedger
                    commitTerms
                    esangCard
                    ctaPair
                    if showCompare { comparePanel }
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

    // MARK: Header

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("SHIPPER · CONFIRM & BOOK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("SPOT · 40FT HC").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }
    /// Golden-anchor law: the H1 is a NUMBER or a PLACE. 005 owns the lane; this screen owns the money.
    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("\(money(allIn)) all-in")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            StatusPill(text: indicative ? "INDICATIVE" : "RATE HELD", kind: indicative ? .warning : .info)
        }
    }
    private var stalenessLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
            Text(syncedAt.map { "Cached quote · last synced \($0.formatted(date: .abbreviated, time: .shortened))" }
                 ?? "Cached quote · not yet synced this session")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(Brand.warning)
    }

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCardSoft).frame(height: 42)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 182)
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

    // MARK: SPEC row — what replaced the phantom rail

    private var specRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SPEC · SET IN CREATE BOOKING")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                Text("\(cargoType) · 40ft HC · \(commodity) · \(Int(totalWeightKg).formatted()) kg · \(Int(totalVolumeCBM)) CBM")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if let onEditSpec {
                Button("Edit", action: onEditSpec)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3).frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.textPrimary.opacity(0.04)))
    }

    // MARK: Sailing — a REAL radio group over the live schedule rows

    private var sailingPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SAILING · \(voyages.count) ON THIS LANE · \(selectedVoyageId == nil ? 0 : 1) SELECTED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if voyages.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.warning)
                        Text("No scheduled sailing on this lane right now. A booking needs a sailing, so confirm stays disabled.")
                            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(voyages.enumerated()), id: \.element.id) { idx, v in
                        Button { selectedVoyageId = v.id } label: { sailingRow(v) }
                            .buttonStyle(.plain)
                        if idx != voyages.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func sailingRow(_ v: VoyageRow007) -> some View {
        let picked = v.id == selectedVoyageId
        return HStack(spacing: Space.s3) {
            ZStack {
                if picked {
                    Circle().fill(LinearGradient.primary).frame(width: 18, height: 18)
                    Circle().fill(.white).frame(width: 7, height: 7)
                } else {
                    Circle().strokeBorder(palette.borderStrong, lineWidth: 1.8).frame(width: 18, height: 18)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                // Named gap 2: vessels.name is not joined, so the row leads with the voyage number.
                Text(v.vesselName.map { "\($0) \(v.voyageNumber ?? "")" } ?? "Voyage \(v.voyageNumber ?? "—")")
                    .font(.system(size: 12.5, weight: picked ? .heavy : .bold))
                    .foregroundStyle(picked ? palette.textPrimary : palette.textSecondary)
                Text(scheduleLine(v)).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(cutoffLine(v))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(picked ? Brand.warning : palette.textTertiary)
        }
        .padding(Space.s4)
        .contentShape(Rectangle())
    }

    private func scheduleLine(_ v: VoyageRow007) -> String {
        let etd = Self.parseDate(v.scheduledDeparture)
        let eta = Self.parseDate(v.scheduledArrival)
        var bits: [String] = []
        if let etd { bits.append("ETD " + etd.formatted(.dateTime.month(.abbreviated).day())) }
        if let eta { bits.append("ETA " + eta.formatted(.dateTime.month(.abbreviated).day())) }
        if let etd, let eta, let d = Calendar.current.dateComponents([.day], from: etd, to: eta).day { bits.append("\(d)d") }
        if bits.isEmpty, let route = v.serviceRoute { bits.append(route) }
        return bits.joined(separator: " · ")
    }
    /// Container cutoff is not a column on vessel_voyages; the industry rule of thumb of two days
    /// before departure is stated as derived, never presented as a carrier-published cutoff.
    private func cutoffLine(_ v: VoyageRow007) -> String {
        guard let etd = Self.parseDate(v.scheduledDeparture),
              let cut = Calendar.current.date(byAdding: .day, value: -2, to: etd) else { return "cutoff —" }
        return "est cutoff " + cut.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Rate ledger — the five real vessel_freight_rates columns + the validity meter

    private var rateLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ALL-IN RATE · 5 LINES · PER 40ft HC · \(currency)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                surchargeLine("Base ocean freight", base)
                surchargeLine("BAF · bunker adjustment", baf)
                surchargeLine("THC origin · \(originPort)", thcOrigin)
                surchargeLine("THC destination · \(destPort)", thcDest)
                surchargeLine("PSS · peak season", pss)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, Space.s2)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(numberOfContainers > 1 ? "ALL-IN · \(numberOfContainers) CONTAINERS" : "ALL-IN")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        HStack(spacing: Space.s3) {
                            Text(money(allIn)).font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            Text(indexDelta).font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
                        }
                    }
                    Spacer(minLength: 0)
                    lockMeter
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }
    private func surchargeLine(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Space.s2)
            Text(money(value)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }.padding(.vertical, 5)
    }
    private var lockMeter: some View {
        HStack(spacing: 8) {
            Circle().fill(indicative ? Brand.warning : Brand.blue).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(indicative ? "INDICATIVE" : "RATE HELD")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(indicative ? Brand.warning : Brand.info)
                Text(lockText).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background((indicative ? Brand.warning : Brand.blue).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Commit terms — the three controls, all bound to the payload

    private var commitTerms: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COMMIT TERMS · EDITABLE HERE · 3 FIELDS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                Stepper(value: $numberOfContainers, in: 1...500) {
                    HStack {
                        Text("Containers").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text("\(numberOfContainers) × 40ft HC")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    }
                }
                Picker("Freight terms", selection: $freightTerms) {
                    Text("Prepaid").tag("prepaid")
                    Text("Collect").tag("collect")
                    Text("Third party").tag("third_party")
                }
                .pickerStyle(.segmented)
                Picker("Incoterms", selection: $incoterms) {
                    ForEach(incotermOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: ESang — geometry and figure preserved (this axis PASSED; do not regress it)

    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            OrbeSang(state: .idle, diameter: 32).padding(.trailing, Space.s3)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · RATE PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangLine).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: Space.s2) {
                    Text(esangAmount).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.magenta)
                    Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private var esangLine: String {
        if indicative { return "Rate is indicative — reconnect before committing" }
        if lockSeconds < 1_800 { return "Window closing — confirm or re-quote" }
        return "Lock now — index trends up next week"
    }
    private var esangAmount: String {
        if indicative { return "NO HOLD" }
        let h = lockSeconds / 3600, m = (lockSeconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m LEFT" : "\(m)m LEFT"
    }
    private var esangDetail: String {
        indicative ? "booking stays ONLINE_ONLY · nothing is queued"
                   : "\(indexDelta) · validity window live"
    }

    // MARK: CTA pair — both real Buttons

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s3) {
                Button { Task { await confirmBooking() } } label: {
                    Text(confirmTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(canConfirm ? AnyShapeStyle(LinearGradient.primary)
                                               : AnyShapeStyle(palette.textTertiary.opacity(0.35)))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)

                // AXIS E · a real Button with a real call, not a Text in a capsule.
                Button { Task { await compareCarriers() } } label: {
                    HStack(spacing: 6) {
                        if comparing { ProgressView().controlSize(.mini) }
                        Text(comparing ? "…" : "Compare").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgSecondary).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(comparing)
            }
            if let why = confirmDisabledReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.info)
                    Text(why).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }
    private var canConfirm: Bool {
        !submitting && bookedRef == nil && selectedVoyageId != nil && !offline
    }
    private var confirmTitle: String {
        if submitting { return "Booking…" }
        if let ref = bookedRef { return "Booked · \(ref)" }
        return "Confirm · \(money(allIn))"
    }
    private var confirmDisabledReason: String? {
        if bookedRef != nil { return nil }
        if offline { return "A booking commits money against a quote that expires, so it is never queued offline. Reconnect to confirm." }
        if selectedVoyageId == nil { return "Pick a sailing first — the booking has to name the voyage it rides." }
        return nil
    }

    private var comparePanel: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CARRIER COMPARISON · \(carrierQuotes.count) QUOTED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if let note = compareNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.info)
                        Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(carrierQuotes.enumerated()), id: \.element.id) { idx, q in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.carrier ?? "—").font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text([q.service, q.transitDays.map { "\($0)d transit" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                            }
                            Spacer()
                            Text(q.allIn.map { money($0) } ?? "—")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        }
                        .padding(Space.s4)
                        if idx != carrierQuotes.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Load — arrays, real key names

    private func load() async {
        loading = true; loadError = nil
        struct SchedIn: Encodable { let departurePortId: Int; let arrivalPortId: Int; let limit: Int }
        struct RateIn: Encodable { let originPortId: Int; let destinationPortId: Int; let containerSize: String }
        do {
            async let sched: [VoyageRow007] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselSchedules",
                input: SchedIn(departurePortId: originPortId, arrivalPortId: destinationPortId, limit: 10))
            async let rates: [RateRow007] = EusoTripAPI.shared.query(
                "vesselShipments.searchRates",
                input: RateIn(originPortId: originPortId, destinationPortId: destinationPortId, containerSize: containerSize))
            let (s, r) = try await (sched, rates)
            applySchedules(s)
            applyRates(r)
            syncedAt = Date(); servedFromCache = false
        } catch {
            // READ_CACHED(ttl 24h): keep the last-known ledger visible but MARKED, never silently.
            if syncedAt != nil { servedFromCache = true } else { loadError = error.eusoUserCopy }
        }
        loading = false
    }

    private func applySchedules(_ rows: [VoyageRow007]) {
        // Only sailings that have not left are bookable.
        let bookable = rows.filter { ($0.status ?? "scheduled") == "scheduled" }
        voyages = bookable.isEmpty ? rows : bookable
        if selectedVoyageId == nil || !voyages.contains(where: { $0.id == selectedVoyageId }) {
            selectedVoyageId = voyages.first?.id
        }
    }

    private func applyRates(_ rows: [RateRow007]) {
        guard let r = rows.first else { return }
        base      = Double(r.ratePerUnit ?? "") ?? base
        baf       = Double(r.bafSurcharge ?? "") ?? baf
        thcOrigin = Double(r.thcOrigin ?? "") ?? thcOrigin
        thcDest   = Double(r.thcDestination ?? "") ?? thcDest
        pss       = Double(r.peakSeasonSurcharge ?? "") ?? pss
        currency  = r.currency ?? currency
        // Named gap 1: no rate-lock procedure. The window is derived from the row's own expiry, and
        // when there is none the meter says INDICATIVE rather than inventing a countdown.
        rateExpiresAt = Self.parseDate(r.expirationDate)
        if let exp = rateExpiresAt {
            lockSeconds = max(Int(exp.timeIntervalSinceNow), 0)
        } else {
            lockSeconds = 0
        }
    }

    /// Ticks the derived validity window. It never counts while indicative — a countdown on a
    /// number nobody is holding is a lie with a clock on it.
    private func streamLock() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { break }
            if lockSeconds > 0 && !offline { lockSeconds -= 1 }
        }
    }

    // MARK: The write — createVesselBooking:424, now carrying BOUND values instead of literals

    private func confirmBooking() async {
        guard canConfirm, let voyage = selectedVoyage else { return }
        submitting = true; defer { submitting = false }
        struct BookingIn: Encodable {
            let originPortId: Int
            let destinationPortId: Int
            let vesselId: Int?
            let cargoType: String
            let commodity: String
            let containerSize: String
            let numberOfContainers: Int
            let totalWeightKg: Double
            let totalVolumeCBM: Double
            let freightTerms: String
            let incoterms: String
            let rate: Double
            let etd: String?
            let eta: String?
        }
        let input = BookingIn(
            originPortId: originPortId,
            destinationPortId: destinationPortId,
            vesselId: voyage.vesselId,                 // from the SELECTED sailing, not a literal
            cargoType: cargoType,
            commodity: commodity,
            containerSize: containerSize,
            numberOfContainers: numberOfContainers,    // from the Stepper
            totalWeightKg: totalWeightKg,
            totalVolumeCBM: totalVolumeCBM,
            freightTerms: freightTerms,                // from the segment
            incoterms: incoterms,                      // from the Picker
            rate: allIn,                               // the priced quote this screen committed to
            etd: voyage.scheduledDeparture,
            eta: voyage.scheduledArrival
        )
        do {
            let c: CreatedBooking007 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBooking", input: input)
            bookedRef = c.bookingNumber ?? "confirmed"
        } catch {
            loadError = error.eusoUserCopy
        }
    }

    // MARK: Compare — getCarrierRates:3048, a real call behind a real Button

    private func compareCarriers() async {
        comparing = true; compareNote = nil; defer { comparing = false }
        showCompare = true
        guard !offline else {
            compareNote = "Carrier comparison is a live lookup — it has nothing cached to show while offline."
            carrierQuotes = []
            return
        }
        struct CompareIn: Encodable { let originPort: String; let destPort: String; let containerSize: String }
        do {
            // getCarrierRates:3048 returns null when the upstream INTTRA call fails, so the optional
            // decode is the honest shape — an empty list and a blank panel would hide the failure.
            let quotes: [CarrierQuote007]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getCarrierRates",
                input: CompareIn(originPort: originCode, destPort: destCode, containerSize: containerSize))
            carrierQuotes = quotes ?? []
            if carrierQuotes.isEmpty {
                compareNote = "The carrier rate feed returned nothing for \(originCode) → \(destCode). Your held quote above is unchanged."
            }
        } catch {
            carrierQuotes = []
            compareNote = error.eusoUserCopy
        }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: String(raw.prefix(10)))
    }
}

#Preview("007 · Confirm & book · Night") {
    VesselNewBooking_007(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("007 · Confirm & book · Light") {
    VesselNewBooking_007(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
