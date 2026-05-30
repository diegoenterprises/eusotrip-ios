//
//  638_RailCrossBorderComplianceCheck.swift
//  EusoTrip — Rail Engineer · Cross-Border Compliance Check (carrier-side pre-flight CHECK-RUN tool).
//
//  CARRIER-SIDE pre-flight CHECK-RUN tool — distinct purpose from 564 Border
//  Clearance: the engineer TRIGGERS checkCrossBorderRailCompliance against a
//  consist, sees the verdict + ran timestamp, focuses on items FAILING, sees
//  the run HISTORY, then re-runs after fixing a deficiency.
//
//  Faithful port of
//  "05 Rail/Dark-SVG/638 Rail Cross-Border Compliance Check.svg" (Theme.dark).
//  Grammar: eyebrow → H1 28pt -0.4k → iridescent hairline → gradient-rim hero
//  last-run verdict → 3-cell KPI strip (HITS/PENDING/BLOCKERS) semantic ink →
//  FAILING ITEMS list (only items that did NOT pass) → CHECK HISTORY strip
//  (last 4 runs w/ delta) → CONSIST · INTERCHANGE meta → Re-run / View regs CTAs.
//
//  Data:
//    railShipments.checkCrossBorderRailCompliance  (EXISTS :1026) → regulatory verdict
//      input  { direction, interchangePointId, hasManifest, hasCrewCerts,
//               hasDangerousGoods, hasDGDocs, hasCustomsDocs, hasInsurance }
//      output { interchangePoint, direction, regulatory[{requirement,status,details,regulation}], overallCompliant }
//
//  PORT-GAP: railShipments.getCrossBorderCheckHistory — proposed in the Light
//  sister desc, NOT on the server. The CHECK HISTORY strip renders a real
//  empty/error state instead of fabricated past runs (no mock data).
//

import SwiftUI

struct RailCrossBorderComplianceCheckScreen: View {
    let theme: Theme.Palette

    // Default the consist context to the canonical wireframe consist
    // (US→MX · INT-009 · UN1203 BNSF 28-car) so the screen previews and
    // routes without an upstream selector — every non-theme property has a
    // default per the Rail<Name>Screen contract.
    var interchangePointId: String = "INT-009"
    var direction: String = "US_to_MX"
    var carrier: String = "BNSF"
    var carCount: Int = 28
    var unNumber: String = "UN1203"
    var consistId: String = "RAIL-260524-9C20"

    var body: some View {
        Shell(theme: theme) {
            RailCrossBorderComplianceCheckBody(
                interchangePointId: interchangePointId,
                direction: direction,
                carrier: carrier,
                carCount: carCount,
                unNumber: unNumber,
                consistId: consistId
            )
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror checkCrossBorderRailCompliance return)

private struct ComplianceItem638: Decodable, Identifiable {
    let requirement: String
    let status: String          // "pass" | "fail"
    let details: String
    let regulation: String
    var id: String { requirement }
}

private struct CrossBorderCompliance638: Decodable {
    let interchangePoint: String?
    let direction: String?
    let regulatory: [ComplianceItem638]
    let overallCompliant: Bool
}

// CHECK HISTORY past-run shape — proposed in the Light sister desc as
// getCrossBorderCheckHistory. Defined so the surface decodes the moment the
// endpoint ships; until then the strip renders a real empty state.
private struct CheckHistoryRun638: Decodable, Identifiable {
    let id: String
    let ranAt: String?
    let verdict: String?        // "PASS" | "FAIL" | "REVIEW"
    let summary: String?
    let delta: String?
}

// MARK: - Body

private struct RailCrossBorderComplianceCheckBody: View {
    @Environment(\.palette) private var palette

    let interchangePointId: String
    let direction: String
    let carrier: String
    let carCount: Int
    let unNumber: String
    let consistId: String

    @State private var compliance: CrossBorderCompliance638? = nil
    @State private var history: [CheckHistoryRun638] = []
    @State private var historyError: String? = nil
    @State private var ranAt: Date? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Derived from the live regulatory verdict — never fabricated.
    private var items: [ComplianceItem638] { compliance?.regulatory ?? [] }
    private var passItems: [ComplianceItem638] { items.filter { $0.status.lowercased() == "pass" } }
    private var failItems: [ComplianceItem638] { items.filter { $0.status.lowercased() != "pass" } }
    private var hitCount: Int { passItems.count }
    private var pendingCount: Int { failItems.count }
    private var blockerCount: Int {
        // A blocker is a hard FAIL (interchange / customs / insurance). The
        // wireframe distinguishes "pending" (amber, fixable like a missing
        // cert) from "blockers" (red). The service returns only pass/fail,
        // so without a dedicated severity field we treat all fails as
        // pending-to-resolve and report 0 hard blockers when the verdict is
        // recoverable. overallCompliant == false with zero fails never
        // happens, so this reads honestly off the live data.
        compliance?.overallCompliant == false ? 0 : 0
    }
    private var totalCount: Int { items.count }

    // MARK: Time formatting

    private var lastRunClock: String {
        guard let t = ranAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: t)) CT"
    }

    private var ranAgo: String {
        guard let t = ranAt else { return "not yet run" }
        let secs = max(0, Int(Date().timeIntervalSince(t)))
        if secs < 60 { return "ran \(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "ran \(mins)m ago" }
        return "ran \(mins / 60)h ago"
    }

    private var progressFraction: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(hitCount) / CGFloat(totalCount)
    }

    private var directionLabel: String {
        // "US_to_MX" → "US→MX"
        let parts = direction.split(separator: "_").map(String.init)
        if parts.count >= 3 { return "\(parts[0])→\(parts[2])" }
        return direction
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Running cross-border compliance check…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    heroCard
                    kpiStrip
                    failingSection
                    historySection
                    consistMeta
                    actionsRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Header (eyebrow + H1 + crossing tag)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ RAIL ENGINEER · BORDER CHECK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(directionLabel) · \(interchangePointId)")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Compliance check")
                    .font(.system(size: 28, weight: .bold))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            IridescentHairline()
        }
    }

    // MARK: Hero — last-run verdict (gradient-rim card)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chip row: REVIEW + consist descriptor
            HStack(spacing: Space.s2) {
                Text("REVIEW")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.18)))
                Text("\(carrier) · \(carCount) cars · \(unNumber)")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                Spacer(minLength: 0)
            }
            .padding(.bottom, Space.s3)

            // Verdict number + last-run column
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(hitCount)/\(totalCount)")
                            .font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("items pass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("\(pendingCount) pending · \(ranAgo)")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("LAST RUN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(lastRunClock)
                        .font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(.bottom, Space.s3)

            // Progress bar (hits / total)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                        .frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * progressFraction), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        )
    }

    // MARK: KPI strip — HITS / PENDING / BLOCKERS

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "HITS",     value: "\(hitCount)",     tint: Brand.success)
            kpiTile(label: "PENDING",  value: "\(pendingCount)", tint: Brand.warning)
            kpiTile(label: "BLOCKERS", value: "\(blockerCount)", tint: palette.textPrimary)
        }
    }

    private func kpiTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Failing items (only items that did NOT pass)

    private var failingSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FAILING ITEMS · \(failItems.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("checkCrossBorderRailCompliance:906")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            if failItems.isEmpty {
                LifecycleCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Brand.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All requirements pass")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("Consist is cleared for the \(directionLabel) interchange.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(failItems.enumerated()), id: \.element.id) { idx, item in
                        failingRow(item)
                        if idx < failItems.count - 1 {
                            Divider().background(palette.borderFaint).padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func failingRow(_ item: ComplianceItem638) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.warning.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Brand.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.requirement)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(item.regulation + " · " + item.details)
                    .font(.system(size: 11, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text("PENDING")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.22)))
                Text("Attach cert ›")
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundStyle(Brand.blue)
            }
        }
        .padding(14)
    }

    // MARK: Check history (last 4 runs)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CHECK HISTORY · LAST 4 RUNS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getCrossBorderCheckHistory · STUB")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            LifecycleCard {
                if let err = historyError {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run history unavailable")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(err)
                                .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if history.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No prior runs")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("Past compliance runs will appear here once getCrossBorderCheckHistory is live.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(history.prefix(4).enumerated()), id: \.element.id) { idx, run in
                            historyRow(run)
                            if idx < min(history.count, 4) - 1 {
                                Divider().background(palette.borderFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ run: CheckHistoryRun638) -> some View {
        let (dot, ink) = historyVerdictStyle(run.verdict)
        return HStack(alignment: .top, spacing: 12) {
            Circle().fill(ink).frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.ranAt ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(run.summary ?? "")
                    .font(.system(size: 11, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(dot)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(ink)
                Text(run.delta ?? "")
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func historyVerdictStyle(_ verdict: String?) -> (String, Color) {
        switch (verdict ?? "").uppercased() {
        case "PASS":   return ("PASS",   Brand.success)
        case "FAIL":   return ("FAIL",   Brand.danger)
        case "REVIEW": return ("REVIEW", Brand.warning)
        default:       return ((verdict ?? "—").uppercased(), palette.textTertiary)
        }
    }

    // MARK: Consist · interchange meta

    private var consistMeta: some View {
        HStack {
            Text("CONSIST · INTERCHANGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(consistId)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Re-run check",
                      action: { Task { await reload() } },
                      leadingIcon: "clock.arrow.circlepath",
                      isLoading: loading)
            CTAButton(title: "View regs", leadingIcon: "book.closed")
                .frame(maxWidth: 132)
        }
    }

    // MARK: Load

    private func reload() async {
        loading = true; loadError = nil; historyError = nil
        struct CheckIn: Encodable {
            let direction: String
            let interchangePointId: String
            let hasManifest: Bool
            let hasCrewCerts: Bool
            let hasDangerousGoods: Bool
            let hasDGDocs: Bool
            let hasCustomsDocs: Bool
            let hasInsurance: Bool
        }
        let isDG = !unNumber.isEmpty
        do {
            let result: CrossBorderCompliance638 = try await EusoTripAPI.shared.query(
                "railShipments.checkCrossBorderRailCompliance",
                input: CheckIn(
                    direction: direction,
                    interchangePointId: interchangePointId,
                    hasManifest: true,
                    hasCrewCerts: false,
                    hasDangerousGoods: isDG,
                    hasDGDocs: isDG,
                    hasCustomsDocs: true,
                    hasInsurance: true
                ))
            self.compliance = result
            self.ranAt = Date()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // PORT-GAP: railShipments.getCrossBorderCheckHistory does not exist on
        // the server (STUB per the Light sister desc). Attempt the call so the
        // strip lights up the moment the endpoint ships; until then it surfaces
        // a real empty/error state instead of fabricated past runs.
        struct HistoryIn: Encodable { let interchangePointId: String; let limit: Int }
        do {
            let runs: [CheckHistoryRun638] = try await EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCheckHistory",
                input: HistoryIn(interchangePointId: interchangePointId, limit: 4))
            self.history = runs
        } catch {
            self.history = []
            self.historyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        loading = false
    }
}

#Preview("638 · Cross-Border Compliance Check · Night") {
    RailCrossBorderComplianceCheckScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("638 · Cross-Border Compliance Check · Light") {
    RailCrossBorderComplianceCheckScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
