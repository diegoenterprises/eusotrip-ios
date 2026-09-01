//
//  836_VesselLaytimeSOF.swift
//  EusoTrip — Vessel Operator · Laytime & Statement of Facts (836).
//
//  Verbatim-composition port of "836 Vessel Laytime & Statement of Facts.svg"
//  (Dark → Light). LAYTIME-METER + SOF-EVENT-LEDGER archetype — the charter-
//  party time reckoning: a money hero carrying an allowed-vs-used meter with a
//  fixed ALLOWED scale mark and an overrun region past it, then a chronological
//  Statement-of-Facts ledger where every milestone is stamped and classed
//  `counts` or `excluded` (that classification IS the instrument — a weather
//  stoppage must never read like working time), then the reckoning strip
//  (rate/day · days over · CP clause) and the laytime-custom country band.
//  Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  Sibling separation: 837 (Container M&R / EOR) is a money SPLIT across three
//  payers. 836 is a money CLOCK — one payer, time on one axis. Neither borrows
//  the other's spine: 836's rows are timestamped and left-spined with a right
//  classification chip; 837's are money-columned with a party assignment.
//  Distinct too from the container D&D cluster (658/665/784/785 = terminal LFD
//  and per-diem) — this is vessel charter-party laytime, a different instrument.
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        voyageNumber, bookingNumber, … } }. Vessel + voyage + booking drive the
//        header and the hero context line whenever a booking is selected.
//    REAL — the charter-party SOF milestone sequence (NOR tendered → NOR
//        accepted → commenced → stoppage → resumed → completed) and the WWD
//        SHEX EIU counts/excluded rule are the fixed instrument, not data.
//    STUB · named-gap — vessel.getLaytimeSOF({voyageId}); there is no laytime /
//        SOF model on disk (grep laytime = 0). It would return { allowedLabel,
//        usedLabel, overLabel, usedFrac, demurrageCents, ratePerDayCents,
//        daysOver, cpClause, events:[{ ts, event, note, counts:Bool }] }. Until
//        it ships: no hours, no dollars, no stamps are rendered — the meter
//        shows its scale unfilled and every milestone reads UNSTAMPED.
//    STUB · named-gap MONEY — vessel.issueDemurrageInvoice({ voyageId, amount,
//        currency:'USD', confirm:true }) — gated + confirm:true + audit + test;
//        writes demurrage_invoice + blockchainAuditTrail
//        vessel.demurrage_issued; broadcasts WS_CHANNELS.VESSEL_OPS /
//        WS_EVENTS.DEMURRAGE_ISSUED. The CTA is present and honest: it names the
//        gap instead of pretending to bill.
//    NOTHING on this screen fabricates money. The SVG's literal figures
//        ($48,600 owed · $28,000/day · 84h allowed vs 96h20m used) exist in this
//        comment only and are never rendered as if live.
//
//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(15m) for the
//    shipment context + laytime reckoning — a stale reckoning is still a
//    readable reckoning, and the awaiting-states are visibly distinct so a
//    cached payload can never masquerade as a fresh one.
//    HONEST SCOPE OF THAT TIER: the retained serve is held IN MEMORY for the
//    life of the session — a failed refresh is banner-flagged above the content
//    it keeps rather than blanking the screen. There is NO persistent cache
//    layer behind it: Services/EusoTripAPI.swift:415-416 sets
//    .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil, so nothing
//    survives a cold launch and the 15m TTL is a policy declaration, not an
//    enforced one. OPEN item (owning lane: the-oath) — a real on-disk read
//    cache with TTL enforcement. Issue demurrage is
//    ONLINE_ONLY(money movement must never be queued): a demurrage invoice
//    queued offline could be issued twice, or issued against a voyage whose
//    exclusions changed while the device was dark.
//
//  CHAIN closure: issuing demurrage emits WS_CHANNELS.VESSEL_OPS /
//    WS_EVENTS.DEMURRAGE_ISSUED to the SHIPPER's demurrage surfaces. OPEN
//    counter-party item (owning lane: VESSEL · the-oath): the shipper half does
//    not receive this. Views/Shipper/426_DemurrageCharges.swift exists but binds
//    the ACCESSORIAL demurrage lane (demurrage.respond / catalysts.
//    acceptDemurrage) — a different table from the vessel demurrage the operator
//    writes. This is the split-brain the vessel dead-air audit named: the
//    operator path resolves fine (665 files a dispute through
//    vesselShipments.disputeVesselDemurrage), while a shipper served a VESSEL
//    demurrage invoice has no inbox to see it in and therefore no way to
//    dispute it. Until the shipper-side vessel-demurrage inbox ships, this
//    screen's issue CTA would create an unanswerable charge — which is the
//    second reason it stays honestly gated here.
//
//  COUNTRY (single-country content, never a file fork): US law · WWD SHEX EIU
//    custom ACTIVE · CA port working custom · MX costumbre del puerto.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselLaytimeSOFScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var voyageId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselLaytimeSOFBody(shipmentId: shipmentId, voyageId: voyageId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct LaytimeShipment836: Decodable {
    let id: Int?
    let vesselName: String?
    let voyageNumber: String?
    let bookingNumber: String?
}
private struct LaytimeDetail836: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: LaytimeShipment836?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(LaytimeShipment836.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? LaytimeShipment836(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - SOF milestone model (the charter-party sequence, not claimed events)

/// How a milestone is treated against the charter-party clock. This is the CP
/// RULE (WWD SHEX EIU), fixed by the instrument — not a per-event outcome, and
/// never a substitute for a stamp.
private enum SOFClass836 {
    case counts
    case excluded
}

private struct SOFMilestone836: Identifiable {
    let id = UUID()
    let title: String
    let note: String
    let klass: SOFClass836
    /// Real stamp from getLaytimeSOF. `nil` until the model ships — rendered as
    /// an em-dash stamp with an UNSTAMPED read, never back-filled.
    var stamp: String? = nil
}

// MARK: - Body

private struct VesselLaytimeSOFBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String

    @State private var shipment: LaytimeShipment836? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var issueNote: String? = nil

    /// The charter-party Statement-of-Facts sequence. These are the milestones
    /// a SOF is made of — the same fixed vocabulary a CP form prints — so they
    /// scaffold the ledger honestly. No stamp, no duration and no exclusion
    /// total is asserted; those arrive with getLaytimeSOF.
    /// STATIC deliberately: the elements carry `let id = UUID()`, so an instance
    /// array literal re-mints every id on each Body re-init and the ForEach
    /// identity changes every render, defeating view diffing. The vocabulary is
    /// fixed charter-party content, so one evaluation for the process is right.
    private static let milestones: [SOFMilestone836] = [
        SOFMilestone836(title: "NOR tendered",       note: "commences turn-time", klass: .counts),
        SOFMilestone836(title: "NOR accepted",       note: "laytime starts",      klass: .counts),
        SOFMilestone836(title: "Commenced loading",  note: "gang allocation",     klass: .counts),
        SOFMilestone836(title: "Weather stoppage",   note: "weather exclusion",   klass: .excluded),
        SOFMilestone836(title: "Resumed loading",    note: "clock restarts",      klass: .counts),
        SOFMilestone836(title: "Completed loading",  note: "laytime stops",       klass: .counts)
    ]

    private var stampedCount: Int { Self.milestones.filter { $0.stamp != nil }.count }

    private var voyageLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voyage = s.voyageNumber ?? s.bookingNumber ?? voyageId
            return voyage.isEmpty ? "\(vessel) · charter-party laytime"
                                  : "\(vessel) · voyage \(voyage) · charter-party laytime"
        }
        // 2026-08-25 — was a fabricated ship and port ("MSC ANL Tongala … POLB").
        // Reached from the operator Me-hub this screen carries no shipmentId, so
        // this is the ONLY line a hub user ever sees. Matches the honest form in
        // 835/837/842: assert no vessel rather than name a plausible one.
        return "— · no booking selected · charter-party laytime"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · LAYTIME & SOF",
                caption: "CHARTER PARTY · SOF",   // was "MSC · USD" — carrier and currency, neither loaded
                title: "Laytime & SOF",
                subtitle: voyageLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil {
                    // Nothing retained to keep — the failure IS the screen.
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        // Non-destructive refresh banner. A failed re-read never
                        // blanks a serve that is already on screen; it is flagged
                        // as no-longer-fresh above the retained content.
                        VesselErrorCard(text: "Refresh failed — \(err) The reckoning below is the last serve this session returned and is not being updated.")
                    }
                    reckoningHero
                    sofLedgerSection
                    reckoningStrip
                    VesselRegulatorBand(
                        title: "LAYTIME CUSTOM · SINGLE-COUNTRY",
                        reference: "laytime · country",
                        rows: [
                            .init("US", "US law · WWD SHEX EIU custom", active: true),
                            .init("CA", "Canada · port working custom"),
                            .init("MX", "Mexico · costumbre del puerto")
                        ]
                    )
                    if let issueNote { VesselGapNote(text: issueNote) }
                    ctaPair
                    VesselGapNote(text: "Vessel and voyage context are live. No laytime reckoning is linked to this voyage — allowed and used time, the demurrage figure and every event stamp arrive with the laytime service. Nothing on this screen is estimated on the device.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Hero (demurrage money + the laytime meter)

    private var reckoningHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Charter-party laytime reckoning")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("RECKONING PENDING")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                // Money is the most dangerous thing to fabricate — the figure
                // stays an em-dash and stays NEUTRAL (never danger-red), so the
                // screen cannot imply that demurrage is owed.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$—")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("demurrage owed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("— allowed · — used · — over")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                LaytimeMeter836(usedFrac: nil,
                                allowedLabel: "allowed —",
                                overLabel: "used —")
            }
        }
    }

    // MARK: - Statement of Facts ledger

    private var sofLedgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "STATEMENT OF FACTS · EVENTS",
                                right: "AWAITING · getLaytimeSOF")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.milestones.enumerated()), id: \.element.id) { idx, m in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        milestoneRow(m)
                    }
                }
            }
            stampLine
            classLegend
        }
    }

    private func milestoneRow(_ m: SOFMilestone836) -> some View {
        let counts = m.klass == .counts
        return HStack(alignment: .center, spacing: Space.s3) {
            // Spine: working time is a solid brand bar, excluded time is a
            // hollow dashed bar. The distinction is legible before any text.
            Group {
                if counts {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Brand.blue)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(palette.textTertiary,
                                      style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2.5]))
                }
            }
            .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(m.stamp ?? "—— ——  ——:——")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(m.stamp == nil ? palette.textTertiary : palette.textSecondary)
                Text(m.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(counts ? palette.textPrimary : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                classChip(m.klass)
                Text(m.note)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func classChip(_ klass: SOFClass836) -> some View {
        let counts = klass == .counts
        return Text(counts ? "counts" : "excluded")
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(counts ? Brand.success : palette.textTertiary)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(
                Capsule().fill(counts ? palette.tintSuccess : palette.tintNeutral)
            )
            .overlay(
                Capsule().strokeBorder(
                    counts ? Color.clear : palette.textTertiary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: counts ? [] : [2.5, 2.5])
                )
            )
    }

    private var stampLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("\(Self.milestones.count) charter-party milestones · \(stampedCount) stamped")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("UNSTAMPED")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(palette.tintNeutral))
        }
    }

    private var classLegend: some View {
        HStack(spacing: Space.s4) {
            legendItem(solid: true,  color: Brand.blue,          label: "counts against laytime")
            legendItem(solid: false, color: palette.textTertiary, label: "excluded · CP exception")
            Spacer(minLength: 0)
        }
    }

    private func legendItem(solid: Bool, color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Group {
                if solid {
                    RoundedRectangle(cornerRadius: 2).fill(color)
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                }
            }
            .frame(width: 4, height: 12)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Reckoning strip (rate · days over · CP clause)

    private var reckoningStrip: some View {
        VesselSummaryStrip(
            label: "Rate $—/day · — days over · CP cl. —",
            value: "reckoning pending",
            valueColor: palette.textTertiary
        )
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Issue demurrage", action: { flagIssueGap() }, trailingIcon: "arrow.right")
            VesselGhostButton(title: "Despatch calc", width: 150) { flagIssueGap() }
        }
    }

    /// The money mutation does not exist yet, and even when it does it is
    /// ONLINE_ONLY. Say that plainly rather than firing a hopeful no-op.
    private func flagIssueGap() {
        issueNote = "Demurrage cannot be issued from this device yet: the invoicing endpoint is not built, and money movement is never queued offline. The reckoning must also be answerable on the shipper side before a charge is served."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 170)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft).frame(height: 44)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: LaytimeDetail836? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a reckoning still being read.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Laytime meter (bespoke · allowed scale mark + overrun region)

/// The laytime instrument: one rail, an ALLOWED scale mark, and the region past
/// the mark reserved for overrun. `usedFrac` is the only value the meter ever
/// paints — `nil` means the reckoning has not been returned, so the rail stays
/// empty. `allowedMark` is the meter's SCALE (where the allowance line is drawn
/// on the rail), not a claim about how much time was allowed or consumed.
private struct LaytimeMeter836: View {
    @Environment(\.palette) private var palette
    let usedFrac: Double?
    let allowedLabel: String
    let overLabel: String

    private let allowedMark: CGFloat = 0.76

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let mark = w * allowedMark
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(palette.tintNeutral).frame(width: mark)
                        Rectangle().fill(Brand.danger.opacity(0.10))
                    }
                    if let f = usedFrac, f > 0 {
                        HStack(spacing: 0) {
                            Rectangle().fill(Brand.success)
                                .frame(width: min(CGFloat(f), allowedMark) * w)
                            if CGFloat(f) > allowedMark {
                                Rectangle().fill(Brand.danger)
                                    .frame(width: (min(CGFloat(f), 1.0) - allowedMark) * w)
                            }
                        }
                    }
                    Rectangle()
                        .fill(usedFrac == nil ? palette.textTertiary : Brand.success)
                        .frame(width: 2)
                        .offset(x: mark - 1)
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text("0")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 4)
                        Text(allowedLabel)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(usedFrac == nil ? palette.textTertiary : Brand.success)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: mark, alignment: .leading)
                    HStack(spacing: 4) {
                        Spacer(minLength: 4)
                        Text(overLabel)
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: max(w - mark, 1), alignment: .trailing)
                }
            }
        }
        .frame(height: 34)
    }
}

#Preview("836 · Vessel Laytime & SOF · Night") {
    VesselLaytimeSOFScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("836 · Vessel Laytime & SOF · Light") {
    VesselLaytimeSOFScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
