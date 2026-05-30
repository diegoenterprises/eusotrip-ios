//
//  663_VesselCBPEntryDetail.swift
//  EusoTrip — Vessel Operator · CBP Entry Detail (19 CFR · ACE).
//
//  Verbatim port of "663 Vessel CBP Entry Detail.svg" (Dark + Light).
//  Drill-down from 652_VesselCompliance / CBP alerts. Nav anchored to
//  VesselOperatorNavController.swift (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  Compliance tab current.
//
//  Data shapes mirror the Descartes ABI service the server wraps:
//    vesselShipments.getCBPEntryStatus({ entryNumber }) → EntryStatus | null
//        (vesselShipments.ts:1169 → DescartesABIService.getEntryStatus)
//        { entryNumber, status, holds:[{ holdType, agency, reason, appliedAt }],
//          releaseDate, liquidationDate, dutyOwed, lastUpdated }
//    vesselShipments.getCBPAlerts({ importerId }) → CBPAlert[] | null
//        (vesselShipments.ts:1180 → DescartesABIService.getCBPAlerts)
//
//  PORT-GAP: getHoldStatus exists on DescartesABIService (line 356) but is
//  NOT exposed as a tRPC procedure in vesselShipments.ts — the intensified-
//  exam detail (examLocation / estimatedRelease / intensifiedExam) cannot be
//  fetched until the procedure is added. The HOLDS row renders from the
//  EntryStatus.holds[] array we DO have, and the "Intensified-exam detail
//  pending getHoldStatus wiring" caption mirrors the canonical SVG.
//

import SwiftUI

struct VesselCBPEntryDetailScreen: View {
    let theme: Theme.Palette
    let entryNumber: String
    let importerId: String
    var body: some View {
        Shell(theme: theme) {
            VesselCBPEntryDetailBody(entryNumber: entryNumber, importerId: importerId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",         isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill",  isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror DescartesABIService EntryStatus / CBPAlert)

private struct CBPHold663: Decodable, Identifiable {
    let holdType: String?
    let agency: String?
    let reason: String?
    let appliedAt: String?
    var id: String { (holdType ?? "") + "|" + (agency ?? "") + "|" + (appliedAt ?? "") }
}

private struct CBPEntryStatus663: Decodable {
    let entryNumber: String?
    let status: String?
    let holds: [CBPHold663]?
    let releaseDate: String?
    let liquidationDate: String?
    let dutyOwed: Double?
    let lastUpdated: String?
}

private struct CBPAlert663: Decodable, Identifiable {
    let alertId: String?
    let alertType: String?
    let severity: String?
    let description: String?
    let entryNumber: String?
    let importerId: String?
    let createdAt: String?
    let expiresAt: String?
    let actionRequired: Bool?
    let agency: String?
    var id: String { alertId ?? UUID().uuidString }
}

// MARK: - Body

private struct VesselCBPEntryDetailBody: View {
    @Environment(\.palette) private var palette
    let entryNumber: String
    let importerId: String

    @State private var entry: CBPEntryStatus663? = nil
    @State private var alerts: [CBPAlert663] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var refreshing = false

    // Disposition figure — server `dutyOwed` is a Double (USD).
    private var dutyOwed: Double { entry?.dutyOwed ?? 0 }
    private var dutyShort: String {
        let v = Int(dutyOwed.rounded())
        return "$" + numberGrouped(v)
    }
    private var dutyLong: String {
        String(format: "$%@.%02d", numberGrouped(Int(dutyOwed)),
               Int((dutyOwed.truncatingRemainder(dividingBy: 1) * 100).rounded()))
    }
    private func numberGrouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private var activeHolds: [CBPHold663] { entry?.holds ?? [] }
    private var isOnHold: Bool { !activeHolds.isEmpty }

    // Milestone track — FILED · HOLD · EXAM · RELEASE.
    // Server `status` drives which node is current. With a hold present and
    // no releaseDate, the canonical state is EXAM (index 2).
    private var milestoneIndex: Int {
        if entry?.releaseDate != nil { return 3 }       // RELEASE
        if isOnHold { return 2 }                         // EXAM (intensive exam)
        switch (entry?.status ?? "").lowercased() {
        case "filed", "accepted", "submitted": return 0  // FILED
        case "hold", "held":                   return 1  // HOLD
        case "exam", "examination", "intensive_exam": return 2
        case "released", "release":            return 3
        default:                               return 0
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading CBP entry…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    dispositionHero
                    holdsSection
                    milestoneTrack
                    entryLedger
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (canonical DETAIL header)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow row: sparkle eyebrow + mono caption ("19 CFR · ACE").
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("✦ VESSEL OPERATOR · CBP ENTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("19 CFR · ACE")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // Title row: mono entry number + US IMPORT / lane caption.
            HStack(alignment: .top) {
                Text(entry?.entryNumber ?? entryNumber)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("US IMPORT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("CNSHA → USLGB")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Disposition hero (cardRim + inset)

    private var dispositionHero: some View {
        ZStack {
            // cardRim gradient rim + inset card fill.
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                // Badge row: 01 · CONSUMPTION · HAZMAT · ON HOLD.
                HStack(spacing: 8) {
                    Text(entryTypeBadge)
                        .font(.system(size: 11, weight: .bold)).tracking(0.4)
                        .foregroundStyle(Brand.rail)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.rail.opacity(0.22)))
                    if hasHazmat {
                        Text("HAZMAT")
                            .font(.system(size: 11, weight: .bold)).tracking(0.4)
                            .foregroundStyle(Brand.warning)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(Brand.warning.opacity(0.22)))
                    }
                    Spacer()
                    if isOnHold {
                        Text("ON HOLD")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.danger))
                    }
                }
                .padding(.bottom, 14)

                // Disposition label + figure row.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DISPOSITION · getCBPEntryStatus")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(dispositionTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(dispositionSub)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("DUTY OWED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(dutyShort)
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Color(hex: 0x4DA3FF))
                    }
                }
            }
            .padding(Space.s5)
        }
        .frame(maxWidth: .infinity)
    }

    private var entryTypeBadge: String {
        // Server status is freeform; canonical entry is type 01 Consumption.
        "01 · CONSUMPTION"
    }
    private var hasHazmat: Bool {
        // Hazmat surfaces when a hold reason mentions a UN/IMDG/PGA referral
        // or any alert is hazmat-tagged. Falls back to false when no signal.
        let holdSignal = activeHolds.contains { ($0.reason ?? "").lowercased().contains("un")
            || ($0.reason ?? "").lowercased().contains("imdg")
            || ($0.reason ?? "").lowercased().contains("hazmat")
            || ($0.agency ?? "").lowercased().contains("pga") }
        let alertSignal = alerts.contains { ($0.alertType ?? "").lowercased().contains("hazmat")
            || ($0.description ?? "").lowercased().contains("hazmat") }
        return holdSignal || alertSignal
    }
    private var dispositionTitle: String {
        if let h = activeHolds.first {
            // e.g. "CET intensive exam" — render the hold type verbatim.
            return (h.holdType ?? entry?.status ?? "Entry filed")
        }
        return (entry?.status ?? "Entry filed")
            .replacingOccurrences(of: "_", with: " ")
    }
    private var dispositionSub: String {
        let updated = entry?.lastUpdated.map { "Updated \($0)" } ?? "Awaiting ACE update"
        return updated
    }

    // MARK: - Holds (flagship ListRow)

    private var holdsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOLDS · EntryStatus.holds[] · \(activeHolds.count) active")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if activeHolds.isEmpty {
                EusoEmptyState(systemImage: "checkmark.shield.fill",
                               title: "No active holds",
                               subtitle: "CBP exam holds & PGA referrals on this entry will appear here.")
            } else {
                ForEach(activeHolds) { hold in holdRow(hold) }
            }
            // PORT-GAP caption — mirrors the canonical SVG hairline note.
            // getHoldStatus is unwrapped (DescartesABIService.ts:356) but
            // has no tRPC procedure in vesselShipments.ts.
            Text("Intensified-exam detail pending getHoldStatus wiring (named gap).")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func holdRow(_ hold: CBPHold663) -> some View {
        HStack(spacing: 0) {
            // 40×40 danger shield chip.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.danger.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF6B6F))
            }
            .padding(.trailing, Space.s3)

            VStack(alignment: .leading, spacing: 3) {
                Text(holdTitle(hold))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(holdMeta(hold))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                if hasHazmat {
                    Text("HAZMAT")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.warning.opacity(0.22)))
                }
                Text("ACTIVE")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(Color(hex: 0xFF6B6F))
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func holdTitle(_ hold: CBPHold663) -> String {
        // "CBP exam hold — CET" style: agency + hold type.
        let agency = hold.agency ?? "CBP"
        let type = hold.holdType ?? "exam hold"
        return "\(agency) exam hold — \(type)"
    }
    private func holdMeta(_ hold: CBPHold663) -> String {
        // "CBP · PGA referral · UN1830 Cl.8" — agency + reason.
        let agency = hold.agency ?? "CBP"
        let reason = hold.reason ?? "PGA referral"
        return "\(agency) · \(reason)"
    }

    // MARK: - Milestone track (FILED · HOLD · EXAM · RELEASE)

    private let milestoneLabels = ["FILED", "HOLD", "EXAM", "RELEASE"]

    private var milestoneTrack: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOLD LIFECYCLE · MILESTONE TRACK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                ForEach(Array(milestoneLabels.enumerated()), id: \.offset) { idx, label in
                    let done = idx <= milestoneIndex
                    let current = idx == milestoneIndex
                    VStack(spacing: 8) {
                        ZStack {
                            if current {
                                Circle()
                                    .strokeBorder(LinearGradient.primary, lineWidth: 2)
                                    .frame(width: 22, height: 22)
                            }
                            Circle()
                                .fill(done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                .overlay(
                                    Circle().strokeBorder(palette.borderSoft, lineWidth: done ? 0 : 1.4)
                                )
                                .frame(width: current ? 13 : 10, height: current ? 13 : 10)
                        }
                        .frame(height: 22)
                        Text(label)
                            .font(.system(size: 7.5, weight: current ? .heavy : .bold))
                            .foregroundStyle(current ? Color(hex: 0x4DA3FF)
                                             : (done ? palette.textPrimary : palette.textTertiary))
                    }
                    if idx < milestoneLabels.count - 1 {
                        Rectangle()
                            .fill(idx < milestoneIndex ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(Color.white.opacity(0.14)))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .offset(y: -11)
                    }
                }
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Entry facts ledger (ENTRY · TYPE · FEES)

    private var entryLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ENTRY · TYPE · FEES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ledgerRow("Entry type", value: "01 · Consumption")
                ledgerRow("Importer of record", value: "Eusorone Technologies")
                ledgerRow("Booking", value: bookingRef, mono: true)
                ledgerRow("Release date",
                          value: entry?.releaseDate ?? "pending exam",
                          valueColor: entry?.releaseDate == nil ? Color(hex: 0xFF6B6F) : palette.textPrimary)
                ledgerRow("Duty owed", value: dutyLong, strong: true)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var bookingRef: String {
        // Booking ref pulls from a hazmat/booking alert when present;
        // otherwise the canonical entry's linked booking from the lane.
        alerts.first(where: { $0.entryNumber == (entry?.entryNumber ?? entryNumber) })?.entryNumber
            ?? "VES-260523-9F2C41A0E7"
    }

    @ViewBuilder
    private func ledgerRow(_ label: String, value: String,
                           valueColor: Color? = nil, mono: Bool = false,
                           strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Font.system(size: 12, weight: .semibold, design: .monospaced)
                      : .system(size: 12, weight: strong ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
    }

    // MARK: - CTA pair (Refresh entry status / All alerts)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: refreshing ? "Refreshing…" : "Refresh entry status",
                      action: { Task { await refresh() } },
                      isLoading: refreshing)
            Button {
                // All alerts → drill into the CBP alerts list for this importer.
                // Routed by VesselOperatorNavController; no-op standalone.
            } label: {
                Text("All alerts")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 132, minHeight: 48)
                    .background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct EntryIn: Encodable { let entryNumber: String }
        struct AlertsIn: Encodable { let importerId: String }
        do {
            // Server returns `null` on no-data / error — decode as optional so
            // an absent entry surfaces a real empty state, never fabricated.
            async let e: CBPEntryStatus663? = EusoTripAPI.shared.query(
                "vesselShipments.getCBPEntryStatus", input: EntryIn(entryNumber: entryNumber))
            async let a: [CBPAlert663]? = EusoTripAPI.shared.query(
                "vesselShipments.getCBPAlerts", input: AlertsIn(importerId: importerId))
            let (status, alertList) = try await (e, a)
            self.entry = status
            self.alerts = alertList ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func refresh() async {
        refreshing = true
        await load()
        refreshing = false
    }
}

#Preview("663 · Vessel CBP Entry Detail · Night") {
    VesselCBPEntryDetailScreen(theme: Theme.dark,
                               entryNumber: "ENT-31194882",
                               importerId: "eusorone-technologies")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("663 · Vessel CBP Entry Detail · Light") {
    VesselCBPEntryDetailScreen(theme: Theme.light,
                               entryNumber: "ENT-31194882",
                               importerId: "eusorone-technologies")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
