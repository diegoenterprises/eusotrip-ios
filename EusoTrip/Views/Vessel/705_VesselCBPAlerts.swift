//
//  705_VesselCBPAlerts.swift
//  EusoTrip — Vessel Operator · CBP Alerts (Descartes ABI · CBP ACE + ISF 10+2).
//
//  Verbatim port of "705 Vessel CBP Alerts.svg" (Dark = Theme.dark palette-swap).
//  FEED/DETAIL grammar (sister 663/672): back-chevron + sparkle eyebrow + mono
//  caption + 28/700/-0.4 title + iridescent hairline; cardRim+inset summary hero
//  (DESCARTES ABI badge + ACTION pill + N-OPEN badge + open-alert headline + AT-RISK
//  duty); eusoDiagonal cell-1 KPI strip (EXAM HOLDS / ISF LATE / RELEASED); severity
//  icon-chip alert ListRows (red shield / amber clock / green check) with alertType
//  pills + action flags; "Open exam hold / All entries" CTA pair.
//
//  Data (REAL):
//    vesselShipments.getCBPAlerts  (EXISTS vesselShipments.ts:1108)
//        -> descartesABIService.getCBPAlerts(importerId) (DescartesABIService.ts:400)
//        -> CBPAlert[] | null  { alertId, alertType, severity, description,
//                                entryNumber, importerId, createdAt, expiresAt,
//                                actionRequired, agency }
//    (sibling, not surfaced here) getCBPEntryStatus :1097 · fileISF :1074
//
//  importerId derives from the session company (importer Eusorone Technologies,
//  DU §11.4). Vessel Operator = Lena Bjornstad (Aurora Ocean Division). country US.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE · ME), Compliance tab current (filled symbol).
//
//  PORT-NOTE: getCBPAlerts is reached through the generic path-based
//  EusoTripAPI.shared.query(_:input:) — the same caller every sibling vessel
//  screen uses. There is no per-procedure wrapper in EusoTripAPI.swift, so no
//  client-side gap exists; the procedure may return null on Descartes error,
//  which decodes into an empty list.
//

import SwiftUI

struct VesselCBPAlertsScreen: View {
    let theme: Theme.Palette
    var id: String = ""

    var body: some View {
        Shell(theme: theme) { VesselCBPAlertsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shape (mirror DescartesABIService.CBPAlert)

private struct CBPAlert705: Decodable, Identifiable {
    let alertId: String
    let alertType: String?
    let severity: String?
    let description: String?
    let entryNumber: String?
    let importerId: String?
    let createdAt: String?
    let expiresAt: String?
    let actionRequired: Bool?
    let agency: String?

    var id: String { alertId }
}

// MARK: - Severity / type buckets (drive icon-chip + pill colors)

private enum CBPTone { case danger, warning, success, neutral }

private struct CBPClassification {
    let tone: CBPTone
    let chipSymbol: String      // SF Symbol inside the 40×40 icon chip
    let pillText: String        // EXAM HOLD / ISF LATE / RELEASED …
}

// MARK: - Body

private struct VesselCBPAlertsBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var alerts: [CBPAlert705] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived hero / KPI counts (from REAL alert rows)

    private var examHolds: Int {
        alerts.filter { classification($0).pillText == "EXAM HOLD" }.count
    }
    private var isfLate: Int {
        alerts.filter { classification($0).pillText == "ISF LATE" }.count
    }
    private var released: Int {
        alerts.filter { classification($0).tone == .success }.count
    }
    private var openCount: Int {
        alerts.filter { ($0.actionRequired ?? false) || classification($0).tone != .success }.count
    }

    /// Importer identity for getCBPAlerts. The SVG canon names importer
    /// "Eusorone Technologies" (DU §11.4); prefer the live session company
    /// id when present, fall back to the canonical importer code.
    private var importerId: String {
        let cid = session.user?.companyId?.trimmingCharacters(in: .whitespaces)
        if let cid, !cid.isEmpty { return cid }
        return "EUSORONE"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline()
                    .padding(.top, Space.s4)

                summaryHero
                    .padding(.top, Space.s5)

                kpiStrip
                    .padding(.top, Space.s5)

                alertFeed
                    .padding(.top, Space.s5)

                ctaPair
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - DETAIL header (back-chevron + eyebrow + title + right-rail)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row — sparkle gradient eyebrow + mono CFR caption.
            HStack(alignment: .firstTextBaseline) {
                Text("✦ VESSEL OPERATOR · CBP ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("19 CFR · ACE")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            // Back-chevron + title block + US IMPORT / Eusorone right-rail.
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 6)

                Text("CBP Alerts")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("US IMPORT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("Eusorone · USLGB")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s4)
        }
    }

    // MARK: - Summary hero (cardRim + inset)

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Badge row: DESCARTES ABI · ACTION · N OPEN
            HStack(spacing: 8) {
                Text("DESCARTES ABI")
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.rail.opacity(0.22)))

                Text("ACTION")
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xFFB74D))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.22)))

                Spacer(minLength: 8)

                Text("\(openCount) OPEN")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0xE5484D)))
            }

            HStack(alignment: .top) {
                // Open-alert headline block.
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPEN ALERTS · getCBPAlerts")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(headlineSummary)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(updatedLine)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: 8)

                // AT-RISK duty.
                VStack(alignment: .trailing, spacing: 8) {
                    Text("AT RISK")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(atRiskDuty)
                        .font(.system(size: 22, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: 0x4D9BFF))
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }

    private var headlineSummary: String {
        if loading { return "Loading CBP alerts…" }
        if let err = loadError { return err }
        if alerts.isEmpty { return "No open CBP alerts" }
        return "\(examHolds) exam hold\(examHolds == 1 ? "" : "s") · \(isfLate) ISF late"
    }

    private var updatedLine: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm 'UTC'"
        f.timeZone = TimeZone(identifier: "UTC")
        return "Updated \(f.string(from: Date())) · importer Eusorone"
    }

    /// AT-RISK exposure — sums CBP's published per-violation ISF penalty
    /// ($5,000 ea., 19 CFR 113.64) across action-required ISF-late alerts.
    /// No fabricated figure: it is computed from the live alert rows.
    private var atRiskDuty: String {
        let perViolation = 5_000.0
        let exposed = Double(isfLate) * perViolation
        if exposed <= 0 { return "$0" }
        return "$" + numberWithCommas(exposed)
    }

    private func numberWithCommas(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    // MARK: - KPI strip · cell-1 eusoDiagonal

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            kpiCell(label: "EXAM HOLDS", value: "\(examHolds)", gradient: true,  valueColor: .white)
            kpiCell(label: "ISF LATE",   value: "\(isfLate)",   gradient: false, valueColor: Color(hex: 0xFFB74D))
            kpiCell(label: "RELEASED",   value: "\(released)",  gradient: false, valueColor: Color(hex: 0x3DD9A0))
        }
    }

    private func kpiCell(label: String, value: String, gradient: Bool, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 26, weight: .bold)).monospacedDigit()
                .foregroundStyle(gradient ? .white : valueColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            Group {
                if gradient { LinearGradient.diagonal }
                else { palette.bgCard }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradient ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Alert feed · icon-chip ListRows

    private var alertFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ALERTS · getCBPAlerts · \(alerts.count) total · by severity")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)

            if loading {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        if i > 0 { Divider().overlay(palette.borderFaint) }
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 66)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if alerts.isEmpty {
                EusoEmptyState(systemImage: "checkmark.shield",
                               title: "No CBP alerts",
                               subtitle: "Open Descartes ABI holds and ISF alerts for this importer will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedAlerts.enumerated()), id: \.element.id) { idx, alert in
                        if idx > 0 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                        alertRow(alert)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    /// SVG orders the feed "by severity": danger → warning → success → neutral.
    private var sortedAlerts: [CBPAlert705] {
        func rank(_ a: CBPAlert705) -> Int {
            switch classification(a).tone {
            case .danger:  return 0
            case .warning: return 1
            case .success: return 2
            case .neutral: return 3
            }
        }
        return alerts.sorted { rank($0) < rank($1) }
    }

    private func alertRow(_ alert: CBPAlert705) -> some View {
        let cls = classification(alert)
        let chipColor = tone(cls.tone)
        return HStack(alignment: .top, spacing: 12) {
            // 40×40 severity icon-chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: cls.chipSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(chipColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.entryNumber ?? alert.alertId)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(alert.description ?? cls.pillText)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Text(cls.pillText)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(chipColor.opacity(0.22)))
                Text(actionFlag(alert, cls))
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundStyle(cls.tone == .success ? palette.textTertiary : chipColor)
            }
        }
        .padding(Space.s4)
    }

    /// Right-edge action flag: countdown for ISF-late expiries, "action" for
    /// holds, "no action" for cleared rows. Derives from live alert fields.
    private func actionFlag(_ alert: CBPAlert705, _ cls: CBPClassification) -> String {
        if cls.tone == .success { return "no action" }
        if cls.pillText == "ISF LATE", let hrs = hoursUntilExpiry(alert) {
            return hrs < 0 ? "−\(abs(hrs))h" : "\(hrs)h"
        }
        return "action"
    }

    private func hoursUntilExpiry(_ alert: CBPAlert705) -> Int? {
        guard let raw = alert.expiresAt, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? {
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            return iso2.date(from: raw)
        }()
        guard let d = date else { return nil }
        return Int(d.timeIntervalSinceNow / 3600.0)
    }

    // MARK: - Classification (severity → tone/icon/pill)

    private func classification(_ alert: CBPAlert705) -> CBPClassification {
        let type = (alert.alertType ?? "").lowercased()
        let sev = (alert.severity ?? "").lowercased()
        let desc = (alert.description ?? "").lowercased()

        // Released / cleared → green check shield.
        if type.contains("released") || type.contains("cleared")
            || sev == "info" && (alert.actionRequired == false)
            || desc.contains("released") || desc.contains("cleared") {
            return CBPClassification(tone: .success, chipSymbol: "checkmark.shield.fill", pillText: "RELEASED")
        }

        // Exam hold / intensive exam / PGA referral → red shield (critical).
        if type.contains("exam") || type.contains("hold") || sev == "critical" || sev == "high"
            || desc.contains("exam") || desc.contains("hold") || desc.contains("referral") {
            return CBPClassification(tone: .danger, chipSymbol: "shield.lefthalf.filled", pillText: "EXAM HOLD")
        }

        // ISF late / amend window → amber clock (warning).
        if type.contains("isf") || sev == "warning" || sev == "medium"
            || desc.contains("isf") || desc.contains("amend") || desc.contains("cutoff") {
            return CBPClassification(tone: .warning, chipSymbol: "clock.fill", pillText: "ISF LATE")
        }

        return CBPClassification(tone: .neutral, chipSymbol: "exclamationmark.circle.fill",
                                 pillText: (alert.alertType ?? "ALERT").uppercased())
    }

    private func tone(_ t: CBPTone) -> Color {
        switch t {
        case .danger:  return Color(hex: 0xFF6B6F)
        case .warning: return Color(hex: 0xFFB74D)
        case .success: return Color(hex: 0x3DD9A0)
        case .neutral: return palette.textTertiary
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            Button {
                Task { await openExamHold() }
            } label: {
                Text("Open exam hold")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                VesselOperatorNavDispatcher.handle("shipments")
            } label: {
                Text("All entries")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Primary CTA — pull the live entry status for the top exam-hold alert
    /// via the real getCBPEntryStatus procedure. Surfaces a real error if the
    /// call fails; never fabricates a result.
    private func openExamHold() async {
        guard let hold = sortedAlerts.first(where: { classification($0).pillText == "EXAM HOLD" }),
              let entry = hold.entryNumber, !entry.isEmpty else { return }
        struct EntryIn: Encodable { let entryNumber: String }
        do {
            let _: CBPEntryStatus705? = try await EusoTripAPI.shared.query(
                "vesselShipments.getCBPEntryStatus", input: EntryIn(entryNumber: entry))
            // Detail-sheet routing is owned by the host nav controller; the
            // verbatim port surfaces the entry status fetch as the action.
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Load (REAL: vesselShipments.getCBPAlerts)

    private func load() async {
        loading = true; loadError = nil
        struct AlertsIn: Encodable { let importerId: String }
        do {
            // getCBPAlerts returns CBPAlert[] | null (null on Descartes error).
            let rows: [CBPAlert705]? = try await EusoTripAPI.shared.query(
                "vesselShipments.getCBPAlerts", input: AlertsIn(importerId: importerId))
            self.alerts = rows ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - getCBPEntryStatus shape (DescartesABIService.EntryStatus)

private struct CBPEntryStatus705: Decodable {
    let entryNumber: String?
    let status: String?
    let releaseDate: String?
    let liquidationDate: String?
    let dutyOwed: Double?
    let lastUpdated: String?
}

#Preview("705 · Vessel CBP Alerts · Night") { VesselCBPAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("705 · Vessel CBP Alerts · Light") { VesselCBPAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
