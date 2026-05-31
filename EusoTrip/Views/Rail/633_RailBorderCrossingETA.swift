//
//  633_RailBorderCrossingETA.swift
//  EusoTrip — Rail Engineer · Border Crossing ETA (carrier vantage).
//
//  Verbatim port of wireframe "633 Rail Border Crossing ETA · Dark".
//  Flagship DETAIL grammar (cf. 621 / 609 / shipper 205): back chevron +
//  eyebrow + mono caption + 28/-0.4 title, gradient-rimmed hero ActiveCard,
//  3-cell KPI strip (cell-1 eusoDiagonal), itemized factor ListRow stack,
//  recommendation context strip, Re-estimate / Interchange pts CTA pair.
//
//  CARRIER-SIDE · cross-border USMCA · KCSM/UP Laredo interchange.
//  Wired to REAL tRPC (grep-confirmed in railShipments router):
//    railShipments.getCrossBorderInterchangePoints  → [RailInterchangePoint]
//    railShipments.estimateRailBorderCrossingTime   → { estimatedHours, breakdown[] }
//

import SwiftUI

struct RailBorderCrossingETAScreen: View {
    let theme: Theme.Palette
    /// Cars in the consist crossing — defaulted to the wireframe consist
    /// size so the screen is constructible with only `theme`.
    var carCount: Int = 22
    var hasHazmat: Bool = false
    /// Railroad filter used to surface the carrier-relevant interchange
    /// (Laredo/Nuevo Laredo, KCSM/UP) from the single-country catalog.
    var railroad: String = "UP"

    var body: some View {
        Shell(theme: theme) {
            RailBorderCrossingETABody(carCount: carCount, hasHazmat: hasHazmat, railroad: railroad)
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

// MARK: - Data shapes (mirror crossBorderRail.ts service contracts)

private struct InterchangePoint633: Decodable, Identifiable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
    let interchangeType: String?
    let customsOffice: String?
    let hazmatAllowed: Bool?
    let notes: String?
}

private struct CrossingFactor633: Decodable, Identifiable {
    let step: String
    let hours: Double
    var id: String { step }
}

private struct CrossingEstimate633: Decodable {
    let estimatedHours: Double
    let breakdown: [CrossingFactor633]
}

// MARK: - Body

private struct RailBorderCrossingETABody: View {
    @Environment(\.palette) private var palette
    let carCount: Int
    let hasHazmat: Bool
    let railroad: String

    @State private var point: InterchangePoint633? = nil
    @State private var estimate: CrossingEstimate633? = nil
    @State private var hasPreClearance: Bool = false
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var reestimating = false
    @State private var syncedNote: String = "synced just now"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    placeholderHero
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    heroCard
                    kpiStrip
                    factorsCard
                    recommendationStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Derived (real-data only)

    /// ETA rendered like the wireframe hero "6h 40m".
    private func hm(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Compact "6h40m" used in the KPI cell.
    private func hmTight(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        let h = total / 60
        let m = total % 60
        if h > 0 && m > 0 { return "\(h)h\(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Signed delta string for a factor row, e.g. "+1h50m" / "4h 00m".
    private func factorDelta(_ hours: Double) -> String {
        hours >= 0 ? "+\(hm(hours))" : "-\(hm(abs(hours)))"
    }

    private var routeLabel: String {
        guard let p = point else { return "—" }
        let a = p.stateProvinceA ?? ""
        let name = p.name ?? p.id
        // "Laredo/Nuevo Laredo" → "N. Laredo to Laredo"
        let parts = name.split(separator: "/").map(String.init)
        if parts.count == 2 { return "\(parts[1]) to \(parts[0])" }
        return a.isEmpty ? name : "\(name) · \(a)"
    }

    private var interchangeMark: String {
        guard let p = point else { return "—" }
        let a = (p.railroadsA?.first) ?? ""
        let b = (p.railroadsB?.first) ?? ""
        if !a.isEmpty && !b.isEmpty { return "\(a) / \(b)" }
        return a.isEmpty ? b : a
    }

    // MARK: - Header (back chevron + eyebrow + mono caption + title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · BORDER ETA")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("USMCA")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            HStack(alignment: .top) {
                Text("Border crossing ETA")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(interchangeMark)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(syncedNote)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    Text("interchange")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    StatusPill(text: statusText, kind: statusKind)
                    Spacer()
                }
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(estimate.map { hm($0.estimatedHours) } ?? "—")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routeLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(carCount) cars · \(hasHazmat ? "hazmat" : "no hazmat")")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(carCount) CARS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(statusText.uppercased())
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(statusColor)
                    }
                }
                .padding(.top, Space.s4)
                // Progress: real fraction of crossing complete is not modelled
                // server-side — render an indeterminate half-bar so the hero
                // keeps the wireframe's progress affordance without fabricating
                // a completion percentage.  // PORT-GAP: crossing progress %
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * 0.5)
                    }
                }
                .frame(height: 6)
                .padding(.top, Space.s4)
            }
        }
    }

    private var statusText: String { "queued" }
    private var statusKind: StatusPill.Kind { hasPreClearance ? .success : .warning }
    private var statusColor: Color { hasPreClearance ? Brand.success : Brand.warning }

    // MARK: - KPI strip (3 cells · cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "ETA",
                    value: estimate.map { hmTight($0.estimatedHours) } ?? "—",
                    filled: true, valueColor: .white)
            kpiCell(label: "CARS",
                    value: "\(carCount)",
                    filled: false, valueColor: palette.textPrimary)
            kpiCell(label: "PRECLR",
                    value: preclearanceLabel,
                    filled: false, valueColor: preclearanceColor)
        }
    }

    /// Pre-clearance potential, derived from the server breakdown: the
    /// customs-inspection factor is what a filed pre-clearance collapses.
    private var preclearanceColor: Color {
        hasPreClearance ? palette.textTertiary : Brand.success
    }
    private var preclearanceLabel: String {
        guard let est = estimate else { return "—" }
        if hasPreClearance { return "filed" }
        let savable = est.breakdown
            .filter { $0.step.lowercased().contains("customs") }
            .reduce(into: 0.0) { acc, f in acc += f.hours }
        return savable > 0 ? hmTight(savable) : "—"
    }

    @ViewBuilder
    private func kpiCell(label: String, value: String, filled: Bool, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(filled ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(
            Group {
                if filled {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(filled ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Factors card (FACTORS · CROSSING TIME · itemized list rows)

    private var factorsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("FACTORS · CROSSING TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:912")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                let rows = estimate?.breakdown ?? []
                if rows.isEmpty {
                    EmptyFactorsRow()
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, f in
                        factorRow(f)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                contextStrip
            }
            .padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Classify a server breakdown step into icon-chip tint + short pill,
    /// mirroring the wireframe's BASE / SCALE / AVAIL grammar onto whatever
    /// real factors the estimator returns for this interchange.
    private func factorTone(_ step: String) -> (chip: Color, pill: String, deltaColor: Color, isCredit: Bool) {
        let s = step.lowercased()
        if s.contains("customs") || s.contains("crew") {
            return (Brand.rail, "BASE", Brand.rail, false)
        }
        if s.contains("dg") || s.contains("hazmat") {
            return (Brand.hazmat, "DG", Brand.hazmat, false)
        }
        if s.contains("inspection") || s.contains(">") || s.contains("cars") {
            return (Brand.warning, "SCALE", Brand.warning, false)
        }
        if s.contains("queue") || s.contains("high-volume") {
            return (Brand.warning, "QUEUE", Brand.warning, false)
        }
        if s.contains("tunnel") {
            return (Brand.info, "TUNNEL", Brand.info, false)
        }
        return (Brand.rail, "FACTOR", palette.textSecondary, false)
    }

    private func factorRow(_ f: CrossingFactor633) -> some View {
        let tone = factorTone(f.step)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.chip.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tone.chip)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.step)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(crossingDetail)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(tone.pill)
                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                .foregroundStyle(tone.deltaColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(tone.chip.opacity(0.24)))
            Text(factorDelta(f.hours))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone.deltaColor)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var crossingDetail: String {
        guard point != nil else { return "interchange hand-off" }
        return "\(interchangeMark) hand-off"
    }

    private var contextStrip: some View {
        let total = estimate?.estimatedHours ?? 0
        return Text("+ Hazmat \(hasHazmat ? "present" : "none") · \(hasHazmat ? "DG escort" : "no DG escort") · est \(hm(total)) \(hasPreClearance ? "with pre-clearance" : "without pre-clearance")")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recommendation context strip

    private var recommendationStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECOMMENDATION · VUCEM")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:887")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            // The estimator returns time factors only — the named VUCEM
            // pre-clearance savings line is not a server field; render the
            // savable customs-inspection time from the real breakdown and
            // flag the named recommendation text as a port gap.
            // PORT-GAP: railShipments.preClearanceRecommendation
            Text(recommendationText)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(provenanceLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var recommendationText: String {
        guard let est = estimate else { return "Pre-clearance window not yet estimated." }
        if hasPreClearance { return "Pre-clearance filed · customs inspection waived at interchange" }
        let savable = est.breakdown
            .filter { $0.step.lowercased().contains("customs") }
            .reduce(into: 0.0) { acc, f in acc += f.hours }
        guard savable > 0 else { return "No pre-clearance savings available at this interchange" }
        return "File VUCEM pre-clearance · saves \(hm(savable)) at \(routeShortName) interchange"
    }

    private var routeShortName: String {
        guard let p = point else { return "interchange" }
        let name = p.name ?? p.id
        return name.split(separator: "/").first.map(String.init) ?? name
    }

    private var provenanceLine: String {
        let mark = interchangeMark
        let office = point?.customsOffice ?? "—"
        return "\(mark) · \(office)"
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: reestimating ? "Re-estimating…" : "Re-estimate",
                      action: { Task { await reload(forcePreClear: true) } },
                      isLoading: reestimating)
            Button(action: {}) {
                Text("Interchange pts")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Placeholder / error

    private var placeholderHero: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 116)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .overlay(
                Text("Estimating crossing…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            )
    }

    private func errorCard(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.danger)
                Text("Crossing estimate unavailable")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            }
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Load (real tRPC · no mock data)

    private func reload(forcePreClear: Bool = false) async {
        if forcePreClear {
            reestimating = true
            hasPreClearance = true
        } else {
            loading = true
        }
        loadError = nil
        struct PointsIn: Encodable { let country: String; let railroad: String }
        struct EstimateIn: Encodable {
            let interchangePointId: String
            let hasPreClearance: Bool
            let carCount: Int
            let hasHazmat: Bool
        }
        do {
            // 1) Real interchange catalog (single-country: MX gateways for
            //    the USMCA southern border), filtered to the carrier railroad.
            let points: [InterchangePoint633] = try await EusoTripAPI.shared.query(
                "railShipments.getCrossBorderInterchangePoints",
                input: PointsIn(country: "MX", railroad: railroad))
            // Prefer the busiest US-MX gateway (Laredo/Nuevo Laredo) when the
            // catalog returns it; otherwise take the first matching point.
            let chosen = points.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("Laredo") })
                ?? points.first
            self.point = chosen

            guard let pid = chosen?.id else {
                self.estimate = nil
                loadError = "No interchange point available for \(railroad) on the southern border."
                if forcePreClear { reestimating = false } else { loading = false }
                return
            }

            // 2) Real crossing-time estimate from the server estimator.
            let est: CrossingEstimate633 = try await EusoTripAPI.shared.query(
                "railShipments.estimateRailBorderCrossingTime",
                input: EstimateIn(interchangePointId: pid,
                                  hasPreClearance: hasPreClearance,
                                  carCount: carCount,
                                  hasHazmat: hasHazmat))
            self.estimate = est
            self.syncedNote = forcePreClear ? "re-estimated just now" : "synced just now"
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        if forcePreClear { reestimating = false } else { loading = false }
    }
}

// MARK: - Empty factors row

private struct EmptyFactorsRow: View {
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No crossing factors")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Estimator returned no breakdown")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }
}

#Preview("633 · Rail Border Crossing ETA · Night") {
    RailBorderCrossingETAScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("633 · Rail Border Crossing ETA · Light") {
    RailBorderCrossingETAScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
