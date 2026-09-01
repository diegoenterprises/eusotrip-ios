//
//  837_VesselContainerEOR.swift
//  EusoTrip — Vessel Operator · Container M&R / EOR (837).
//
//  Verbatim-composition port of "837 Vessel Container M&R EOR.svg" (Dark →
//  Light). ESTIMATE-OF-REPAIR + THREE-WAY RESPONSIBILITY SPLIT archetype — the
//  EOR total does not sit alone, it immediately breaks into one rail divided
//  between CARRIER / LESSEE / WEAR-AND-TEAR (a split, not three tiles), then
//  the IICL-coded repair lines each carrying component · code · repair action ·
//  amount · who pays, then the survey-evidence row, the IICL5 hold strip and
//  the repair-standard country band.
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  Sibling separation: 836 (Laytime & SOF) is a money CLOCK — one payer, time
//  on one axis, a chronological left-spined ledger with counts/excluded chips.
//  837 is a money SPLIT — no clock, no chronology; its rail divides one total
//  between three payers and every line answers "who pays", not "when". Distinct
//  too from 676 Equipment Health (telemetry, not an estimate) and from 832
//  Three-Way Match (invoice reconciliation, not a damage survey).
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, … }, containers: [{ id, containerNumber, containerType,
//        status, … }] }. The container under survey, its type and its booking
//        come from that payload; the container number is real equipment
//        identity, not a label typed into the screen.
//    REAL — the IICL5 / AAR repair standard and its component codes (TRA top
//        rail · CCR corner casting · MAE machinery · FLR floor) are the fixed
//        inspection instrument, exactly as the CSS Code is fixed on 833.
//    STUB · named-gap — vessel.getEOR({ containerId }); there is no M&R / EOR
//        model on disk (grep EOR = 0, grep IICL = 0 across Views). It would
//        return { totalCents, carrierCents, lesseeCents, wearCents, photos:Int,
//        shopDays, lines:[{ component, code, repair, amountCents,
//        who: carrier|lessee|wear }] }. Until it ships the rail renders
//        UNALLOCATED (dashed, equal-width segments that claim no proportion),
//        every component line reads "$—" with an UNASSIGNED party, and no
//        damage is asserted to have been found.
//    STUB · named-gap MONEY — vessel.approveEOR({ containerId, amount,
//        currency:'USD', confirm:true }) — gated + confirm:true + audit + test;
//        writes eor_approval + blockchainAuditTrail vessel.eor_approved;
//        broadcasts WS_CHANNELS.VESSEL_OPS / WS_EVENTS.EOR_APPROVED.
//    NOTHING on this screen fabricates money OR equipment identity. The SVG's
//        literal figures ($1,240 total · $740 carrier / $360 lessee / $140 W&T ·
//        4 lines · 4 photos · est 2 days) exist in this comment only, and so
//        does its sample unit identity — the SVG's specimen container number and
//        box type are NOT used as render fallbacks. When the containers payload
//        resolves no unit the header reads "— · no container selected".
//
//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(15m) for the
//    container context + estimate — a fifteen-minute-old estimate is still a
//    readable estimate, and the unallocated/awaiting states are visibly
//    distinct so cache can never pass as live.
//    HONEST SCOPE OF THAT TIER: what the code actually does today is retain the
//    last decoded serve IN MEMORY for the life of the session and banner-flag a
//    failed refresh above it instead of blanking the screen. There is NO
//    persistent cache layer behind it — Services/EusoTripAPI.swift:415-416 sets
//    .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so nothing
//    survives a cold launch and the 15m TTL is a policy declaration, not an
//    enforced one. OPEN item (owning lane: the-oath): a real on-disk read cache
//    with TTL enforcement. Approve EOR is
//    ONLINE_ONLY(money movement must never be queued): an approval queued
//    offline could be replayed against a re-surveyed unit, or approve an amount
//    that the depot has already revised.
//
//  CHAIN closure: approving an EOR emits WS_CHANNELS.VESSEL_OPS /
//    WS_EVENTS.EOR_APPROVED to the EQUIPMENT / DETENTION surfaces — the repair
//    hold is what stops a damaged unit from being re-issued, and the approved
//    amount is what the lessee is later billed against. OPEN counter-party item
//    (owning lane: VESSEL · the-oath): that half does not exist. The detention
//    cluster is present on iOS (784 Detention Tracking · 790 Detention
//    Dashboard · 791 Active Detentions) but not one of those surfaces consumes
//    an eor_approval row or listens for EOR_APPROVED, and there is no
//    lessee-side EOR acceptance / dispute screen anywhere in the app (grep EOR
//    across Views = 0 before this file). So an approved estimate would emit
//    into silence: the unit's hold would never be reflected on the equipment
//    side and the lessee would never see the line they are charged for. Until
//    the receiving half ships, the approve CTA stays honestly gated.
//
//  COUNTRY (single-country content, never a file fork): US IICL5 · AAR repair
//    standard ACTIVE · CA IICL5 depot tariff CAD · MX IICL5 maniobra MXN.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselContainerEORScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var containerId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselContainerEORBody(shipmentId: shipmentId, containerId: containerId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Shipment + container shapes (getVesselShipmentDetail)

private struct EORShipment837: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
}
private struct EORContainer837: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
    let status: String?
}
private struct EORDetail837: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: EORShipment837?
    let containers: [EORContainer837]?

    private enum CodingKeys: String, CodingKey { case shipment, containers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(EORShipment837.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? EORShipment837(from: decoder)   // real shape: fields sit on the root
        }
        self.containers = try? c.decodeIfPresent([EORContainer837].self, forKey: .containers)
    }
}

// MARK: - Responsibility model

/// The three payers an EOR line can land on. This is the IICL cost-cause split
/// the whole screen exists to resolve — it is doctrine, not data.
private enum EORPayer837: CaseIterable {
    case carrier, lessee, wear

    var label: String {
        switch self {
        case .carrier: return "CARRIER"
        case .lessee:  return "LESSEE"
        case .wear:    return "W&T"
        }
    }
    var longLabel: String {
        switch self {
        case .carrier: return "Carrier"
        case .lessee:  return "Lessee"
        case .wear:    return "Wear & tear"
        }
    }
}

/// One inspection component in the IICL survey scope. `amount` and `payer` are
/// `nil` until getEOR returns — an unfilled line means "no repair line was
/// returned for this component", never "no damage" and never a made-up figure.
private struct EORLine837: Identifiable {
    let id = UUID()
    let component: String
    let code: String
    let action: String
    var amount: String? = nil
    var payer: EORPayer837? = nil
}

// MARK: - Body

private struct VesselContainerEORBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let containerId: String

    @State private var shipment: EORShipment837? = nil
    @State private var container: EORContainer837? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var approveNote: String? = nil

    /// The IICL5 inspection scope for a box at gate-in survey. These are the
    /// standard's component codes and their standard repair actions — the same
    /// four an EOR form prints — so they scaffold the estimate honestly.
    /// STATIC deliberately: the elements carry `let id = UUID()`, so an instance
    /// array literal re-mints every id on each Body re-init and the ForEach
    /// identity changes every render, defeating view diffing. The scope is fixed
    /// standard content, so one evaluation for the process is correct.
    private static let lines: [EORLine837] = [
        EORLine837(component: "Top rail",         code: "TRA", action: "dent DT · straighten"),
        EORLine837(component: "Corner casting",   code: "CCR", action: "crack CR · replace"),
        EORLine837(component: "Reefer machinery", code: "MAE", action: "gasket BT · reseal"),
        EORLine837(component: "Floor board",      code: "FLR", action: "gouge · repair")
    ]

    private var pricedCount: Int { Self.lines.filter { $0.amount != nil }.count }

    private func payerColor(_ p: EORPayer837?) -> Color {
        guard let p else { return palette.textTertiary }
        switch p {
        case .carrier: return Brand.blue
        case .lessee:  return Color(hex: 0xFFC246)
        case .wear:    return palette.textTertiary
        }
    }

    /// Equipment identity is REAL data or it is nothing. A container number and
    /// a box type are the survey's subject — printing the SVG's sample unit as a
    /// fallback would name a box nobody has surveyed and attach an estimate to
    /// it. When no unit has resolved the header says so.
    private var unitLine: String {
        guard let box = container, let number = box.containerNumber, !number.isEmpty else {
            return "— · no container selected · gate-in survey"
        }
        let rawType = box.containerType ?? ""
        let type = rawType.isEmpty ? "type —" : rawType
        return "\(number) · \(type) · gate-in survey"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · CONTAINER M&R / EOR",
                caption: "IICL · EOR",   // was "MSC · IICL" — IICL is the real repair standard; the carrier was invented
                title: "EOR estimate",
                subtitle: unitLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil && container == nil {
                    // Nothing retained to keep — the failure IS the screen.
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        // Non-destructive refresh banner. A failed re-read never
                        // blanks a serve that is already on screen; it is flagged
                        // as no-longer-fresh above the retained content.
                        VesselErrorCard(text: "Refresh failed — \(err) The estimate below is the last serve this session returned and is not being updated.")
                    }
                    splitHero
                    damageLineSection
                    evidenceRow
                    VesselSummaryStrip(
                        label: "IICL5 criteria · DV hold until repaired",
                        value: "shop time —",
                        valueColor: palette.textTertiary
                    )
                    VesselRegulatorBand(
                        title: "REPAIR STANDARD · SINGLE-COUNTRY",
                        reference: "repair · country",
                        rows: [
                            .init("US", "IICL5 · AAR repair standard", active: true),
                            .init("CA", "IICL5 · depot tariff CAD"),
                            .init("MX", "IICL5 · maniobra MXN")
                        ]
                    )
                    if let approveNote { VesselGapNote(text: approveNote) }
                    ctaPair
                    VesselGapNote(text: "Container identity and booking context are live. No estimate of repair is linked to this unit — every amount, the carrier/lessee/wear split and the survey photographs arrive with the M&R service. No repair cost is calculated on the device.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Hero (EOR total broken straight into the three-way split)

    private var splitHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Depot gate-in survey · repair estimate")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("PENDING APPROVAL")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$—")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("EOR total · \(pricedCount) of \(Self.lines.count) lines priced")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                EORSplitRail837(shares: nil)
                splitLegend
            }
        }
    }

    private var splitLegend: some View {
        HStack(spacing: 0) {
            ForEach(Array(EORPayer837.allCases.enumerated()), id: \.offset) { idx, payer in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(payerColor(payer))
                        .frame(width: 8, height: 8)
                    Text(payer.longLabel)
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(payerColor(payer))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("$—")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity,
                       alignment: idx == 0 ? .leading : (idx == 1 ? .center : .trailing))
            }
        }
    }

    // MARK: - IICL damage lines (component · code · action · amount · who pays)

    private var damageLineSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DAMAGE SURVEY · IICL COMPONENTS",
                                right: "AWAITING · getEOR")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.lines.enumerated()), id: \.element.id) { idx, line in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        damageRow(line)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("IICL5 inspection scope · repair lines and cost cause arrive with the survey")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
    }

    private func damageRow(_ line: EORLine837) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // The spine carries the payer. Unassigned lines get a hollow dashed
            // spine so an unresolved cost cause is never mistaken for a settled
            // one at a glance.
            Group {
                if line.payer != nil {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(payerColor(line.payer))
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(palette.textTertiary,
                                      style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2.5]))
                }
            }
            .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(line.component)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(line.code) · \(line.action)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(line.amount ?? "$—")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(line.amount == nil ? palette.textTertiary : palette.textPrimary)
                payerChip(line.payer)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func payerChip(_ payer: EORPayer837?) -> some View {
        let assigned = payer != nil
        return Text(payer?.label ?? "UNASSIGNED")
            .font(.system(size: 8, weight: .heavy)).tracking(0.3)
            .foregroundStyle(payerColor(payer))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                Capsule().fill(assigned ? payerColor(payer).opacity(0.15) : palette.tintNeutral)
            )
            .overlay(
                Capsule().strokeBorder(
                    assigned ? Color.clear : palette.textTertiary.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1, dash: assigned ? [] : [2.5, 2.5])
                )
            )
    }

    // MARK: - Survey evidence

    private var evidenceRow: some View {
        VesselGroupCard(cornerRadius: Radius.md) {
            HStack(spacing: Space.s3) {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(palette.textTertiary.opacity(0.45),
                                          style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 40, height: 26)
                            .overlay(
                                Image(systemName: "camera")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(palette.textTertiary)
                            )
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("No survey photos linked")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("gate camera + surveyor mobile")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Approve EOR", action: { flagApproveGap() }, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Dispute lines", width: 150) { flagApproveGap() }
        }
    }

    /// The money mutation does not exist yet, and even when it does it is
    /// ONLINE_ONLY — and its counter-party half is missing, so an approval today
    /// would emit into silence. Say all of that instead of firing a no-op.
    private func flagApproveGap() {
        approveNote = "An estimate cannot be approved or disputed from this device yet: the approval endpoint is not built, money movement is never queued offline, and no equipment or lessee surface currently receives an approved EOR."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft).frame(height: 60)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; container = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: EORDetail837? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
            let boxes = detail?.containers ?? []
            // Prefer the unit this screen was opened for; otherwise the first
            // container on the booking. Never invent a unit that is not there.
            self.container = boxes.first(where: { $0.containerNumber == containerId }) ?? boxes.first
        } catch {
            // `shipment` and `container` are deliberately NOT cleared. A failed
            // refresh keeps the last decoded serve on screen, banner-labelled as
            // not fresh, rather than blanking an estimate under review.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Three-way split rail (bespoke · one total divided, never three tiles)

/// The responsibility instrument: ONE rail carrying the whole EOR total, cut
/// into carrier / lessee / wear-and-tear. `shares` are fractions summing to 1;
/// `nil` means getEOR has not returned, and the rail renders UNALLOCATED — equal
/// dashed outlines that visibly claim no proportion and paint no money.
private struct EORSplitRail837: View {
    @Environment(\.palette) private var palette
    /// (colour, fraction) per payer, in carrier → lessee → wear order.
    let shares: [(Color, Double)]?

    var body: some View {
        Group {
            if let shares, !shares.isEmpty {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    HStack(spacing: 0) {
                        ForEach(Array(shares.enumerated()), id: \.offset) { _, part in
                            Rectangle().fill(part.0)
                                .frame(width: w * CGFloat(max(part.1, 0)))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .strokeBorder(palette.textTertiary.opacity(0.45),
                                          style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 12)
                .overlay(alignment: .center) {
                    Text("UNALLOCATED")
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(palette.bgCard))
                }
            }
        }
    }
}

#Preview("837 · Vessel Container M&R / EOR · Night") {
    VesselContainerEORScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("837 · Vessel Container M&R / EOR · Light") {
    VesselContainerEORScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
