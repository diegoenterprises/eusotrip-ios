//
//  826_VesselSlotAllocation.swift
//  EusoTrip — Vessel Operator · VSA Slot Allocation (826).
//
//  Verbatim-composition port of "826 Vessel Slot Allocation.svg" (Dark =
//  Theme.dark palette-swap → Light). PARTNER ALLOCATION-BAR + SAILING-MATRIX
//  archetype — a vessel-sharing-agreement slot board for one service loop:
//  this-loop utilisation + blanked-sailing hero, a next-sailings strip (a
//  cancelled voyage IS a BLANK to reallocate), and per-partner allocation
//  bars. Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS ·
//  [orb] · COMPLIANCE · ME), Shipments tab current.
//
//  WIRING (honest):
//    Sailings are REAL — blankSailing.dashboard (blankSailing.ts:44, vesselProcedure)
//        → { summary:{cancelledSailings, scheduledSailings},
//            cancelledVoyages:[voyage], scheduledVoyages:[voyage] }.
//      A cancelled voyage renders as the BLANK sailing to reallocate.
//    There is NO slot-allocation / VSA model on disk (grep slot/VSA = 0) →
//      STUB · named-gap handed to the-oath: vessel.getSlotAllocation({loopId})
//      + vessel.reallocateSlots({loopId,week,moves,confirm:true}). The
//      partner-allocation bars render from that model once it exists; until
//      then they show an honest awaiting-state (never fabricated TEU).
//    Reallocate slots → proposed vessel.reallocateSlots (moves sellable
//      capacity → gated + confirm:true + blockchainAuditTrail
//      vessel.slots_reallocated). No dedicated mutation yet.
//    COUNTRY: US FMC VSA filing active · CA CTA conference · MX SCT (standby).
//

import SwiftUI

struct VesselSlotAllocationScreen: View {
    let theme: Theme.Palette
    var loopId: String = "TP6"

    var body: some View {
        Shell(theme: theme) {
            VesselSlotAllocationBody(loopId: loopId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (blankSailing.dashboard → vesselVoyages rows, permissive)

private struct SlotVoyage826: Decodable, Identifiable {
    let id: Int?
    let voyageNumber: String?
    let vesselName: String?
    let serviceLoop: String?
    let status: String?
    var rowId: String { voyageNumber ?? (id.map(String.init) ?? UUID().uuidString) }
}

private struct SlotDashboard826: Decodable {
    struct Summary: Decodable { let cancelledSailings: Int?; let scheduledSailings: Int? }
    let summary: Summary?
    let cancelledVoyages: [SlotVoyage826]?
    let scheduledVoyages: [SlotVoyage826]?
}

// MARK: - Body

private struct VesselSlotAllocationBody: View {
    @Environment(\.palette) private var palette
    let loopId: String

    @State private var dash: SlotDashboard826? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var scheduledCount: Int { dash?.summary?.scheduledSailings ?? (dash?.scheduledVoyages?.count ?? 0) }
    private var blankedCount: Int { dash?.summary?.cancelledSailings ?? (dash?.cancelledVoyages?.count ?? 0) }
    private var totalSailings: Int { scheduledCount + blankedCount }

    /// Schedule reliability — the one real, derived slot-board metric we can
    /// compute honestly from live voyages (kept vs blanked). NOT TEU
    /// utilisation (that needs the VSA slot model), so it is labelled as
    /// reliability, never fabricated as capacity.
    private var reliabilityPct: Int {
        guard totalSailings > 0 else { return 0 }
        return Int((Double(scheduledCount) / Double(totalSailings) * 100).rounded())
    }

    /// The next sailings strip = up to 3 upcoming voyages, blanked ones
    /// (cancelled) flagged as void → reallocate.
    private var sailings: [(voyage: SlotVoyage826, blank: Bool)] {
        let scheduled = (dash?.scheduledVoyages ?? []).map { ($0, false) }
        let cancelled = (dash?.cancelledVoyages ?? []).map { ($0, true) }
        return Array((scheduled + cancelled).prefix(3)).map { (voyage: $0.0, blank: $0.1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · VSA SLOTS",
                caption: "GEMINI COOP",
                title: "Slot allocation"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    utilisationHero
                    sailingsSection
                    partnerSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE ACTIVE GATED",
                        reference: "slots · country",
                        rows: [
                            .init("US", "FMC VSA filing · USLGB call", active: true),
                            .init("CA", "CTA conference · CAVAN call"),
                            .init("MX", "SCT · MXZLO transshipment")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Verified sailing capacity is shown above. Partner-level TEU allocations appear only after a signed VSA allocation is linked.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Utilisation hero (loop context · reliability · blanked at-risk)

    private var utilisationHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("\(loopLabel) · weekly")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x5AB0FF)).frame(width: 6, height: 6)
                        Text("GEMINI VSA")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Color(hex: 0x5AB0FF))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0x5AB0FF).opacity(0.14)))
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reliabilityPct)%")
                            .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(reliabilityPct >= 85 ? Color(hex: 0x34D8A6)
                                             : reliabilityPct >= 60 ? Color(hex: 0xFFC246) : Brand.danger)
                        Text("THIS-LOOP SCHEDULE RELIABILITY")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(scheduledCount) sailing\(scheduledCount == 1 ? "" : "s") kept · \(totalSailings) planned")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(blankedCount) blank")
                            .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(blankedCount > 0 ? Color(hex: 0xFF6F61) : Color(hex: 0x34D8A6))
                        Text(blankedCount > 0 ? "to reallocate" : "loop clean")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var loopLabel: String {
        (dash?.scheduledVoyages?.first?.serviceLoop
         ?? dash?.cancelledVoyages?.first?.serviceLoop
         ?? "\(loopId) Transpacific")
    }

    // MARK: - Sailings strip (next 3 · real voyages · BLANK flag)

    private var sailingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "SAILINGS · NEXT 3", right: "blankSailing.dashboard")
            if sailings.isEmpty {
                EusoEmptyState(systemImage: "sailboat",
                               title: "No sailings on this loop",
                               subtitle: "Scheduled and blanked voyages for the loop appear here once the schedule service responds.")
            } else {
                HStack(spacing: Space.s2) {
                    ForEach(Array(sailings.enumerated()), id: \.offset) { _, item in
                        sailingCard(item.voyage, blank: item.blank)
                    }
                }
            }
        }
    }

    private func sailingCard(_ v: SlotVoyage826, blank: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v.voyageNumber ?? "—")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
            Text(blank ? "BLANK" : "SAILING")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(blank ? Color(hex: 0xFF6F61) : Color(hex: 0x34D8A6))
            Text(blank ? "void → reallocate" : (v.vesselName ?? "scheduled"))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    if !blank {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(hex: 0x34D8A6))
                            .frame(width: 40, height: 4)
                    }
                }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(blank ? Color(hex: 0xFF6F61).opacity(0.35) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Partner allocation bars (STUB · getSlotAllocation)

    private var partnerSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "PARTNER ALLOCATION", right: "VSA REQUIRED")
            EusoEmptyState(systemImage: "chart.bar.xaxis",
                           title: "Per-partner slots awaiting the VSA model",
                           subtitle: "Own-vessel, alliance, purchased, swap, and spot allocations appear after a signed VSA allocation is linked.")
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Reallocate slots", action: {}, trailingIcon: "arrow.left.arrow.right")
            VesselGhostButton(title: "Loop schedule", width: 150) {
                VesselOperatorNavDispatcher.handle("shipments")
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 132)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 90)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
        }
    }

    // MARK: - Load (REAL: blankSailing.dashboard)

    private func load() async {
        loading = true; loadError = nil
        do {
            let d: SlotDashboard826 = try await EusoTripAPI.shared.queryNoInput("blankSailing.dashboard")
            self.dash = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("826 · Vessel Slot Allocation · Night") {
    VesselSlotAllocationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("826 · Vessel Slot Allocation · Light") {
    VesselSlotAllocationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
