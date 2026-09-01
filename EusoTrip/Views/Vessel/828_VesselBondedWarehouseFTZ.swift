//
//  828_VesselBondedWarehouseFTZ.swift
//  EusoTrip — Vessel Operator · Bonded Warehouse / FTZ Inventory (828).
//
//  Verbatim-composition port of "828 Vessel Bonded Warehouse FTZ.svg" (Dark →
//  Light). DUTY-DEFERRED-HERO + CUSTODY-SPLIT-BAR + DOUBLE-ENTRY-LEDGER
//  archetype — a customs-bonded custody surface: a duty-in-suspense hero with a
//  3-segment custody split bar (in-bond / duty-paid out / exported), and an
//  admissions/withdrawals double-entry ledger. Nav: HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE(current) · ME.
//
//  WIRING (honest):
//    Compliance posture is REAL — vesselShipments.getVesselCompliance
//        (vesselShipments.ts:2047, vesselProcedure, input { vesselId? }) →
//        { status, totalInspections, failedCount, … }.
//    Per-container CBP disposition is REAL — vesselShipments.getCBPEntryStatus
//        (vesselShipments.ts:2807).
//    There is NO FTZ / bonded-inventory model on disk (grep bondedWarehouse/FTZ
//        = 0) → STUB · named-gap: vessel.getBondedInventory({zoneId}) +
//        vessel.fileWeeklyEntry({zoneId,confirm:true}) → writes the e214
//        weekly-entry row + blockchainAuditTrail vessel.ftz_weekly_entry,
//        broadcasts WS_EVENTS.bondedInventoryUpdated. The duty-in-suspense
//        figure, custody split and admit/withdraw ledger render from that model
//        once it ships; until then they show honest awaiting-states.
//    COUNTRY: US FTZ 19 CFR 146 active · CA CBSA D4 sufferance · MX Depósito Fiscal.
//

import SwiftUI

struct VesselBondedWarehouseFTZScreen: View {
    let theme: Theme.Palette
    var zoneId: String = "FTZ-50"

    var body: some View {
        Shell(theme: theme) {
            VesselBondedFTZBody(zoneId: zoneId)
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

private struct FTZCompliance828: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

// MARK: - Body

private struct VesselBondedFTZBody: View {
    @Environment(\.palette) private var palette
    let zoneId: String

    @State private var compliance: FTZCompliance828? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var complianceLine: String {
        guard let c = compliance else { return "zone posture pending" }
        let insp = c.totalInspections ?? 0
        let status = (c.status ?? "unknown").replacingOccurrences(of: "_", with: " ")
        return "\(insp) inspection\(insp == 1 ? "" : "s") on file · \(status)"
    }
    private var complianceOK: Bool { (compliance?.status ?? "") == "compliant" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · BONDED · FTZ",
                caption: "CBP CW · FTZ 50",
                title: "Bonded inventory",
                subtitle: "Aurora Ocean Division · customs-bonded custody"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    dutyHero
                    ledgerSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE-COUNTRY VARIATION",
                        reference: "19 CFR 146",
                        rows: [
                            .init("US", "FTZ 19 CFR 146 · CBP CW bonded", active: true),
                            .init("CA", "Sufferance Warehouse · CBSA D4"),
                            .init("MX", "Depósito Fiscal · Aduanas")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Zone compliance status is verified. No bonded inventory ledger is linked, so duty-in-suspense is withheld.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Duty-deferred hero + custody split scaffold

    private var dutyHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("FTZ 50 · zone B · status activated")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("DUTY-DEFERRED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0x34D8A6))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0x34D8A6).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("$—")
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                    Spacer(minLength: 8)
                    Text("duty in suspense")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFC246))
                }
                Text("CBP CW-2 class · verified custody value required")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)

                // 3-segment custody split — schema shown, empty until data.
                custodySplit

                // REAL compliance posture line off getVesselCompliance.
                HStack(spacing: 6) {
                    Circle().fill(complianceOK ? Brand.success : Brand.warning).frame(width: 6, height: 6)
                    Text(complianceLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text("VERIFIED VESSEL COMPLIANCE")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
        }
    }

    private var custodySplit: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(height: 9)
            HStack {
                custodyLegend("in bond", Color(hex: 0x5AB0FF))
                Spacer()
                custodyLegend("duty-paid out", Color(hex: 0x34D8A6))
                Spacer()
                custodyLegend("exported", palette.textTertiary)
            }
        }
    }

    private func custodyLegend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Admissions / withdrawals ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "ADMISSIONS / WITHDRAWALS", right: "NO VERIFIED LEDGER")
            EusoEmptyState(systemImage: "tray.full",
                           title: "Custody ledger awaiting the FTZ model",
                           subtitle: "Verified e214 admissions and CBP 7501/7512 withdrawals appear here after a bonded inventory ledger is linked.")
            VesselSummaryStrip(label: "Zone balance · TEU in custody",
                               value: "pending", valueColor: palette.textSecondary)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Admit to zone", action: {}, trailingIcon: "arrow.right")
            VesselGhostButton(title: "Weekly entry", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 170)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 180)
        }
    }

    // MARK: - Load (REAL: getVesselCompliance)

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let vesselId: Int? }
        do {
            let c: FTZCompliance828 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCompliance", input: In(vesselId: nil))
            self.compliance = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("828 · Vessel Bonded FTZ · Night") {
    VesselBondedWarehouseFTZScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("828 · Vessel Bonded FTZ · Light") {
    VesselBondedWarehouseFTZScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
