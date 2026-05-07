//
//  224_ShipperPartnerDirectory.swift
//  EusoTrip 2027 UI — Shipper · Partner Directory (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/224_ShipperPartnerDirectory.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. The
//  Eusotrans LLC USDOT 3 194 882 owner-op seam pins to row 1 when
//  present (§8). Partner-index formula is the §9.1 / §43.2 canon:
//
//    index = onTime · 0.4 + completion · 0.3 + log₁₀(loads+1)/log₁₀(50) · 0.2 + spend · 0.1
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · PARTNER DIRECTORY / "{N} PARTNERS · {M} FAVORITED"
//    2. Title block      Partner directory / "Eusorone Technologies · trusted carrier network"
//    3. IridescentHairline
//    4. KPI summary card 3-cell · AVG INDEX (gradient) · LOADS YTD · EXPIRING (warn glyph)
//    5. Filter chip row  All / Favorites + star / Tanker / Reefer / Cryo
//    6. Partner list     status-aware 3pt tier rim · 44pt monogram avatar w/ §11.4 tone palette
//                        · name + favorite star · mono credentials · 3-stat row
//                        (LOADS · ON-TIME · AGR) · 56pt P1/P2 index badge w/ composite
//    7. Tap-hint footer  inside the list card · gradient mid-link
//    8. Formula footer   PARTNERSHIP INDEX · §9.1 formula verbatim
//
//  Real wiring preserved: `supplyChain.getMyPartners(status:toRole:)`
//  via `ShipperPartnerDirectoryStore`. Search + status filter
//  preserved as supplemental utility.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2136 — Partner envelope doesn't ship `loads`, `onTime`,
//                `completion`, `composite`, or `equipmentTypes`.
//                Per-row LOADS / ON-TIME stats and index badge paint
//                "—" placeholders. Equipment chip filter (Tanker /
//                Reefer / Cryo) paints "—" pending classification.
//                Suggested wire shape: extend Partner with `loads90d:
//                int, onTimeRate: int, completionRate: int, composite:
//                double, equipmentTypes: string[]`.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3 numbers-
//  first copy; §4.3 single iridescent hairline; §8 owner-op seam
//  (Eusotrans LLC pinned to row 1 when present); §9.1 / §43.2
//  partnership-index formula; §11 / §11.2 / §11.4 Diego canon; §13
//  carrier mix (MC-306 / MC-331 / DOT- / 53' Reefer); §15.2 status-
//  aware tier-rim grammar; §16 KPI summary card; §19.2 file-scoped
//  PartnerStar + helpers; §20.4 no dead buttons; §22.2 textTertiary
//  informational counter.
//

import SwiftUI

// MARK: - Filter (wireframe canon)

private enum PartnerFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case tanker
    case reefer
    case cryo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:        return "All"
        case .favorites:  return "Favorites"
        case .tanker:     return "Tanker"
        case .reefer:     return "Reefer"
        case .cryo:       return "Cryo"
        }
    }

    var withStar: Bool { self == .favorites }
}

// MARK: - Status helpers

private struct PartnerStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> PartnerStatusStyle {
        switch (raw ?? "").lowercased() {
        case "active":      return .init(label: "Active",     color: Brand.success)
        case "pending":     return .init(label: "Pending",    color: Brand.warning)
        case "declined":    return .init(label: "Declined",   color: Brand.danger)
        case "suspended":   return .init(label: "Suspended",  color: Brand.danger)
        case "terminated":  return .init(label: "Terminated", color: Brand.danger)
        default:            return .init(label: (raw ?? "Unknown").capitalized, color: Brand.neutral)
        }
    }
}

private enum AgrStatus {
    case active
    case awaiting
    case expiring
    case none
}

private enum AvatarTone { case gradient, hazmat, info, escort, rail }

private enum PartnerDirectoryBadgeTier { case gradientHero, gradientHollow, goldHero, goldHollow }

// MARK: - Store (preserved)

@MainActor
final class ShipperPartnerDirectoryStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([SupplyChainAPI.Partner])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var unfiltered: [SupplyChainAPI.Partner] = []
    @Published var search: String = ""
    @Published fileprivate var filter: PartnerFilter = .all {
        didSet {
            if oldValue != filter { Task { await load() } }
        }
    }

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let rows = try await api.supplyChain.getMyPartners(status: nil)
            unfiltered = rows
            phase = .loaded(applyFilter(rows: rows))
        } catch {
            phase = .error("Couldn't reach partner directory.")
        }
    }

    private func applyFilter(rows: [SupplyChainAPI.Partner]) -> [SupplyChainAPI.Partner] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let searched: [SupplyChainAPI.Partner]
        if q.isEmpty {
            searched = rows
        } else {
            searched = rows.filter { p in
                (p.companyName ?? "").lowercased().contains(q)
                || (p.companyDot ?? "").lowercased().contains(q)
                || (p.companyMc ?? "").lowercased().contains(q)
                || (p.companyState ?? "").lowercased().contains(q)
            }
        }
        return applyClientFilter(rows: searched, filter: filter)
    }

    fileprivate func applyClientFilter(rows: [SupplyChainAPI.Partner],
                                       filter: PartnerFilter) -> [SupplyChainAPI.Partner] {
        switch filter {
        case .all:
            return pinnedHouseFirst(rows)
        case .favorites:
            // Heuristic: any partner with an active agreement counts as favorited.
            // EUSO-2136 — no explicit isFavorite flag.
            return pinnedHouseFirst(rows.filter {
                ($0.agreementStatus ?? "").lowercased() == "active"
            })
        case .tanker, .reefer, .cryo:
            // EUSO-2136 — equipment classification not on envelope.
            return []
        }
    }

    /// §8 owner-op seam — pin Eusotrans LLC to row 1 when present.
    private func pinnedHouseFirst(_ rows: [SupplyChainAPI.Partner]) -> [SupplyChainAPI.Partner] {
        var out = rows
        out.sort { lhs, rhs in
            let lHouse = (lhs.companyName ?? "").lowercased().contains("eusotrans")
            let rHouse = (rhs.companyName ?? "").lowercased().contains("eusotrans")
            if lHouse != rHouse { return lHouse }
            return false
        }
        return out
    }
}

// MARK: - Screen root

struct ShipperPartnerDirectory: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ShipperPartnerDirectoryStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        // RealtimeService → partner directory refreshes when carrier
        // performance metrics shift, new partners onboard, or roster
        // updates land.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · PARTNER DIRECTORY")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s3)
    }

    private var counterEyebrow: String {
        let total = store.unfiltered.count
        let favorited = store.unfiltered.filter {
            ($0.agreementStatus ?? "").lowercased() == "active"
        }.count
        return "\(total) PARTNERS · \(favorited) FAVORITED"
    }

    private var counterAccessibility: String {
        "\(store.unfiltered.count) partners in the directory"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Partner directory")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · trusted carrier network")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s3)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s3)
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryCard
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                searchBar
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                filterChipRow
                    .padding(.top, Space.s3)

                if rows.isEmpty {
                    emptyOrNoMatchCard
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                } else {
                    partnerListCard(rows)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s4)
                }

                formulaFooter
            }
        }
    }

    // MARK: KPI summary card (3-cell · AVG INDEX / LOADS YTD / EXPIRING)

    private var kpiSummaryCard: some View {
        let expiring = store.unfiltered.filter {
            let s = ($0.agreementStatus ?? "").lowercased()
            return s == "expired" || s == "pending_signature"
        }.count

        return HStack(spacing: 0) {
            // EUSO-2136 — index aggregate not on envelope.
            kpiCell(label: "AVG INDEX",
                    value: "—",
                    valueStyle: .gradient,
                    trail: "pending",
                    trailColor: palette.textSecondary,
                    showWarn: false)
            kpiDivider
            // EUSO-2136 — loads aggregate not on envelope.
            kpiCell(label: "LOADS YTD",
                    value: "—",
                    valueStyle: .neutral,
                    trail: "pending",
                    trailColor: palette.textSecondary,
                    showWarn: false)
            kpiDivider
            kpiCell(label: "EXPIRING",
                    value: "\(expiring)",
                    valueStyle: .neutral,
                    trail: expiring > 0 ? "renew now" : "all clean",
                    trailColor: expiring > 0 ? Brand.warning : palette.textSecondary,
                    showWarn: expiring > 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private enum ValueStyle { case gradient, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String,
                         trailColor: Color,
                         showWarn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if showWarn {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                }
                Text(trail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(trailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: Search bar (preserved supplemental)

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Search · name · MC# · DOT# · state", text: $store.search)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: store.search) { _, _ in Task { await store.load() } }
            if !store.search.isEmpty {
                Button { store.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Filter chip row

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PartnerFilter.allCases) { f in
                    filterChip(f, count: count(for: f))
                }
                Color.clear.frame(width: 16, height: 1)
            }
            .padding(.horizontal, Space.s3)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for filter: PartnerFilter) -> String {
        switch filter {
        case .all:        return "\(store.unfiltered.count)"
        case .favorites:
            return "\(store.unfiltered.filter { ($0.agreementStatus ?? "").lowercased() == "active" }.count)"
        case .tanker, .reefer, .cryo:
            return "—"
        }
    }

    @ViewBuilder
    private func filterChip(_ f: PartnerFilter, count: String) -> some View {
        let isActive = (store.filter == f)
        let label = "\(f.label) · \(count)"
        Button(action: { tapFilter(f) }) {
            if isActive {
                HStack(spacing: 6) {
                    if f.withStar {
                        PartnerStar().fill(.white).frame(width: 10, height: 10)
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient.primary))
            } else {
                HStack(spacing: 6) {
                    if f.withStar {
                        PartnerStar().fill(Brand.hazmat).frame(width: 10, height: 10)
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: PartnerFilter) {
        store.filter = f
        // observability post — telemetry only; real effect is `store.filter = f` above
        NotificationCenter.default.post(
            name: .eusoShipperPartnerFilter,
            object: nil,
            userInfo: [
                "source": "224_ShipperPartnerDirectory",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Partner list card

    private func partnerListCard(_ rows: [SupplyChainAPI.Partner]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, partner in
                partnerRow(partner)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, Space.s4)
                }
            }
            Text("Tap a partner to see contracts & lane history")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LinearGradient.primary)
                .padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private func partnerRow(_ p: SupplyChainAPI.Partner) -> some View {
        let agr = canonAgrStatus(p)
        let avatar = avatarTone(p)
        let isFav = (p.agreementStatus ?? "").lowercased() == "active"

        return Button(action: { tapRow(p) }) {
            HStack(alignment: .top, spacing: Space.s3) {
                Capsule(style: .continuous)
                    .fill(rimPaint(for: agr))
                    .frame(width: 3, height: 64)
                    .padding(.top, 4)

                avatarBadge(monogram: monogram(p.companyName ?? "?"), tone: avatar)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(p.companyName ?? "Unknown")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if isFav {
                            PartnerStar().fill(Brand.hazmat).frame(width: 10, height: 10)
                        }
                    }
                    Text(credentialLine(p))
                        .font(EType.mono(.caption))
                        .tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.bottom, 2)

                    HStack(spacing: Space.s5) {
                        statCell(label: "LOADS",   value: "—")
                        statCell(label: "ON-TIME", value: "—")
                        statCell(label: "AGR",
                                 value: agrText(for: agr),
                                 color: agrColor(for: agr),
                                 compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                indexBadge(p)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PartnerRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(p.companyName ?? "Unknown")\(isFav ? ", favorited" : ""), \(credentialLine(p)), agreement \(agrText(for: agr))"
        )
    }

    private func canonAgrStatus(_ p: SupplyChainAPI.Partner) -> AgrStatus {
        switch (p.agreementStatus ?? "").lowercased() {
        case "active":             return .active
        case "pending_signature":  return .awaiting
        case "expired":            return .expiring
        default:                   return .none
        }
    }

    private func avatarTone(_ p: SupplyChainAPI.Partner) -> AvatarTone {
        let n = (p.companyName ?? "").lowercased()
        if n.contains("eusotrans") { return .gradient }
        if n.contains("hazmat") || n.contains("petroleum") || n.contains("fuel") || n.contains("tanker") { return .hazmat }
        if n.contains("cold") || n.contains("reefer") || n.contains("refriger") { return .info }
        if n.contains("cryogenic") || n.contains("nh3") || n.contains("ammonia") || n.contains("escort") { return .escort }
        return .rail
    }

    private func monogram(_ name: String) -> String {
        let initials = name.split(separator: " ").compactMap { $0.first.map(String.init) }
            .prefix(2).joined().uppercased()
        return initials.isEmpty ? "?" : initials
    }

    private func credentialLine(_ p: SupplyChainAPI.Partner) -> String {
        var parts: [String] = []
        if let dot = p.companyDot, !dot.isEmpty { parts.append("DOT \(dot)") }
        if let mc = p.companyMc, !mc.isEmpty { parts.append("MC-\(mc)") }
        if let st = p.companyState, !st.isEmpty { parts.append(st.uppercased()) }
        return parts.isEmpty ? "USDOT pending" : parts.joined(separator: " · ")
    }

    private func statCell(label: String,
                          value: String,
                          color: Color? = nil,
                          compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: compact ? 11 : 13, weight: .bold).monospacedDigit())
                .foregroundStyle(color ?? palette.textPrimary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func avatarBadge(monogram: String, tone: AvatarTone) -> some View {
        switch tone {
        case .gradient:
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                Text(monogram)
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
            }
        case .hazmat:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.hazmat.opacity(0.18),
                         text:  Brand.hazmat)
        case .info:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.info.opacity(0.16),
                         text:  Brand.info)
        case .escort:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.escort.opacity(0.14),
                         text:  Brand.escort)
        case .rail:
            tintedAvatar(monogram: monogram,
                         fill:  Brand.rail.opacity(0.16),
                         text:  Brand.rail)
        }
    }

    private func tintedAvatar(monogram: String, fill: Color, text: Color) -> some View {
        ZStack {
            Circle().fill(fill).frame(width: 44, height: 44)
            Text(monogram)
                .font(.system(size: 14, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(text)
        }
    }

    @ViewBuilder
    private func indexBadge(_ p: SupplyChainAPI.Partner) -> some View {
        // EUSO-2136 — composite/index not on envelope; paint placeholder
        // badge with neutral tier styling.
        let tier: PartnerDirectoryBadgeTier = (p.companyName ?? "").lowercased().contains("eusotrans")
            ? .gradientHero : .goldHollow
        let letter = tier == .gradientHero ? "P1" : "P—"
        let badgeShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let goldFade = LinearGradient(
            colors: [Color(hex: 0xFFB100), Color(hex: 0xFFA726)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        ZStack {
            switch tier {
            case .gradientHero:
                badgeShape.fill(LinearGradient.diagonal)
                gradeText(letter, "house",
                          color: .white,
                          subColor: .white.opacity(0.85))
            case .gradientHollow:
                badgeShape.fill(palette.bgCard)
                badgeShape.strokeBorder(LinearGradient.primary, lineWidth: 2)
                gradeTextGradient(letter, "—",
                                  subColor: palette.textSecondary)
            case .goldHero:
                badgeShape.fill(goldFade)
                gradeText(letter, "—",
                          color: .white,
                          subColor: .white.opacity(0.85))
            case .goldHollow:
                badgeShape.fill(palette.bgCard)
                badgeShape.strokeBorder(goldFade, lineWidth: 2)
                gradeText(letter, "—",
                          color: Color(hex: 0xB27300),
                          subColor: palette.textSecondary)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func gradeText(_ grade: String,
                           _ composite: String,
                           color: Color,
                           subColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(grade)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(composite)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(subColor)
        }
    }

    private func gradeTextGradient(_ grade: String,
                                   _ composite: String,
                                   subColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(grade)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(composite)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(subColor)
        }
    }

    // MARK: Status grammar helpers

    private func rimPaint(for status: AgrStatus) -> AnyShapeStyle {
        switch status {
        case .active:
            return AnyShapeStyle(LinearGradient.diagonal)
        case .expiring:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xFFB100), Color(hex: 0xFFA726)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .awaiting:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: 0xFF9500), Color(hex: 0xFF7A00)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .none:
            return AnyShapeStyle(palette.textTertiary)
        }
    }

    private func agrText(for status: AgrStatus) -> String {
        switch status {
        case .active:    return "ACTIVE"
        case .expiring:  return "EXPIRING"
        case .awaiting:  return "AWAITING SIG"
        case .none:      return "—"
        }
    }

    private func agrColor(for status: AgrStatus) -> Color? {
        switch status {
        case .active:    return Brand.success
        case .expiring:  return Color(hex: 0xB27300)
        case .awaiting:  return Color(hex: 0xFF7A00)
        case .none:      return palette.textTertiary
        }
    }

    // MARK: Formula footer

    private var formulaFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PARTNERSHIP INDEX")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("index = onTime · 0.4 + completion · 0.3 + log₁₀(loads+1)/log₁₀(50) · 0.2 + spend · 0.1")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s2)
    }

    // MARK: Notification posts (§20.4)

    private func tapRow(_ p: SupplyChainAPI.Partner) {
        // Real action: jump to 213 Catalyst Scorecards filtered to
        // this partner so the founder sees their lane history,
        // on-time rate, and grade in-app. Replaces openURL stub.
        NotificationCenter.default.post(
            name: .eusoShipperPartnerRow,
            object: nil,
            userInfo: [
                "source": "224_ShipperPartnerDirectory",
                "partnershipId": p.id,
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "213", "partnerId": p.id]
        )
    }

    // MARK: Empty / error

    private var emptyOrNoMatchCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(store.filter == .all ? "No partners yet" : "No matches for this filter")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(store.filter == .all
                 ? "Invite your first catalyst to start building your private rolodex."
                 : "Try a different filter, or check back when an agreement signs.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                // Real action: compose a mail to ops to broker a
                // partner introduction. Replaces openURL stub. The
                // dedicated in-app invite form ships in a follow-up.
                NotificationCenter.default.post(
                    name: .eusoShipperPartnerInvite,
                    object: nil,
                    userInfo: [
                        "source": "224_ShipperPartnerDirectory",
                        "shipperCompanyId": 1
                    ]
                )
                let body = "I'd like to invite a partner. Carrier name / MC# / lanes / hazmat capability are below."
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:ops@eusotrip.com?subject=Partner%20invite&body=\(body)") {
                    openURL(url)
                }
            } label: {
                Text("Invite a partner")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Press feedback

private struct PartnerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Star (§19.2 file-scoped 5-point glyph)

private struct PartnerStar: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = [
            CGPoint(x: 5,   y: 0),
            CGPoint(x: 6.2, y: 3.6),
            CGPoint(x: 10,  y: 3.6),
            CGPoint(x: 7,   y: 5.8),
            CGPoint(x: 8.2, y: 9.4),
            CGPoint(x: 5,   y: 7.2),
            CGPoint(x: 1.8, y: 9.4),
            CGPoint(x: 3,   y: 5.8),
            CGPoint(x: 0,   y: 3.6),
            CGPoint(x: 3.8, y: 3.6),
        ]
        let sx = rect.width / 10.0
        let sy = rect.height / 9.4
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x = rect.minX + p.x * sx
            let y = rect.minY + p.y * sy
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Favorites / Tanker / Reefer / Cryo).
    static let eusoShipperPartnerFilter = Notification.Name("eusoShipperPartnerFilter")
    /// Partner row tap — opens the detail sheet via MeAction hand-off.
    static let eusoShipperPartnerRow    = Notification.Name("eusoShipperPartnerRow")
    /// "Invite a partner" CTA tap on the empty state.
    static let eusoShipperPartnerInvite = Notification.Name("eusoShipperPartnerInvite")
}

// MARK: - Previews

#Preview("224 · Partner Directory · Dark") {
    ShipperPartnerDirectory()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("224 · Partner Directory · Light") {
    ShipperPartnerDirectory()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
