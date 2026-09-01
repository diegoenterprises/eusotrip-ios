//
//  833_VesselLashingSecuringPlan.swift
//  EusoTrip — Vessel Operator · Lashing & Securing Plan (833).
//
//  Verbatim-composition port of "833 Vessel Lashing & Securing Plan.svg" (Dark →
//  Light). TIER-FORCE-WORKSHEET + ESANG-ADVISORY archetype — a departure
//  securing check: a peak-force / MSL hero, a per-tier securing-force worksheet
//  (T90→T82, twist-lock / rod / bridge), an ESANG next-best-move card, and the
//  securing-authority band. Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current)
//  · ME.
//
//  WIRING (honest):
//    Stow context is REAL — vesselShipments.getVesselShipmentDetail
//        (vesselShipments.ts:561, vesselProcedure, input { id }) → { shipment,
//        containers, … }; bay / vessel drive the hero when a booking is loaded.
//    The CSS Code (IMO MSC.1/Circ.1353) is the real securing standard, not
//        fabricated — it is the fixed reference.
//    There is NO securing model on disk (tier forces, MSL %, twist-lock counts;
//        grep securing = 0) → STUB · named-gap: vessel.getSecuringPlan({bayId})
//        + vessel.approveSecuringPlan({bayId,confirm:true}) → writes the
//        securing_approvals row + blockchainAuditTrail vessel.securing_approved,
//        broadcasts WS_EVENTS.SECURING_APPROVED. Per-tier securing forces + the
//        ESANG re-lash recommendation render from that model once it ships;
//        until then the worksheet + advisory show honest awaiting-states.
//    COUNTRY: US USCG 33 CFR 154 active · CA TP 15211 · MX SEMAR DGMM.
//

import SwiftUI

struct VesselLashingSecuringPlanScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var bayId: String = "18"

    var body: some View {
        Shell(theme: theme) {
            VesselLashingSecuringPlanBody(shipmentId: shipmentId, bayId: bayId)
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

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct SecuringShipment833: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
}
private struct SecuringDetail833: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: SecuringShipment833?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(SecuringShipment833.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? SecuringShipment833(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Body

private struct VesselLashingSecuringPlanBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let bayId: String

    @State private var shipment: SecuringShipment833? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Physical on-deck tiers for the bay (odd tiers, high→low). The tier
    // structure is real stow geometry; the securing FORCE per tier comes from
    // getSecuringPlan (STUB) and is shown pending, never fabricated.
    private let tiers = ["T90", "T88", "T86", "T84", "T82"]

    private var vesselLine: String {
        if let s = shipment {
            return "Bay \(bayId) · \(s.vesselName ?? "on-deck stack") · CSS Code MSC.1/Circ.1353"
        }
        return "Bay \(bayId) · MSC ANL Tongala · CSS Code MSC.1/Circ.1353"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · LASHING & SECURING",
                caption: "MSC · USCG",
                title: "Securing plan",
                subtitle: vesselLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    securingHero
                    tierSection
                    esangCard
                    VesselRegulatorBand(
                        title: "SECURING AUTHORITY · SINGLE-COUNTRY",
                        reference: "securing · country",
                        rows: [
                            .init("US", "USCG 33 CFR 154 · CSM approved", active: true),
                            .init("CA", "Transport Canada TP 15211"),
                            .init("MX", "SEMAR DGMM · NOM securing")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Stow context is verified and CSS Code MSC.1/Circ.1353 governs securing. No approved tier-level securing plan is linked.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Securing hero (peak force / MSL)

    private var securingHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("On-deck stack · tiers 82–90 · departure check")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("MSL PENDING")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("—%")
                        .font(.system(size: 32, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: 0xFFC246))
                    Text("peak force / MSL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("verified twist-lock · rod · bridge counts required")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(height: 8)
            }
        }
    }

    // MARK: - Tier force worksheet (scaffold · forces pending)

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "TIER ELEVATION · SECURING FORCE", right: "APPROVED PLAN REQUIRED")
            VesselGroupCard {
                VStack(spacing: 0) {
                    ForEach(Array(tiers.enumerated()), id: \.offset) { idx, tier in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        tierRow(tier)
                    }
                }
            }
            legendRow
        }
    }

    private func tierRow(_ tier: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(tier)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 34, alignment: .leading)
            // Method schema chip (twist-lock corner markers)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x5AB0FF)).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x5AB0FF)).frame(width: 5, height: 5)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(palette.borderSoft, lineWidth: 1))
            // Empty force track (populates from getSecuringPlan)
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(height: 9)
            Text("—%")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            legendChip("Twist-lock", Color(hex: 0x5AB0FF))
            legendChip("Rod", Color(hex: 0x34D8A6))
            legendChip("Bridge", Color(hex: 0x9B6BFF))
            legendChip(">90% watch", Color(hex: 0xFFC246))
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - ESANG AI advisory card

    private var esangCard: some View {
        VesselGroupCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 8) {
                    OrbeSang(state: .idle, diameter: 22)
                    Text("ESANG AI")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                    Spacer(minLength: 6)
                    Text("next best move")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Re-lash recommendation loads with securing forces")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Once verified tier MSL values are available, ESANG can recommend a re-lash before the departure gate.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Approve securing", action: {}, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Lashing log", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 220)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 80)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: SecuringDetail833? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("833 · Vessel Lashing & Securing · Night") {
    VesselLashingSecuringPlanScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("833 · Vessel Lashing & Securing · Light") {
    VesselLashingSecuringPlanScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
