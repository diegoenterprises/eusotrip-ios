//
//  672_VesselUSCGPortEntry.swift
//  EusoTrip — Vessel Operator · USCG Port Entry (33 CFR 160 · arrival gate).
//
//  Verbatim port of "672 Vessel USCG Port Entry.svg" (Dark + Light). Archetype =
//  COMPLIANCE / GATE. A tri-country country-segment drives which arrival regime is
//  live (US USCG active); the active-regime hero carries the 96-hour eNOA countdown
//  arc-clock + verdict; a statutory arrival-gate column; and a tri-country arrival-
//  authority band (US · CA · MX).
//
//  Web peer client/src/pages/vessel/VesselUSCGPortEntry.tsx (route UNVERIFIED).
//  tRPC (verified live 2026-07):
//    vesselShipments.getUSCGPortEntry (EXISTS :1015, {vesselId}) → services/
//      uscgPortEntry.validateUSCGPortEntry: { vesselId, vesselName, overallStatus
//      ('denied'|'conditional'|'cleared'), checks:[{requirement, regulation,
//      status('pass'|'fail'|'warning'|'unknown'), details}], denialReasons[] }.
//      The gate column + verdict bind to this real 33 CFR 160 payload.
//    vesselShipments.getUSCGCompliance (EXISTS :3462, {vesselId?}) — PSC/ISPS/P&I
//      cross-check.
//  HONEST GAP (surfaced to the-oath): validateUSCGPortEntry is READ-ONLY — there is
//    no vessel-scoped write for an eNOA/NVMC submission. "File / update eNOA" re-
//    validates the gate verdict and states the filing routes through NVMC (external);
//    it never fakes a submission. CA PAIR / MX arribo have no vessel-scoped proc.
//
//  RBAC vesselProcedure. transportMode = vessel · US arrival · 33 CFR 160 · USD
//  (CA MTSR/CBSA · CAD standby; MX SEMAR/SAT · MXN standby). NAV (VesselOperator):
//  HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private struct USCGCheck672: Decodable, Identifiable {
    let requirement: String?
    let regulation: String?
    let status: String?       // pass | fail | warning | unknown
    let details: String?
    var id: String { (requirement ?? "") + "|" + (regulation ?? "") }
}

private struct USCGPortEntry672: Decodable {
    let vesselId: Int?
    let vesselName: String?
    let overallStatus: String?   // denied | conditional | cleared
    let checks: [USCGCheck672]?
    let denialReasons: [String]?
}

struct VesselUSCGPortEntryScreen: View {
    var theme: Theme.Palette = Theme.dark
    var vesselId: Int = 118
    var imoNumber: String = "9456789"
    var lane: String = "CNSHA → USLGB Pier 400"
    var etaLabel: String = "Jun 9"
    /// Hours remaining to the 96-hour eNOA cutoff (client-side arc-clock).
    var hoursToCutoff: Int = 34

    var body: some View {
        Shell(theme: theme) {
            VesselUSCGPortEntryBody(vesselId: vesselId, imoNumber: imoNumber,
                                    lane: lane, etaLabel: etaLabel, hoursToCutoff: hoursToCutoff)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselUSCGPortEntryBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let vesselId: Int
    let imoNumber: String
    let lane: String
    let etaLabel: String
    let hoursToCutoff: Int

    @State private var entry: USCGPortEntry672? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil
    @State private var revalidating = false

    private var checks: [USCGCheck672] { entry?.checks ?? [] }
    private var verdict: String {
        switch (entry?.overallStatus ?? "").lowercased() {
        case "cleared":     return "Cleared for entry"
        case "denied":      return "Entry denied"
        case "conditional": return "Conditional entry"
        default:            return checks.isEmpty ? "Awaiting gate check" : "Conditional entry"
        }
    }
    private var targetedCount: Int {
        checks.filter { ($0.status ?? "").lowercased() == "warning" || ($0.status ?? "").lowercased() == "fail" }.count
    }
    private var verdictColor: Color {
        switch (entry?.overallStatus ?? "").lowercased() {
        case "cleared": return Brand.success
        case "denied":  return Brand.danger
        default:        return Brand.warning
        }
    }
    /// 96-hour window → fraction consumed for the arc.
    private var arcFraction: CGFloat {
        CGFloat(max(0, min(96, 96 - hoursToCutoff))) / 96
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if let actionNote { noteBanner(actionNote) }

                countrySegment
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    verdictHero
                    gateColumn
                }
                triCountryBand
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · PORT ENTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USCG · 33 CFR 160")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Brand.vessel)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Text("Compliance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("USCG port entry")
                .font(.system(size: 26, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("IMO \(imoNumber) · \(lane) · ETA \(etaLabel)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Country segment (US active)

    private var countrySegment: some View {
        HStack(spacing: Space.s3) {
            segChip(title: "US · USCG", sub: "eNOA 96-HR", active: true)
            segChip(title: "CA · TC MARINE", sub: "PAIR 96-HR", active: false)
            segChip(title: "MX · SEMAR", sub: "ARRIBO · DESPACHO", active: false)
        }
    }

    private func segChip(title: String, sub: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? .white : palette.textSecondary)
            Text(sub)
                .font(.system(size: 8, weight: .bold)).tracking(0.2)
                .foregroundStyle(active ? Color.white.opacity(0.85) : palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
    }

    // MARK: - Verdict hero (arc-clock + verdict)

    private var verdictHero: some View {
        HStack(spacing: Space.s5) {
            arcClock
            VStack(alignment: .leading, spacing: 6) {
                Text("NVMC eNOA · NOA-318824")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text(verdict)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("\(targetedCount) of \(max(checks.count, 1)) gates targeted")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if targetedCount > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(Brand.warning)
                            .frame(width: 6, height: 6)
                            .opacity(reduceMotion ? 1 : pscPulse)
                        Text("PSC TARGETED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(Brand.warning)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pscPulse = 0.35
                }
            }
        }
    }

    @State private var pscPulse: Double = 1

    private var arcClock: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 7)
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(verdictColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(hoursToCutoff)h")
                    .font(.system(size: 19, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("TO CUTOFF")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 84, height: 84)
    }

    // MARK: - Arrival gate column (real checks)

    private var gateColumn: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ARRIVAL GATES · getUSCGPortEntry · 33 CFR 160")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if checks.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.shield",
                                   title: "No gate checks yet",
                                   subtitle: "USCG arrival gates for this vessel will appear here.")
                        .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { idx, c in
                        if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                        gateRow(c)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func gateRow(_ c: USCGCheck672) -> some View {
        let st = (c.status ?? "unknown").lowercased()
        let (tint, icon, badge): (Color, String, String) = {
            switch st {
            case "pass":    return (Brand.success, "checkmark.shield.fill", "ACCEPTED")
            case "fail":    return (Brand.danger, "exclamationmark.shield.fill", "BLOCKED")
            case "warning": return (Brand.warning, "exclamationmark.triangle.fill", "TARGETED")
            default:        return (Brand.info, "shield.lefthalf.filled", "PENDING")
            }
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.requirement ?? "Requirement")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(c.details ?? (c.regulation ?? ""))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(badge)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(tint)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.16)))
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Tri-country arrival-authority band

    private var triCountryBand: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TRI-COUNTRY PORT ENTRY · ARRIVAL AUTHORITY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                authorityRow(cc: "US", title: "USCG · NVMC eNOA",
                             sub: "−96h pre-arrival · 33 CFR 160 · USD",
                             right: "$25k+/day", state: "● ACTIVE", active: true)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                authorityRow(cc: "CA", title: "TC Marine · 96-hr PAIR",
                             sub: "MTSR + CBSA ACI · pre-arrival · CAD",
                             right: "C$ penalty", state: "STANDBY", active: false)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                authorityRow(cc: "MX", title: "SEMAR · Arribo / Despacho",
                             sub: "Ley Nav. · Capitanía · agente naval · MXN",
                             right: "agente naval", state: "STANDBY", active: false)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func authorityRow(cc: String, title: String, sub: String,
                              right: String, state: String, active: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Text(cc)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(active ? .white : palette.textSecondary)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(active ? AnyShapeStyle(LinearGradient.primary)
                                 : AnyShapeStyle(Color.white.opacity(0.06))))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(right)
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(active ? Color(hex: 0xFF6B5E) : palette.textSecondary)
                Text(state)
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(active ? Brand.blue : palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
        .background(active ? AnyShapeStyle(LinearGradient(colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)],
                                                          startPoint: .leading, endPoint: .trailing))
                           : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await fileOrUpdateENOA() }
            } label: {
                Text(revalidating ? "Re-validating…" : "File / update eNOA")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(revalidating ? 0.6 : 1)
            .disabled(revalidating)

            Button {
                actionNote = "Switching discharge port re-runs the arrival-gate check."
            } label: {
                Text("Switch port")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 112)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 220)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let vesselId: Int }
        do {
            let e: USCGPortEntry672? = try await EusoTripAPI.shared.query(
                "vesselShipments.getUSCGPortEntry", input: In(vesselId: vesselId))
            self.entry = e
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// getUSCGPortEntry is read-only — there is no eNOA/NVMC write proc. This
    /// re-validates the gate verdict (a real action) and states, honestly, that
    /// the filing itself routes through NVMC. No fabricated submission.
    private func fileOrUpdateENOA() async {
        revalidating = true
        await load()
        revalidating = false
        actionNote = "Gate verdict re-validated. eNOA is filed via NVMC — submission endpoint pending (surfaced to the-oath)."
    }
}

#Preview("672 · Vessel USCG Port Entry · Night") {
    VesselUSCGPortEntryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("672 · Vessel USCG Port Entry · Light") {
    VesselUSCGPortEntryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
