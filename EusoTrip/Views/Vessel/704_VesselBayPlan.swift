//
//  704_VesselBayPlan.swift
//  EusoTrip — Vessel Operator · Bay Plan.
//
//  Faithful port of "704 Vessel Bay Plan.svg" (Light + Dark), adapted onto the canonical DesignSystem
//  (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline). Role
//  VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with the SHIPMENTS slot inked — a bay plan is an
//  operations board, not a statutory surface.
//
//  ARCHETYPE: GRID — a stow plan is a coordinate space, and one projection cannot express it. The
//  retired composition was a single stow elevation, so transverse stability, stack weight and the
//  on-deck versus under-deck split were unrepresentable, and it printed "PLAN LOCK AT RISK" as a text
//  banner — the risk was ASSERTED, never DRAWN. This screen draws it.
//
//  HERO ORGAN: a DUAL-PROJECTION BAY PANE. An athwartships cross-section (9 stacks x 5 tiers, the
//  hatch cover a solid rule splitting on-deck from in-hold) set beside a plan view of the same bay
//  (2 rows x 10 slots), the two joined by three 1.2-stroke correspondence rules so a cell in one
//  projection locates itself in the other.
//
//  LIVE FUSION: the lattice, the stack-weight strip, the exception rows, the ESang read and the
//  country footer are FIVE faces of ONE `boxes` array and re-reason together off load(). The placed
//  count, the reefer count, the verified-mass count and every exception figure are DERIVED from that
//  one state — never a parallel literal. Degraded provider state surfaces an explicit error card,
//  never a frozen number.
//
//  THE HONEST CORE OF THIS SCREEN. Placement has NO backing procedure. The boxes are real; where
//  each one goes is unknown. Rather than scatter real containers into plausible slots — the single
//  most dangerous thing this screen could do — the lattice renders in an explicit UNPLACED state
//  with a visible gap notice, and the nine stack columns render as an EMPTY ENVELOPE beneath a red
//  cap rule that measures nothing. That emptiness is the drawn risk: the ship's stack-weight check
//  cannot be run at all.
//
//  OFFLINE POLICY: READ_CACHED(300s) — nothing here moves money or commits an award. Staleness is
//  DRAWN, not claimed: the hero's right caption stamps the read clock, and the UNPLACED band states
//  the placed count against the live box count, so a cached read can never be mistaken for a
//  resolved plan.
//
//  Data / wiring (every line opened first-hand 2026-08-11; vesselShipments.ts was moving during this
//  fire, so nothing below is copied from a legacy citation — md5 1e4186fb365acaa7cac76303ee502dbd,
//  4328 lines):
//    vesselShipments.getContainerPositions (EXISTS server/routers/vesselShipments.ts:2535 ·
//      vesselProcedure · input {status?:String, limit:Int=100} · returns {containers:[shippingContainers
//      rows], total}). P0-READ-TENANCY: the resolver is `.query(async ({ input })` at
//      vesselShipments.ts:2540 and takes NO ctx, so the read spans every tenant on the platform. This
//      screen filters client-side on assignedShipmentId and says the read is unscoped on screen.
//      This is the only real list of the operator's containers that exists.
//    vesselShipments.esangVesselSuggestion (EXISTS server/routers/vesselShipments.ts:4210 ·
//      vesselProcedure · input z.object({}).optional() · returns {headline,subline,kind,bookingNumber,
//      confidence,generatedAt}). Grounded ONLY on demurrage and ISF exposure and scoped
//      eq(vesselShipments.shipperId, userId) at vesselShipments.ts:4225 — shipper-scoped on an
//      operator screen, and carrying no stow grounding at all. The card renders its real text and
//      labels that limit directly beneath rather than passing it off as stow advice.
//    STUB · named-gap NO-STOW-READ: the data model exists and nothing exposes it. vesselCargoManifests
//      (drizzle/schema.ts:12091) carries voyageId, shipmentId, containerNumber, sealNumber,
//      cargoDescription, packageCount, grossWeightKg, volumeCBM, loadPortId, dischargePortId,
//      hazmatClass, temperatureRequired and stowagePosition varchar(20) (drizzle/schema.ts:12105) —
//      literally the bay-row-tier field — and the table has ZERO readers AND ZERO writers anywhere in
//      the repo outside the schema file. Proposed shape:
//      vesselStowage.getBayPlan({voyageId:number, bay:number}) returns {bay, stacks, tiers,
//      cells:[{bay,row,tier,containerNumber,grossWeightKg,hazmatClass,temperatureRequired,
//      dischargePortId}], unplaced:[containerNumber], stackWeightCapKg}.
//    STUB · named-gap NO-STOW-WRITE: there is no stowage write of any kind. Proposed shape:
//      vesselStowage.lockBayPlan({voyageId, bay, lockedBy}) returns {locked:Bool, lockedAt}. This
//      screen therefore ships NO lock CTA rather than a button that cannot lock.
//    STUB · named-gap NO-DG-JOIN: imdg.getCompliance (EXISTS server/routers/imdg.ts:13 ·
//      protectedProcedure · input {loadId:number} · impl server/services/IMDGService.ts:49) keys on a
//      ROAD loadId and shippingContainers carries no loadId column, so no box can be joined to a DG
//      record. The DG corner-notch is drawn in the CELL KEY as grammar and never painted on a cell.
//    CHAIN-OPEN: bay status change — WS_EVENTS.TERMINAL_BAY_STATUS (shared/websocket-events.ts:222)
//      exists and is the ONLY occurrence of that constant in the repo: zero emitters, zero
//      subscribers, so a bay-status change reaches nobody.
//    CHAIN-OPEN: lock bay plan — no procedure exists to write it, so nothing can broadcast.
//    HOUSE STANDARD cited for scoping, deliberately NOT used as a stow source:
//      terminals.getYardMap (EXISTS server/routers/terminals.ts:3565 · protectedProcedure · no input ·
//      tenancy CORRECT, eq(yardSpots.companyId, companyId) at terminals.ts:3573, ordered
//      locationId,row,col at terminals.ts:3574). It is a YARD grid, not a ship bay.
//    RBAC: vesselProcedure (server/_core/trpc.ts:268) is a MODE gate only — no tenant scoping and no
//      role-within-mode scoping.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. File-scoped types are suffixed 704 to
//  avoid cross-file private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen

struct VesselBayPlanScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0            // 0 = registry / zero-arg use

    init(theme: Theme.Palette, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselBayPlanBody704(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror the procedure returns EXACTLY)

/// SQL decimals reach the client as a JSON number OR a string. One tolerant decoder for both.
private struct FlexDouble704: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self)      { value = d }
        else if let i = try? c.decode(Int.self)    { value = Double(i) }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else                                       { value = nil }
    }
}

/// One row of `vesselShipments.getContainerPositions().containers` — a raw `shippingContainers` row
/// (drizzle/schema.ts:11852). Only the columns this screen reasons about are declared.
private struct BayBox704: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let isoType: String?
    let sizeType: String?
    let condition: String?
    let status: String?
    let assignedShipmentId: Int?
    let currentPortId: Int?
    let vgmGrossMassKg: FlexDouble704?
    let tareWeightKg: Int?
    let maxPayloadKg: Int?

    /// NO SOURCE — and deliberately expressed as a field rather than a hardcoded zero so that every
    /// count downstream derives from state. `getContainerPositions` returns `shippingContainers`
    /// columns only, and that table has no bay/row/tier column. The field that would carry it is
    /// `vesselCargoManifests.stowagePosition` (drizzle/schema.ts:12105) — zero readers, zero writers.
    var stowSlot: String? { nil }

    /// LIVE — reefer is real, straight off the size enum (drizzle/schema.ts:11856).
    var isReefer: Bool { (sizeType ?? "").lowercased().contains("reefer") }
    /// LIVE — SOLAS VI/2 verified gross mass (drizzle/schema.ts:11869).
    var vgmKg: Double? { vgmGrossMassKg?.value }
    var vgmVerified: Bool { (vgmGrossMassKg?.value ?? 0) > 0 }
}

private struct BayBoxResponse704: Decodable {
    let containers: [BayBox704]
    let total: Int?
}

/// `vesselShipments.esangVesselSuggestion` return (vesselShipments.ts:4210).
private struct EsangCard704: Decodable {
    let headline: String?
    let subline: String?
    let kind: String?
}

// MARK: - Body

private struct VesselBayPlanBody704: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    // Live rows only — no seeds, no demo arrays.
    @State private var boxes: [BayBox704] = []
    @State private var total: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var esang: EsangCard704? = nil
    @State private var esangGap: String? = nil
    @State private var readStamp: String = ""
    @State private var rechecking = false
    @State private var showGapDetail = false

    /// Operator SELECTION, not data — the stepper drives it. The lattice geometry it labels is a
    /// nominal display frame, which the pane states in as many words.
    @State private var bay: Int = 9

    // The lattice's nominal dimensions. Declared once so the strip, the pane and the copy agree.
    private let stacks = 9
    private let tiers  = 5
    private let planSlots = 10
    private let planRows  = 2

    // MARK: derived state — every figure below reads THIS state, never a parallel literal

    private var voyageBoxes: [BayBox704] {
        guard shipmentId > 0 else { return boxes }
        return boxes.filter { $0.assignedShipmentId == shipmentId }
    }
    private var placedCount: Int   { voyageBoxes.filter { $0.stowSlot != nil }.count }
    private var reeferCount: Int   { voyageBoxes.filter { $0.isReefer }.count }
    private var vgmVerifiedCount: Int { voyageBoxes.filter { $0.vgmVerified }.count }
    private var vgmMissingCount: Int  { max(0, voyageBoxes.count - vgmVerifiedCount) }
    private var resolvedStacks: Int {
        // A stack resolves only when at least one box claims a position in it. None can.
        placedCount > 0 ? min(stacks, placedCount) : 0
    }
    private var isEmpty: Bool { !loading && loadError == nil && voyageBoxes.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.top, Space.s4)

            VStack(alignment: .leading, spacing: Space.s5) {
                if let err = loadError {
                    errorCard(err)
                } else if loading {
                    loadingCard
                } else if isEmpty {
                    emptyCard
                } else {
                    heroPane
                    stackStrip
                    exceptionsCard
                    esangCard
                }

                if showGapDetail { gapDetailPanel }

                countryFooter
                ctaRow
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ VESSEL · BAY PLAN · STOW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("USLGB · VOYAGE 041E")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.top, Space.s5)

            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Bay plan")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                bayStepper
            }
            .padding(.top, Space.s4)

            Text(sublineText)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s5)
    }

    private var sublineText: String {
        if loading { return "Reading containers on this voyage…" }
        if loadError != nil { return "Container read unavailable" }
        let n = voyageBoxes.count
        return "\(n) box\(n == 1 ? "" : "es") on this voyage · \(placedCount) carr\(placedCount == 1 ? "ies" : "y") a row or tier"
    }

    private var bayStepper: some View {
        HStack(spacing: Space.s2) {
            Button { if bay > 1 { bay -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous bay")

            Text("BAY \(String(format: "%02d", bay))")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
                .frame(minWidth: 44)

            Button { if bay < 99 { bay += 1 } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next bay")
        }
        .padding(.horizontal, Space.s3)
        .frame(height: 26)
        .background(Capsule().fill(palette.bgCard))
        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: - HERO · dual-projection bay pane

    private var heroPane: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("BAY \(String(format: "%02d", bay)) · TWO PROJECTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                // Staleness is DRAWN: the read clock is stamped on the organ itself.
                Text(readStamp.isEmpty ? "READ —" : "READ \(readStamp)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .top, spacing: 0) {
                projectionLabel("ATHWARTSHIPS")
                Spacer(minLength: Space.s2)
                projectionLabel("PLAN VIEW")
            }

            BayLattice704(stacks: stacks, tiers: tiers,
                          planSlots: planSlots, planRows: planRows,
                          cardColor: palette.bgCard,
                          cellStroke: palette.borderSoft,
                          hatchColor: palette.textTertiary)

            HStack(alignment: .firstTextBaseline) {
                Text("\(stacks) STACKS · \(tiers) TIERS · BAR = HATCH COVER")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("ROWS 82 / 84 · SLOTS 01-\(planSlots)")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }

            cellKey

            // The drawn statement that no stow read exists.
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NO STOW READ · \(placedCount) OF \(voyageBoxes.count) BOXES PLACED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.danger)
                    Text("Lattice is nominal. No bay, row or tier position is reported for these boxes.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                StatusPill(text: "Gap", kind: .danger)
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.danger.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.35), lineWidth: 1))
            )
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl)
    }

    private func projectionLabel(_ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s)
                .font(.system(size: 8, weight: .bold)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(LinearGradient.primary)
                .frame(width: 18, height: 2)
        }
    }

    /// The cell grammar, shown as LABELLED SPECIMENS. Two of the four have no live source, so they
    /// appear here as vocabulary and are never painted onto a cell in the lattice above.
    private var cellKey: some View {
        HStack(spacing: 0) {
            keySpecimen(label: "POD · gap")      { AnyView(Text("LB").font(.system(size: 6, weight: .heavy)).foregroundStyle(palette.textSecondary)) }
            Spacer(minLength: Space.s1)
            keySpecimen(label: "Reefer · \(reeferCount)", notch: Brand.info) { AnyView(EmptyView()) }
            Spacer(minLength: Space.s1)
            keySpecimen(label: "DG · no join", notch: Brand.hazmat) { AnyView(EmptyView()) }
            Spacer(minLength: Space.s1)
            keySpecimen(label: "Unplaced", dashed: true) { AnyView(EmptyView()) }
        }
    }

    private func keySpecimen(label: String,
                             notch: Color? = nil,
                             dashed: Bool = false,
                             @ViewBuilder glyph: () -> AnyView) -> some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(width: 18, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(dashed ? palette.borderSoft : palette.borderStrong,
                                          style: StrokeStyle(lineWidth: 1.2,
                                                             dash: dashed ? [2, 2] : []))
                    )
                    .overlay(glyph())
                if let notch {
                    Rectangle().fill(notch).frame(width: 3, height: 3)
                }
            }
            .frame(width: 18, height: 14)

            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: - MID-BAND · stack-weight column strip

    private var stackStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("STACK WEIGHT · \(stacks) STACKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("\(voyageBoxes.count) BOXES · \(placedCount) PLACED")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(spacing: Space.s2) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("STACK CAP")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.danger)
                    Text("NO SOURCE")
                        .font(.system(size: 8, weight: .bold)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            ZStack {
                // Nine 28-wide column ENVELOPES. Height would be accumulated tier weight; with no
                // placement there is nothing to accumulate, so the silhouettes stay empty.
                HStack(spacing: Space.s2) {
                    ForEach(Array(0..<stacks), id: \.self) { _ in
                        ZStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(palette.borderSoft,
                                              style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
                            VStack(spacing: 0) {
                                ForEach(Array(1..<max(tiers, 2)), id: \.self) { _ in
                                    Spacer(minLength: 0)
                                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 58)

                // The red cap rule across all nine, at the top of the plot.
                VStack(spacing: 0) {
                    HRule704()
                        .stroke(Brand.danger, style: StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
                        .frame(height: 2)
                    Spacer(minLength: 0)
                }
                .frame(height: 58)

                Text("\(resolvedStacks) OF \(stacks) RESOLVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, Space.s4)
                    .frame(height: 24)
                    .background(
                        Capsule().fill(palette.bgCard)
                            .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.35), lineWidth: 1))
                    )
            }
            .frame(height: 58)

            Rectangle().fill(palette.borderSoft).frame(height: 1)

            Text("Column height is accumulated tier weight — none can be computed.")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Exception callouts keyed to bay coordinates

    private var exceptionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXCEPTIONS · BAY \(String(format: "%02d", bay))")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)

            exceptionRow(key: "\(String(format: "%02d", bay))-··-··",
                         reason: "No row or tier for any box",
                         pill: "No reader", kind: .danger)
            Divider().overlay(palette.borderFaint)
            exceptionRow(key: "\(String(format: "%02d", bay))-DG-··",
                         reason: "DG keys on load, not container",
                         pill: "No join", kind: .warning)
            Divider().overlay(palette.borderFaint)
            exceptionRow(key: "\(String(format: "%02d", bay))-VGM-·",
                         reason: vgmMissingCount > 0
                            ? "\(vgmMissingCount) of \(voyageBoxes.count) boxes have no verified mass"
                            : "Mass reads per box, not per stack",
                         pill: vgmMissingCount > 0 ? "Blocking" : "Live",
                         kind: vgmMissingCount > 0 ? .danger : .success)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func exceptionRow(key: String, reason: String, pill: String, kind: StatusPill.Kind) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(key)
                .font(EType.mono(.caption)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 60, alignment: .leading)
            Text(reason)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s2)
            StatusPill(text: pill, kind: kind)
        }
        .padding(.vertical, Space.s2)
    }

    // MARK: - ESang

    private var esangCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1))
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("DEMURRAGE / ISF READ")
                    .font(.system(size: 9, weight: .bold)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            if let e = esang, let head = e.headline, !head.isEmpty {
                Text(head)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = e.subline, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let gap = esangGap {
                Text("ESang read unavailable")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(gap)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The limit of the read, stated on the screen rather than implied away.
            Text("ESang has no stow input; this read is demurrage and ISF only, and it is scoped to the shipper.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Gap detail (what the "Stow gap detail" CTA opens)

    private var gapDetailPanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("STOW GAP DETAIL")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            gapLine("NO-STOW-READ",
                    "vessel_cargo_manifests.stowagePosition exists in the schema and has zero readers and zero writers. Proposed: vesselStowage.getBayPlan({voyageId, bay}).")
            gapLine("NO-STOW-WRITE",
                    "No stowage write of any kind exists, so the plan cannot be locked. Proposed: vesselStowage.lockBayPlan({voyageId, bay, lockedBy}).")
            gapLine("NO-DG-JOIN",
                    "imdg.getCompliance keys on a road loadId; a container carries none, so no DG notch can be resolved.")
            gapLine("CHAIN-OPEN",
                    "TERMINAL_BAY_STATUS is defined with zero emitters and zero subscribers — a bay-status change reaches nobody.")
            gapLine("P0-READ-TENANCY",
                    "getContainerPositions takes no ctx, so the read spans every tenant — \(total) container\(total == 1 ? "" : "s") platform-wide reached this device, filtered to \(voyageBoxes.count) here on the client, not on the server.")
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func gapLine(_ tag: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(Brand.danger)
            Text(body)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Country footer (small footer, never a feature organ)

    private var countryFooter: some View {
        HStack(spacing: Space.s3) {
            countryChip("US", active: true, label: "USLGB · VGM")
            countryChip("CA", active: false, label: "CAVAN · TC")
            countryChip("MX", active: false, label: "MXZLO · SEMAR")
            Spacer(minLength: Space.s1)
            Text("ALL 3 · NO READ")
                .font(.system(size: 8, weight: .bold)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func countryChip(_ code: String, active: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            Text(code)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(active ? Color.white : palette.textSecondary)
                .frame(width: 20, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.tintNeutral))
                )
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    // MARK: - CTA pair (216 + 176 — off both stamped tails)

    private var ctaRow: some View {
        GeometryReader { g in
            let gap: CGFloat = Space.s2
            let w = max(g.size.width - gap, 1)
            HStack(spacing: gap) {
                CTAButton(title: "Recheck placements",
                          action: { Task { await recheck() } },
                          isLoading: rechecking)
                    .frame(width: w * (216.0 / 392.0))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showGapDetail.toggle() }
                } label: {
                    Text(showGapDetail ? "Hide gap detail" : "Stow gap detail")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(palette.bgCard)
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(palette.borderSoft, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .frame(width: w * (176.0 / 392.0))
            }
        }
        .frame(height: 48)
        .padding(.bottom, Space.s4)
    }

    // MARK: - Non-happy states (bespoke, never fabricated rows)

    private var loadingCard: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Reading containers on this voyage…")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NO CONTAINERS ON THIS VOYAGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("The container read returned nothing to place.")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text("There is no bay to draw until boxes are assigned to this voyage. Nothing here is filled in on your behalf.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("CONTAINER READ FAILED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("No lattice is drawn from a failed read.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintDanger)
        )
    }

    // MARK: - load · real calls only, unconditional overwrite

    private func load() async {
        loading = true; loadError = nil
        struct BayIn704: Encodable { let status: String?; let limit: Int }
        do {
            let resp: BayBoxResponse704 = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions",
                input: BayIn704(status: nil, limit: 200))
            boxes = resp.containers                    // UNCONDITIONAL — an empty list clears the pane
            total = resp.total ?? resp.containers.count
            readStamp = Self.clock()
        } catch {
            boxes = []
            total = 0
            loadError = error.eusoUserCopy
            loading = false
            return
        }
        await loadEsang()
        loading = false
    }

    /// Real ESang read. On failure the card states the gap; it never falls back to written copy.
    private func loadEsang() async {
        esangGap = nil
        do {
            let card: EsangCard704 = try await EusoTripAPI.shared
                .queryNoInput("vesselShipments.esangVesselSuggestion")
            esang = card
        } catch {
            esang = nil
            esangGap = error.eusoUserCopy
        }
    }

    private func recheck() async {
        rechecking = true
        await load()
        rechecking = false
    }

    private static func clock() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
}

// MARK: - The dual-projection lattice (hero organ)

/// Cross-section beside plan view, joined by three 1.2-stroke correspondence rules. Every cell is
/// drawn in the UNPLACED grammar — a card-coloured gap behind a 1.2 dashed stroke — because no
/// procedure returns a position for any box. Nothing here is ever filled from a guess.
private struct BayLattice704: View {
    let stacks: Int
    let tiers: Int
    let planSlots: Int
    let planRows: Int
    let cardColor: Color
    let cellStroke: Color
    let hatchColor: Color

    // Vertical rhythm, mirrored from the SVG: rowA 0..14, rowB 16..30, hatch 33..38,
    // rowC 41..55, rowD 57..71, rowE 73..87. Plan block (34 tall) centres at 26.5..60.5.
    private let blockHeight: CGFloat = 87
    private let planBlockHeight: CGFloat = 34

    var body: some View {
        GeometryReader { g in
            let channel: CGFloat = 10
            let unit = max(g.size.width - channel, 1)
            let crossW = unit * (176.0 / 370.5)
            let planW  = unit * (194.5 / 370.5)
            let cGap: CGFloat = 1.75
            let cCell = max((crossW - cGap * CGFloat(stacks - 1)) / CGFloat(stacks), 3)
            let pGap: CGFloat = 0.5
            let pCell = max((planW - pGap * CGFloat(planSlots - 1)) / CGFloat(planSlots), 3)
            let lead = min(18, cCell * 1.2)

            ZStack(alignment: .topLeading) {
                HStack(alignment: .center, spacing: channel) {
                    // --- athwartships cross-section ---
                    VStack(spacing: 0) {
                        tierRow(cell: cCell, gap: cGap, height: 14)
                        Color.clear.frame(height: 2)
                        tierRow(cell: cCell, gap: cGap, height: 14)
                        Color.clear.frame(height: 3)
                        // hatch cover — the rule that splits on-deck from in-hold
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(hatchColor.opacity(0.55))
                            .frame(width: crossW, height: 5)
                        Color.clear.frame(height: 3)
                        tierRow(cell: cCell, gap: cGap, height: 14)
                        Color.clear.frame(height: 2)
                        tierRow(cell: cCell, gap: cGap, height: 14)
                        Color.clear.frame(height: 2)
                        tierRow(cell: cCell, gap: cGap, height: 14)
                    }
                    .frame(width: crossW, height: blockHeight)

                    // --- plan view of the same bay ---
                    VStack(spacing: 2) {
                        ForEach(Array(0..<planRows), id: \.self) { _ in
                            HStack(spacing: pGap) {
                                ForEach(Array(0..<planSlots), id: \.self) { _ in
                                    unplacedCell(w: pCell, h: 16)
                                }
                            }
                        }
                    }
                    .frame(width: planW, height: planBlockHeight)
                }
                .frame(height: blockHeight)

                // --- three correspondence rules, with an 18pt lead inside each projection ---
                Canvas { ctx, _ in
                    let pairs: [(CGFloat, CGFloat)] = [(7, 34.5), (35.5, 43.5), (64, 52.5)]
                    let grad = Gradient(colors: [Brand.blue, Brand.magenta])
                    for (ya, yb) in pairs {
                        var p = Path()
                        p.move(to: CGPoint(x: crossW - lead, y: ya))
                        p.addLine(to: CGPoint(x: crossW, y: ya))
                        p.addLine(to: CGPoint(x: crossW + channel, y: yb))
                        p.addLine(to: CGPoint(x: crossW + channel + lead, y: yb))
                        ctx.stroke(p,
                                   with: .linearGradient(grad,
                                                         startPoint: CGPoint(x: crossW - lead, y: 0),
                                                         endPoint: CGPoint(x: crossW + channel + lead, y: 0)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                        ctx.fill(Path(ellipseIn: CGRect(x: crossW - lead - 2, y: ya - 2, width: 4, height: 4)),
                                 with: .color(Brand.blue))
                        ctx.fill(Path(ellipseIn: CGRect(x: crossW + channel + lead - 2, y: yb - 2, width: 4, height: 4)),
                                 with: .color(Brand.magenta))
                    }
                }
                .frame(height: blockHeight)
                .allowsHitTesting(false)
            }
        }
        .frame(height: blockHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bay lattice, \(stacks) stacks by \(tiers) tiers beside a \(planRows) by \(planSlots) plan view. Every slot is unplaced because no stow position is published.")
    }

    private func tierRow(cell: CGFloat, gap: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(0..<stacks), id: \.self) { _ in
                unplacedCell(w: cell, h: height)
            }
        }
    }

    private func unplacedCell(w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(cardColor)
            .frame(width: w, height: h)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(cellStroke, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            )
    }
}

/// A single horizontal rule, so the stack cap can be dashed without a Canvas.
private struct HRule704: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

#Preview("704 Bay Plan · Light") {
    VesselBayPlanScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#Preview("704 Bay Plan · Dark") {
    VesselBayPlanScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
