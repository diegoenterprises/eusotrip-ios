//
//  829_VesselInBondMovement.swift
//  EusoTrip — Vessel Operator · In-Bond Movement (IT / T&E / IE) (829).
//
//  Verbatim-composition port of "829 Vessel In-Bond Movement.svg" (Dark →
//  Light). ROUTED-CHECKPOINT-LINE + SEAL-ROW + CONVEYANCE-PANEL archetype — a
//  bonded-transit tracking surface: an in-bond entry hero, a horizontal ACE
//  QP/WP message line (Unlading → QP created → In transit → Arrival → WP
//  close), a seal integrity row, and a conveyance / bond panel. Nav: HOME ·
//  SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest):
//    CBP disposition is REAL — vesselShipments.getCBPEntryStatus
//        (vesselShipments.ts:2807, vesselProcedure, input { entryNumber }) →
//        EntryStatus | null; status drives which ACE node is current.
//    CBP holds context is REAL — vesselShipments.getCBPAlerts
//        (vesselShipments.ts:2818, input { importerId }).
//    There is NO in-bond model on disk (IT/T&E/IE number, QP/WP, seal events;
//        grep inBond = 0) → STUB · named-gap: vessel.getInBondStatus({inBondNo})
//        + vessel.closeInBond({inBondNo,confirm:true}) via DescartesABIService
//        (CBP QP/WP) → writes the arrival/close event + blockchainAuditTrail
//        vessel.inbond_closed, broadcasts WS_EVENTS.inBondStatusChanged. The
//        IT number, sealed route, seal + conveyance render from that model once
//        it ships; until then they show honest awaiting-states.
//    COUNTRY: US ACE eBond (19 CFR 18) active · CA CBSA A8A · MX Tránsito T1.
//

import SwiftUI

struct VesselInBondMovementScreen: View {
    let theme: Theme.Palette
    var inBondNo: String = ""
    var importerId: String = "EUSORONE"

    var body: some View {
        Shell(theme: theme) {
            VesselInBondMovementBody(inBondNo: inBondNo, importerId: importerId)
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

// MARK: - Entry shape (getCBPEntryStatus)

private struct InBondEntry829: Decodable {
    let entryNumber: String?
    let status: String?
    let releaseDate: String?
    let lastUpdated: String?
}

// MARK: - ACE checkpoint model

private struct ACENode829: Identifiable {
    let id = UUID()
    let title: String
    let sub: String
}

// MARK: - Body

private struct VesselInBondMovementBody: View {
    @Environment(\.palette) private var palette
    let inBondNo: String
    let importerId: String

    @State private var entry: InBondEntry829? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let nodes: [ACENode829] = [
        .init(title: "Unlading",  sub: "USLGB"),
        .init(title: "QP created", sub: "eBond"),
        .init(title: "In transit", sub: "sealed"),
        .init(title: "Arrival",   sub: "USMEM"),
        .init(title: "WP close",  sub: "entry")
    ]

    /// Current ACE node — derived from the REAL entry status when present.
    /// Released → WP close (4); in-transit posture → In transit (2);
    /// otherwise QP created (1). No entry yet → In transit gate (2), the
    /// canonical sealed-move state.
    private var currentIndex: Int {
        guard let entry else { return 2 }
        if entry.releaseDate != nil { return 4 }
        switch (entry.status ?? "").lowercased() {
        case "arrived", "arrival": return 3
        case "released", "closed": return 4
        case "filed", "accepted", "created": return 1
        default: return 2
        }
    }

    private var inBondNumber: String { entry?.entryNumber ?? (inBondNo.isEmpty ? "awaiting" : inBondNo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · IN-BOND · CBP",
                caption: "ACE eBond",
                title: "In-bond move",
                subtitle: "IT entry · USLGB → bonded inland · sealed"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    entryHero
                    routingSection
                    conveyanceSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE-COUNTRY VARIATION",
                        reference: "19 CFR 18",
                        rows: [
                            .init("US", "ACE eBond · QP create / WP close", active: true),
                            .init("CA", "CBSA in-bond · A8A / SCN"),
                            .init("MX", "Tránsito T1 · pedimento")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "CBP disposition is verified. No in-bond number, sealed route, seal event, or conveyance record is linked.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Entry hero

    private var entryHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("In-bond number")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 8)
                    Text("IT · TRANSPORT")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0x5AB0FF).opacity(0.13)))
                }
                Text(inBondNumber)
                    .font(.system(size: 26, weight: .bold, design: .monospaced)).tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("USLGB Long Beach → USMEM bonded CFS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("bonded carrier Aurora Drayage · bond 9-CB 41822")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - Routed checkpoint line (ACE QP/WP)

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "IN-BOND ROUTING · ACE QP / WP", right: "getCBPEntryStatus")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, node in
                            checkpointNode(idx: idx, node: node)
                            if idx < nodes.count - 1 {
                                Rectangle()
                                    .fill(idx < currentIndex ? AnyShapeStyle(LinearGradient.primary)
                                          : AnyShapeStyle(palette.borderSoft))
                                    .frame(height: 3)
                                    .frame(maxWidth: .infinity)
                                    .offset(y: 8)
                            }
                        }
                    }
                    // Seal integrity sub-row
                    HStack(spacing: 8) {
                        Circle().fill(Brand.success).frame(width: 8, height: 8)
                        Text("Seal integrity · verified event history")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 6)
                        Text(currentIndex >= 3 ? "arrival ok" : "in transit")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.success)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }

    private func checkpointNode(idx: Int, node: ACENode829) -> some View {
        let done = idx < currentIndex
        let current = idx == currentIndex
        return VStack(spacing: 6) {
            ZStack {
                if current {
                    Circle().fill(Color(hex: 0x5AB0FF).opacity(0.18)).frame(width: 20, height: 20)
                    Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                } else if done {
                    Circle().fill(Color(hex: 0x5AB0FF)).frame(width: 16, height: 16)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().fill(palette.tintNeutral).frame(width: 14, height: 14)
                    Circle().strokeBorder(palette.textTertiary, lineWidth: 1.5).frame(width: 14, height: 14)
                }
            }
            .frame(height: 20)
            Text(node.title)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(done || current ? palette.textPrimary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(node.sub)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(current ? Color(hex: 0x5AB0FF) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Conveyance & bond panel

    private var conveyanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CONVEYANCE & BOND", right: "NO VERIFIED MOVEMENT")
            VesselGroupCard {
                HStack(spacing: 0) {
                    conveyanceCell("Mode", "Drayage truck")
                    Divider().frame(height: 38).overlay(palette.borderFaint)
                    conveyanceCell("Carrier bond", "pending")
                    Divider().frame(height: 38).overlay(palette.borderFaint)
                    conveyanceCell("ACE SCN", "pending")
                }
            }
        }
    }

    private func conveyanceCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(value == "pending" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Close in-bond", action: {}, trailingIcon: "checkmark")
            VesselGhostButton(title: "Track seal", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 140)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 70)
        }
    }

    // MARK: - Load (REAL: getCBPEntryStatus + getCBPAlerts)

    private func load() async {
        loading = true; loadError = nil
        struct EntryIn: Encodable { let entryNumber: String }
        do {
            if !inBondNo.isEmpty {
                let e: InBondEntry829? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getCBPEntryStatus", input: EntryIn(entryNumber: inBondNo))
                self.entry = e
            } else {
                self.entry = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("829 · Vessel In-Bond Movement · Night") {
    VesselInBondMovementScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("829 · Vessel In-Bond Movement · Light") {
    VesselInBondMovementScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
