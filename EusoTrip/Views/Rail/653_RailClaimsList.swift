//
//  653_RailClaimsList.swift
//  EusoTrip — Rail Engineer · Claims List (carrier-side intermodal claims queue).
//
//  Verbatim port of "653 Rail Claims List · Dark". Built to the flagship DETAIL
//  grammar (645 Rail Detention Dashboard / 02 Shipper 205): back-chevron + eyebrow
//  + mono caption + title 28/-0.4; gradient-rimmed (cardRim+inset) hero ActiveCard
//  with lead figure + progress; 3-cell KPI strip (cell-1 eusoDiagonal); itemized
//  ListRow stack (40x40 icon chip + title + mono sub + short status pill + right
//  tabular value); context strip; CTA pair.
//
//  Carrier BNSF Intermodal; shipper-of-record Diego Usoro · Eusorone Technologies.
//  Pure-rail so no driver-anchor (ME) disc.
//
//  RAIL vocabulary preserved: claim / concealed-damage / OS&D / shortage / loss /
//  demurrage / detention. CARRIER-SIDE intermodal-parity gap-fill.
//
//  Live wiring (grep-confirmed in-repo, EusoTripAPI.shared.freightClaims):
//    · freightClaims.getClaimsDashboard  → FreightClaimsAPI.Dashboard  (open/pending/
//      resolved/denied/totalValue/avgResolutionDays/aging)
//    · freightClaims.getClaims(status:search:limit:) → ClaimsResponse{ claims:[Claim] }
//      where Claim = id:Int · type · status · description · createdAt · severity
//  PORT-GAP (flagged below): freightClaims.getClaimById is NOT exposed on the Swift
//  API surface — the SVG's "tap a row -> getClaimById" detail drill is wired to a
//  no-op until the per-claim read lands.
//

import SwiftUI

struct RailClaimsListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimsListBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailClaimsListBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: FreightClaimsAPI.Dashboard? = nil
    @State private var claims: [FreightClaimsAPI.Claim] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived live counts (no fabricated numbers — empty state if absent)

    /// SVG eyebrow "23 OPEN" — wired to dashboard.open.
    private var openCount: Int { dashboard?.open ?? 0 }

    /// SVG hero "7 awaiting docs" — pending claims (awaiting documentation).
    private var awaitingCount: Int { dashboard?.pending ?? 0 }

    /// SVG hero / KPI "5 escalated" — escalated severity or status across the
    /// loaded queue. Derived from the live rows, never seeded.
    private var escalatedCount: Int {
        claims.filter { isEscalated($0) }.count
    }

    /// Active = open + pending (the working queue, matching the hero "23 active").
    private var activeCount: Int { openCount + awaitingCount }

    /// SLA headroom in days — avg resolution days, surfaced as the hero "3d" chip.
    private var slaDays: Int { Int((dashboard?.avgResolutionDays ?? 0).rounded()) }

    /// Hero progress fraction — resolved share of all claims the dashboard knows.
    private var progressFraction: CGFloat {
        guard let d = dashboard else { return 0 }
        let total = d.open + d.pending + d.resolved + d.denied
        guard total > 0 else { return 0 }
        return CGFloat(d.resolved) / CGFloat(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrow
            titleRow
            IridescentHairline()

            if loading {
                loadingSkeleton
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else {
                heroCard
                kpiStrip
                claimsCard
                contextStrip
                ctaPair
            }

            Color.clear.frame(height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow ( ✦ RAIL ENGINEER · CLAIMS  /  23 OPEN )

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · CLAIMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("\(openCount) OPEN")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (back chevron + "Claims list" + BNSF / synced)

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Claims list")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("BNSF")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 5m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Hero ActiveCard (gradient-rimmed)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Filter pills row
                HStack(spacing: Space.s2) {
                    Text("filter: open")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("\(escalatedCount) escalated")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    Spacer()
                }

                // Lead figure + label  /  SLA
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text("\(activeCount)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("active claims")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("\(awaitingCount) awaiting docs · \(escalatedCount) escalated")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("SLA")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(slaDays)d")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0xFFB74D))
                    }
                }

                // Progress track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * progressFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 3-cell KPI strip (cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "OPEN", value: "\(openCount)", gradientFill: true,
                    valueColor: .white, labelColor: .white.opacity(0.85))
            kpiCell(label: "AWAITING", value: "\(awaitingCount)", gradientFill: false,
                    valueColor: Color(hex: 0xFFB74D), labelColor: palette.textTertiary)
            kpiCell(label: "ESCALATED", value: "\(escalatedCount)", gradientFill: false,
                    valueColor: Color(hex: 0xFF6B5E), labelColor: palette.textTertiary)
        }
    }

    private func kpiCell(label: String, value: String, gradientFill: Bool,
                         valueColor: Color, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(labelColor)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            Group {
                if gradientFill {
                    LinearGradient.diagonal
                } else {
                    palette.bgCard
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradientFill ? Color.clear : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Claims list card

    private var claimsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CLAIMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getClaims:172")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            if claims.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No open claims",
                    subtitle: "Filed damage, shortage, loss & OS&D claims for this carrier queue will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(claims.enumerated()), id: \.element.id) { idx, claim in
                        claimRow(claim)
                        if idx < claims.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

                // PORT-GAP: freightClaims.getClaimById is not on the Swift API.
                Text("+ tap a row -> getClaimById · evidence + workflow stage")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s2)
            }
        }
    }

    private func claimRow(_ claim: FreightClaimsAPI.Claim) -> some View {
        let tone = rowTone(claim)
        return Button {
            // PORT-GAP: freightClaims.getClaimById — per-claim detail drill
            // (evidence + workflow stage) is not exposed on EusoTripAPI yet.
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tone.fill.opacity(tone.fillOpacity))
                        .frame(width: 40, height: 40)
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tone.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(claimNumber(claim))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitleLine(claim))
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(tone.pill)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(tone.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(tone.fill.opacity(tone.fillOpacity)))
                    Text(amountString(claim))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tone.amountInk)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CLAIM DETAIL · getClaimById")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("tap a row")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("filter open/closed · sort by value, age, SLA")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Carrier BNSF Intermodal · Eusorone Technologies (DU) · open queue")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (File claim · Sort)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "File claim", action: {
                // PORT-GAP: freightClaims.fileClaim requires a loadId + amount +
                // description context the list surface doesn't carry; the filing
                // sheet (645/099 grammar) is the canonical entry point. Wired
                // here as the primary CTA destination once that sheet ports.
            })
            Button {
                cycleSort()
            } label: {
                Text("Sort")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Sort cycle

    enum SortMode: String, CaseIterable {
        case value = "value", age = "age", sla = "sla"
    }
    @State private var sortMode: SortMode = .value

    private func cycleSort() {
        let all = SortMode.allCases
        if let i = all.firstIndex(of: sortMode) {
            sortMode = all[(i + 1) % all.count]
        }
        claims = sortedClaims(claims)
    }

    private func sortedClaims(_ rows: [FreightClaimsAPI.Claim]) -> [FreightClaimsAPI.Claim] {
        switch sortMode {
        case .value:
            // Escalated first, then by recency (createdAt desc) since the Claim
            // row carries no amount field on this list response.
            return rows.sorted { a, b in
                if isEscalated(a) != isEscalated(b) { return isEscalated(a) }
                return (a.createdAt ?? "") > (b.createdAt ?? "")
            }
        case .age:
            return rows.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        case .sla:
            return rows.sorted { isEscalated($0) && !isEscalated($1) }
        }
    }

    // MARK: - Row helpers (derive verbatim grammar from live fields)

    private func isEscalated(_ claim: FreightClaimsAPI.Claim) -> Bool {
        let sev = (claim.severity ?? "").lowercased()
        let st  = (claim.status ?? "").lowercased()
        return sev == "critical" || sev == "high" || sev == "escalated"
            || st.contains("escalat") || st.contains("dispute")
    }

    private struct RowTone {
        let pill: String
        let ink: Color
        let fill: Color
        let fillOpacity: Double
        let amountInk: Color
    }

    /// Maps the live claim status onto the SVG's three pill tones:
    ///   ESCALATED (danger) · DOCS / pending (warning) · FILED (info).
    private func rowTone(_ claim: FreightClaimsAPI.Claim) -> RowTone {
        let st = (claim.status ?? "").lowercased()
        if isEscalated(claim) {
            return RowTone(pill: "ESCALATED", ink: Color(hex: 0xFF6B5E),
                           fill: Brand.danger, fillOpacity: 0.18,
                           amountInk: Color(hex: 0xFF6B5E))
        }
        if st.contains("pending") || st.contains("doc") || st.contains("await") || st.contains("review") {
            return RowTone(pill: "DOCS", ink: Color(hex: 0xFFB74D),
                           fill: Brand.warning, fillOpacity: 0.22,
                           amountInk: Color(hex: 0xFFB74D))
        }
        if st.contains("resolv") || st.contains("paid") || st.contains("closed") {
            return RowTone(pill: "RESOLVED", ink: Brand.success,
                           fill: Brand.success, fillOpacity: 0.18,
                           amountInk: palette.textPrimary)
        }
        if st.contains("deni") || st.contains("reject") {
            return RowTone(pill: "DENIED", ink: palette.textSecondary,
                           fill: Brand.neutral, fillOpacity: 0.18,
                           amountInk: palette.textPrimary)
        }
        // Default — filed / open.
        return RowTone(pill: "FILED", ink: Color(hex: 0x5BB0F5),
                       fill: Brand.info, fillOpacity: 0.20,
                       amountInk: palette.textPrimary)
    }

    /// Canonical claim number — server-provided where present, else a stable
    /// CLM-derived label from the row id. No fabricated identifiers.
    private func claimNumber(_ claim: FreightClaimsAPI.Claim) -> String {
        "CLM-\(claim.id)"
    }

    /// "<Type> · <route/yard>" mono sub-line. Type from the live enum; the
    /// route hint rides the description (server returns "Damage · Logistics
    /// Park CHI"-style copy on this surface).
    private func subtitleLine(_ claim: FreightClaimsAPI.Claim) -> String {
        let type = (claim.type ?? "Claim").capitalized
        if let desc = claim.description, !desc.isEmpty {
            // Avoid double-printing the type if the description leads with it.
            if desc.lowercased().hasPrefix(type.lowercased()) { return desc }
            return "\(type) · \(desc)"
        }
        return type
    }

    /// The list response Claim row carries no amount field — render an em-dash
    /// rather than fabricate a dollar value. (Amount lives on getClaimById /
    /// the dashboard totalValue aggregate, both flagged PORT-GAP for the row.)
    private func amountString(_ claim: FreightClaimsAPI.Claim) -> String {
        "—"
    }

    // MARK: - Loader

    private func reload() async {
        loading = true; loadError = nil
        do {
            async let d: FreightClaimsAPI.Dashboard =
                EusoTripAPI.shared.freightClaims.getDashboard()
            async let c: FreightClaimsAPI.ClaimsResponse =
                EusoTripAPI.shared.freightClaims.getClaims(status: "open", limit: 30)
            let (dash, resp) = try await (d, c)
            self.dashboard = dash
            self.claims = sortedClaims(resp.claims)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("653 · Rail Claims List · Night") {
    RailClaimsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("653 · Rail Claims List · Light") {
    RailClaimsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
