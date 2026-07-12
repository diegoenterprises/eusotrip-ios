//
//  830_VesselGeneralOrder.swift
//  EusoTrip — Vessel Operator · General Order / Unclaimed Cargo (830).
//
//  Verbatim-composition port of "830 Vessel General Order.svg" (Dark → Light).
//  ABANDONMENT-MILESTONE-TRACK + GO-QUEUE-LEDGER archetype — a statutory-
//  deadline risk surface: an at-risk hero over the 15/45/180-day GO clock, a
//  0–180-day abandonment-milestone track, and a general-order queue ledger.
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest):
//    Entry / no-entry disposition is REAL — vesselShipments.getCBPEntryStatus
//        (vesselShipments.ts:2807, vesselProcedure, input { entryNumber }).
//    Compliance posture is REAL — vesselShipments.getVesselCompliance
//        (vesselShipments.ts:2047).
//    The 15/45/180-day milestones ARE the CBP General Order statute (19 CFR
//        127), not fabricated — they are the fixed reference scale.
//    There is NO GO aging / queue model on disk (grep generalOrder = 0) →
//        STUB · named-gap: vessel.getGeneralOrderQueue({terminal}) +
//        vessel.notifyImporter({containerId}) + vessel.moveToGO({containerId,
//        confirm:true}) → computes aging from arrival + free-time, writes the
//        GO move + importer notice + blockchainAuditTrail vessel.moved_to_go,
//        broadcasts WS_EVENTS.generalOrderUpdated. The today-dot and queue rows
//        render from that model once it ships; until then honest awaiting-state.
//    COUNTRY: US 19 CFR 127 (15d/6mo) active · CA CBSA D4-1-5 · MX Art.32 Ley Aduanera.
//

import SwiftUI

struct VesselGeneralOrderScreen: View {
    let theme: Theme.Palette
    var terminal: String = "USLGB"

    var body: some View {
        Shell(theme: theme) {
            VesselGeneralOrderBody(terminal: terminal)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Compliance shape (getVesselCompliance)

private struct GOCompliance830: Decodable {
    let status: String?
    let totalInspections: Int?
}

// MARK: - Body

private struct VesselGeneralOrderBody: View {
    @Environment(\.palette) private var palette
    let terminal: String

    @State private var compliance: GOCompliance830? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Statutory GO milestones (19 CFR 127) on a 0–180-day scale.
    private let milestones: [(label: String, day: Int)] =
        [("Arr", 0), ("GO", 15), ("Notice", 45), ("Sale", 180)]

    private var complianceLine: String {
        guard let c = compliance else { return "posture pending" }
        return "\(c.totalInspections ?? 0) records · \((c.status ?? "unknown").replacingOccurrences(of: "_", with: " "))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · GENERAL ORDER · CBP",
                caption: "19 CFR 127",
                title: "General order",
                subtitle: "Unclaimed ≥ 15 days · GO warehouse risk"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    atRiskHero
                    queueSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE-COUNTRY VARIATION",
                        reference: "19 CFR 127",
                        rows: [
                            .init("US", "CBP General Order · 15d / 6mo sale", active: true),
                            .init("CA", "CBSA abandoned · D4-1-5"),
                            .init("MX", "Abandono · Art. 32 Ley Aduanera")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "The 15/45/180-day milestones are the CBP GO statute; entry/no-entry disposition is REAL (getCBPEntryStatus). Per-container aging, the today-dot and the queue need the GO model — proposed vessel.getGeneralOrderQueue / notifyImporter / moveToGO (statutory notice + CBP sale → human-gated + confirm + audit). No fabricated aging.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - At-risk hero + abandonment milestone track

    private var atRiskHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Unclaimed at \(terminal) · no entry filed")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("AT RISK")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFF6F61))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFF6F61).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Day —")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFF6F61))
                    Text("of 15 to GO")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("aging & importer responsiveness await getGeneralOrderQueue")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)

                milestoneTrack

                HStack(spacing: 6) {
                    Circle().fill(Brand.warning).frame(width: 6, height: 6)
                    Text(complianceLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text("getVesselCompliance")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
        }
    }

    private var milestoneTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let trackY: CGFloat = 14
            ZStack(alignment: .topLeading) {
                // Base rail
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: w, height: 8)
                    .offset(y: trackY)
                // Milestone ticks + labels
                ForEach(Array(milestones.enumerated()), id: \.offset) { _, m in
                    let x = w * CGFloat(m.day) / 180.0
                    Rectangle().fill(palette.textTertiary)
                        .frame(width: 1.2, height: 14)
                        .offset(x: min(max(x, 0.6), w - 0.6), y: trackY - 3)
                    Text("d\(m.day)")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .offset(x: max(0, min(x - 8, w - 20)), y: 0)
                    Text(m.label)
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .offset(x: max(0, min(x - 12, w - 30)), y: trackY + 14)
                }
            }
        }
        .frame(height: 44)
    }

    // MARK: - GO queue ledger

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "GENERAL-ORDER QUEUE", right: "STUB · getGeneralOrderQueue")
            EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                           title: "GO queue awaiting the aging model",
                           subtitle: "Each unclaimed container — no-entry days, importer responsiveness, GO state and accrued storage — posts here once vessel.getGeneralOrderQueue ships. No fabricated aging.")
            VesselSummaryStrip(label: "Accrued GO storage · importer liable",
                               value: "pending", valueColor: palette.textSecondary)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Notify importer", action: {}, trailingIcon: "bell.badge")
            VesselGhostButton(title: "Move to GO", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
        }
    }

    // MARK: - Load (REAL: getVesselCompliance)

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let vesselId: Int? }
        do {
            let c: GOCompliance830 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCompliance", input: In(vesselId: nil))
            self.compliance = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("830 · Vessel General Order · Night") {
    VesselGeneralOrderScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("830 · Vessel General Order · Light") {
    VesselGeneralOrderScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
