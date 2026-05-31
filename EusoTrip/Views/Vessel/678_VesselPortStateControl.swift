//
//  678_VesselPortStateControl.swift
//  EusoTrip — Vessel Operator · Port State Control Inspection (Dark).
//
//  Verbatim port of canonical wireframe "678 Vessel Port State Control".
//  DETAIL header → cardRim exam-outcome hero (TARGETED · CIC · NO DETENTION
//  badges + deficiency-count figure + detain-risk + severity bar) → 3-cell
//  KPI strip (DEFICIENCIES · OPEN · DETENTION) → deficiency flagship ListRows
//  (40x40 severity chip + title + mono code sub + OPEN/OBSERVATION/VALID pill)
//  → ESang clearance advisory → File-rectification / All-certs CTA pair →
//  BottomNav (COMPLIANCE current).
//
//  Wiring (REAL):
//    · vesselShipments.getVesselCompliance  (vesselShipments.ts:854) — drives
//      the inspections list; the latest PSC inspection's `deficiencies` JSON
//      array ({ code, description, action }) populates the flagship ListRows,
//      the hero figure (count), open/detention KPIs, and the severity bar.
//    · vesselShipments.getUSCGPortEntry     (vesselShipments.ts:521) — USCG
//      33 CFR 160 port-entry status drives the DETAIN RISK readout +
//      TARGETED / NO-DETENTION badge resolution. Requires a vesselId.
//
//  See StructuredOutput.portGaps for the booking→vesselId resolution gap.
//

import SwiftUI

struct VesselPortStateControlScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselPortStateControlBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror vesselShipments.getVesselCompliance / getUSCGPortEntry)

/// One PSC deficiency line item — the `deficiencies` JSON column on
/// vessel_inspections: `{ code, description, action }[]`.
private struct PSCDeficiency: Decodable, Identifiable {
    let code: String?
    let description: String?
    let action: String?
    var id: String { (code ?? "") + (description ?? "") }
}

/// One inspection row from getVesselCompliance.inspections. The server
/// returns raw drizzle rows (vessel_inspections), so we decode the columns
/// we render: result, authority, inspectionType, inspectionDate,
/// detentionDays, and the deficiencies array.
private struct PSCInspection: Decodable, Identifiable {
    let id: Int
    let inspectionType: String?
    let authority: String?
    let result: String?
    let deficiencies: [PSCDeficiency]?
    let inspectionDate: String?
    let detentionDays: Int?
}

/// Envelope for vesselShipments.getVesselCompliance.
private struct VesselComplianceEnvelope: Decodable {
    let inspections: [PSCInspection]?
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

/// One check row from getUSCGPortEntry (33 CFR 160).
private struct USCGCheck: Decodable, Identifiable {
    let requirement: String?
    let regulation: String?
    let status: String?
    let details: String?
    var id: String { (requirement ?? "") + (regulation ?? "") }
}

/// Envelope for vesselShipments.getUSCGPortEntry.
private struct USCGPortEntryEnvelope: Decodable {
    let vesselId: Int?
    let vesselName: String?
    let overallStatus: String?
    let checks: [USCGCheck]?
    let denialReasons: [String]?
}

// MARK: - Body

private struct VesselPortStateControlBody: View {
    @Environment(\.palette) private var palette

    @State private var compliance: VesselComplianceEnvelope? = nil
    @State private var portEntry: USCGPortEntryEnvelope? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Canonical booking context (wireframe <desc>).
    private let bookingRef = "VES-260524-7B3D90F2C5"
    private let portLabel  = "USLGB Pier 400"

    // MARK: Derived

    /// Latest PSC inspection drives the hero + flagship rows. The compliance
    /// endpoint returns inspections ordered desc by inspectionDate, so the
    /// first PSC-type inspection is the most recent.
    private var latestPSC: PSCInspection? {
        let list = compliance?.inspections ?? []
        return list.first(where: { ($0.inspectionType ?? "").lowercased() == "psc" }) ?? list.first
    }

    private var deficiencies: [PSCDeficiency] { latestPSC?.deficiencies ?? [] }

    /// Open vs. observation vs. valid is read off each deficiency's `action`
    /// field — server records "open"/"observation"/"valid"/"monitor" style
    /// dispositions there. Anything without a closure marker reads OPEN.
    private func disposition(_ d: PSCDeficiency) -> PSCStatus {
        let a = (d.action ?? "").lowercased()
        if a.contains("valid") || a.contains("sighted") || a.contains("closed") || a.contains("rectified") { return .valid }
        if a.contains("observation") || a.contains("monitor") { return .observation }
        return .open
    }

    private var openCount:      Int { deficiencies.filter { disposition($0) == .open }.count }
    private var deficiencyCount: Int { latestPSC.map { $0.deficiencies?.count ?? 0 } ?? (compliance?.failedCount ?? 0) }
    private var detentionCount: Int { latestPSC?.detentionDays ?? 0 > 0 ? 1 : 0 }

    /// DETAIN RISK readout — derived from USCG port-entry overall status,
    /// falling back to the compliance result when USCG is unavailable.
    private var detainRisk: (label: String, color: Color) {
        if let s = portEntry?.overallStatus?.lowercased() {
            switch s {
            case "cleared":     return ("Low", Brand.success)
            case "conditional": return ("Elevated", Brand.warning)
            case "denied":      return ("High", Brand.danger)
            default: break
            }
        }
        // Fallback to PSC result severity.
        switch (latestPSC?.result ?? "").lowercased() {
        case "detention":   return ("High", Brand.danger)
        case "fail":        return ("Elevated", Brand.warning)
        case "conditional": return ("Elevated", Brand.warning)
        case "pass":        return ("Low", Brand.success)
        default:            return ("—", palette.textTertiary)
        }
    }

    private var noDetention: Bool { detentionCount == 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingHero
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        examHero
                        kpiStrip
                        deficiencySection
                        esangAdvisory
                        ctaPair
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - DETAIL header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("✦ VESSEL OPERATOR · PSC INSPECTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("33 CFR 160")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Port State Control")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(portLabel)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Loading hero

    private var loadingHero: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 116)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint))
    }

    // MARK: - Exam-outcome hero (cardRim + inset)

    private var examHero: some View {
        let risk = detainRisk
        return VStack(alignment: .leading, spacing: 0) {
            // Badge row: TARGETED · CIC · NO DETENTION
            HStack(spacing: Space.s2) {
                if isTargeted {
                    heroBadge("TARGETED", color: Brand.warning)
                }
                heroBadge("CIC · LIFE-SAVING", color: Brand.rail)
                heroBadge(noDetention ? "NO DETENTION" : "DETENTION", color: noDetention ? Brand.success : Brand.danger)
                Spacer(minLength: 0)
            }
            .padding(.bottom, Space.s4)

            // Figure + caption + detain risk
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(deficiencyCount)")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("deficiencies · \(openCount) open")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(examMeta)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("DETAIN RISK")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(risk.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(risk.color)
                }
            }
            .padding(.bottom, Space.s4)

            // Severity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(severityColor)
                        .frame(width: max(0, geo.size.width * severityFraction))
                }
            }
            .frame(height: 6)
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    /// TARGETED badge shows when USCG flags the entry conditional/denied or
    /// the PSC inspection carried a fail/detention result (the two server
    /// signals for an expanded "targeted" examination).
    private var isTargeted: Bool {
        if let s = portEntry?.overallStatus?.lowercased(), s == "conditional" || s == "denied" { return true }
        let r = (latestPSC?.result ?? "").lowercased()
        return r == "fail" || r == "detention" || r == "conditional"
    }

    private var examMeta: String {
        var parts: [String] = []
        if let d = latestPSC?.inspectionDate {
            parts.append("Exam \(shortDate(d))")
        }
        if let a = latestPSC?.authority, !a.isEmpty {
            parts.append(a)
        }
        return parts.isEmpty ? "Awaiting PSC exam record" : parts.joined(separator: " · ")
    }

    /// Severity bar fill — fraction of deficiencies still open, colored by
    /// detain risk.
    private var severityFraction: CGFloat {
        let total = max(deficiencyCount, 1)
        return CGFloat(openCount) / CGFloat(total)
    }
    private var severityColor: Color {
        if !noDetention { return Brand.danger }
        if openCount > 0 { return Brand.warning }
        return Brand.success
    }

    private func heroBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.22)))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "DEFICIENCIES", value: "\(deficiencyCount)", gradientNumeral: true)
            MetricTile(label: "OPEN",         value: "\(openCount)",       accent: openCount > 0 ? Brand.warning : nil)
            MetricTile(label: "DETENTION",    value: "\(detentionCount)",  accent: detentionCount > 0 ? Brand.danger : nil)
        }
    }

    // MARK: - Deficiency flagship ListRows

    private var deficiencySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DEFICIENCIES · getVesselCompliance")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if deficiencies.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.seal",
                    title: "No deficiencies on record",
                    subtitle: "PSC deficiency line items from the latest Port State Control exam will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(deficiencies.enumerated()), id: \.element.id) { idx, d in
                        deficiencyRow(d)
                        if idx < deficiencies.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, Space.s1)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func deficiencyRow(_ d: PSCDeficiency) -> some View {
        let status = disposition(d)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(status.color.opacity(0.22))
                    .frame(width: 40, height: 40)
                Image(systemName: status.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(status.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(d.description ?? "Deficiency")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(codeSub(d))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(status.label)
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    private func codeSub(_ d: PSCDeficiency) -> String {
        var parts: [String] = []
        if let c = d.code, !c.isEmpty { parts.append("code \(c)") }
        if let a = d.action, !a.isEmpty { parts.append(a) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - ESang advisory

    private var esangAdvisory: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(openCount > 0
                     ? "ESang: clear \(openCount) open item\(openCount == 1 ? "" : "s") to avoid detention"
                     : "ESang: no open PSC items — clearance unblocked")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("estimateVesselClearanceTime · ~4h added if unresolved")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "File rectification record") { /* opens rectification filing flow */ }
                .frame(maxWidth: .infinity)
            Button {
                /* opens statutory certificate ledger */
            } label: {
                Text("All certs")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .frame(width: 132)
            .background(palette.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func shortDate(_ iso: String) -> String {
        let inF = ISO8601DateFormatter()
        inF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = inF.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return String(iso.prefix(10)) }
        let out = DateFormatter(); out.dateFormat = "MM-dd"
        return out.string(from: date)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil

        // getVesselCompliance takes an OPTIONAL vesselId — without one the
        // server returns fleet-wide inspections (latest 20), mirroring the
        // 652 reference screen. We send an EMPTY input (not an explicit
        // null) because Zod's `.optional()` accepts `undefined`, not JSON
        // null. This screen is per-booking (VES-260524-7B3D90F2C5) but the
        // wireframe-canonical compliance endpoint resolves by vesselId, not
        // bookingNumber — see PORT-GAP.
        do {
            let comp: VesselComplianceEnvelope = try await EusoTripAPI.shared.queryNoInput(
                "vesselShipments.getVesselCompliance")
            self.compliance = comp

            // getUSCGPortEntry REQUIRES a numeric vesselId. We derive it from
            // the latest inspection row when present; otherwise the USCG
            // port-entry readout falls back to the PSC result (handled in
            // detainRisk / isTargeted) and we skip the call.
            // PORT-GAP: vesselShipments.getUSCGPortEntry needs a vesselId,
            // but getVesselCompliance does not surface the vessel FK on its
            // inspection rows in a stable field — and there is NO
            // booking→vesselId resolver endpoint on the server. USCG
            // 33 CFR 160 status is therefore derived from the PSC result
            // until a resolver ships. See StructuredOutput.portGaps.
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Deficiency disposition

private enum PSCStatus {
    case open, observation, valid

    var label: String {
        switch self {
        case .open:        return "OPEN"
        case .observation: return "OBSERVATION"
        case .valid:       return "VALID"
        }
    }
    var color: Color {
        switch self {
        case .open:        return Brand.warning
        case .observation: return Brand.info
        case .valid:       return Brand.success
        }
    }
    var icon: String {
        switch self {
        case .open:        return "doc.text"
        case .observation: return "drop"
        case .valid:       return "checkmark.shield"
        }
    }
}

#Preview("678 · Vessel Port State Control · Night") { VesselPortStateControlScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("678 · Vessel Port State Control · Light") { VesselPortStateControlScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
