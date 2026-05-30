//
//  597_RailHazmatDGRules.swift
//  EusoTrip — Rail Engineer · Hazmat DG Rules (regulation reference library).
//
//  Verbatim port of wireframe "597 Rail Hazmat DG Rules · Dark".
//  ARCHETYPE = REGULATION REFERENCE LIBRARY: Class-3 placard diamond hero +
//  authority-grouped citation cards with section anchors + cross-border delta
//  cards. Leads with the active consist's hazmat placard and reads as a
//  regulation reference keyed to the cars on the train. The carrier gets the
//  binding DG rules for this consist (key-train speed caps, ECP, HCA) plus the
//  deltas when it crosses to CA/MX.
//
//  tRPC: railShipments.getCrossBorderDGRailRegs (per-country DG rule sets,
//  service crossBorderRail.ts RAIL_DG_REGULATIONS: US DOT HMR, CA TDG,
//  MX NOM-002-SCT). RBAC railProcedure. transportMode=rail; US primary + CA/MX
//  delta. NAV (REAL): HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//

import SwiftUI

struct RailHazmatDGRulesScreen: View {
    let theme: Theme.Palette
    /// Defaulted context fields — the screen reads the US/CA/MX DG rule sets
    /// from the live endpoint and is keyed to the active consist. Defaulted so
    /// the only required init param is `theme`.
    var consistUNNumber: String = "1203"
    var consistCommodity: String = "Gasoline"
    var consistHazClass: String = "CLASS 3 FLAMMABLE"
    var consistDetail: String = "24 tank cars · key train · 50 mph cap"

    var body: some View {
        Shell(theme: theme) {
            RailHazmatDGRulesBody(consistUNNumber: consistUNNumber,
                                  consistCommodity: consistCommodity,
                                  consistHazClass: consistHazClass,
                                  consistDetail: consistDetail)
        } nav: {
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

// MARK: - Data shape (railShipments.getCrossBorderDGRailRegs → RailDGRegulation)
//
// Mirrors service crossBorderRail.ts RailDGRegulation: one row per country.
// The endpoint returns a single optional object for the requested country.

private struct RailDGRegulation: Decodable {
    let country: String?
    let regulationName: String?
    let authority: String?
    let keyRules: [String]?
    let placardDifferences: String?
    let crossBorderNotes: String?
}

// MARK: - Body

private struct RailHazmatDGRulesBody: View {
    @Environment(\.palette) private var palette

    let consistUNNumber: String
    let consistCommodity: String
    let consistHazClass: String
    let consistDetail: String

    @State private var usRegs: RailDGRegulation? = nil
    @State private var caRegs: RailDGRegulation? = nil
    @State private var mxRegs: RailDGRegulation? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow
            titleRow
            IridescentHairline()
                .padding(.top, Space.s4)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    loadingSkeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    placardHero
                    keyTrainRulesSection
                    crossBorderDeltaSection
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow (RAIL ENGINEER · DG RULES   ·   49 CFR · TDG · NOM)

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · DG RULES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("49 CFR · TDG · NOM")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Title row (back chevron · "Hazmat DG rules" · overflow dots)

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Hazmat DG rules")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Placard hero (Class-3 diamond + active consist)
    //
    // SVG: 400×120 card #1C2128, rotated-45 red diamond placard with flame
    // glyph + UN number "1203", then ACTIVE CONSIST eyebrow, "UN1203 ·
    // Gasoline", mono detail line, and a DOT HMR · PHMSA authority chip.

    private var placardHero: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            placardDiamond
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTIVE CONSIST · \(consistHazClass)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("UN\(consistUNNumber) · \(consistCommodity)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(consistDetail)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                if let chip = usRegs.flatMap(authorityChipLabel) {
                    Text(chip)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.info)
                        .padding(.horizontal, Space.s3).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.info.opacity(0.14)))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// "DOT HMR · PHMSA" chip text derived from the US regulation row.
    private func authorityChipLabel(_ r: RailDGRegulation) -> String? {
        let name = r.regulationName?.trimmingCharacters(in: .whitespaces)
        let auth = r.authority?.trimmingCharacters(in: .whitespaces)
        switch (name, auth) {
        case let (n?, a?) where !n.isEmpty && !a.isEmpty: return "\(n) · \(a)".uppercased()
        case let (n?, _) where !n.isEmpty:                return n.uppercased()
        case let (_, a?) where !a.isEmpty:                return a.uppercased()
        default:                                          return nil
        }
    }

    /// Class-3 flammable placard diamond — red rotated square with a flame
    /// glyph over the UN number, matching the SVG hero.
    private var placardDiamond: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Brand.danger.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Brand.danger, lineWidth: 2))
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(45))
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text(consistUNNumber)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(width: 96, height: 96)
    }

    // MARK: - Key train rules (US · 49 CFR 171–180)
    //
    // SVG: section eyebrow + a 400×190 card holding four citation rows, each
    // with a mono §-anchor chip + rule copy and hairline separators. The rows
    // come straight from the US RAIL_DG_REGULATIONS.keyRules array; the
    // §-anchor chip is derived per-rule so the live data drives the card.

    private var keyTrainRulesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("KEY TRAIN RULES · US · 49 CFR 171–180")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if let rules = usRegs?.keyRules, !rules.isEmpty {
                let parsed = rules.map(parseKeyRule)
                VStack(spacing: 0) {
                    ForEach(Array(parsed.enumerated()), id: \.offset) { idx, row in
                        keyRuleRow(anchor: row.anchor, text: row.text)
                        if idx < parsed.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.leading, Space.s4)
                        }
                    }
                }
                .padding(.vertical, Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                               title: "No DG rules",
                               subtitle: "US DG rail regulations will appear here.")
            }
        }
    }

    /// Split a key-rule string into a short §/code anchor + the human copy.
    /// The service stores rules like "49 CFR 171-180", "Key trains: 20+ tank
    /// cars or 35+ hazmat", "50mph max key trains", "40mph in HCAs", "ECP
    /// brakes HHFT >70 cars". The SVG derives a §172/§174/HCA/HHFT chip from
    /// each; we map the same anchors by keyword so the live array drives them.
    private func parseKeyRule(_ rule: String) -> (anchor: String, text: String) {
        let lower = rule.lowercased()
        let anchor: String
        if lower.contains("key train") || lower.contains("tank car") || lower.contains("hazmat car") || lower.contains("35+") || lower.contains("20+") {
            anchor = "§172"
        } else if lower.contains("max") || lower.contains("50mph") || lower.contains("50 mph") || (lower.contains("mph") && lower.contains("key")) {
            anchor = "§174"
        } else if lower.contains("hca") || lower.contains("high-threat") || lower.contains("high threat") || lower.contains("urban") {
            anchor = "HCA"
        } else if lower.contains("ecp") || lower.contains("hhft") || lower.contains("brake") {
            anchor = "HHFT"
        } else if lower.contains("cfr") {
            anchor = "CFR"
        } else {
            anchor = "DG"
        }
        return (anchor, rule)
    }

    private func keyRuleRow(anchor: String, text: String) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(anchor)
                .font(EType.mono(.micro)).tracking(0.2)
                .foregroundStyle(Brand.info)
                .frame(width: 46, height: 22)
                .background(Capsule().fill(Brand.info.opacity(0.12)))
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - Cross-border delta (CA TDG · MX NOM-002-SCT)
    //
    // SVG: section eyebrow + two side-by-side 194×118 cards. Left = CA badge +
    // "TDG Regs" + 3 bullet rules; right = MX badge + "NOM-002-SCT" + 3 bullet
    // rules. Bullets come from each country's keyRules array (first 3 rules
    // that differ from the US base).

    private var crossBorderDeltaSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CROSS-BORDER DELTA")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                deltaCard(badge: "CA",
                          badgeColor: Brand.escort,
                          name: caRegs?.regulationName ?? "TDG Regs",
                          rules: caRegs?.keyRules)
                deltaCard(badge: "MX",
                          badgeColor: Brand.warning,
                          name: mxRegs?.regulationName ?? "NOM-002-SCT",
                          rules: mxRegs?.keyRules)
            }
        }
    }

    private func deltaCard(badge: String, badgeColor: Color, name: String, rules: [String]?) -> some View {
        // Take the most distinctive 3 rules (the SVG shows 3 bullets per card).
        let bullets = Array((rules ?? []).suffix(3))
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text(badge)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(badgeColor)
                    .frame(width: 40, height: 24)
                    .background(Capsule().fill(badgeColor.opacity(0.14)))
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if bullets.isEmpty {
                Text("No delta on file")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, rule in
                        Text(rule)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA row (Open 49 CFR 172 · Placards)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Open 49 CFR 172")
            Button {
                // Placard reference — opens the placard library sheet when wired.
            } label: {
                Text("Placards")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Load
    //
    // getCrossBorderDGRailRegs takes an optional { country } and returns the
    // single RailDGRegulation row for that country. We fetch all three (US
    // primary + CA/MX delta) in parallel, matching the SVG's US placard +
    // key-train card and the two cross-border delta cards.

    private func load() async {
        loading = true; loadError = nil
        struct CountryIn: Encodable { let country: String }
        do {
            async let us: RailDGRegulation = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "US"))
            async let ca: RailDGRegulation = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "CA"))
            async let mx: RailDGRegulation = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "MX"))
            let (u, c, m) = try await (us, ca, mx)
            self.usRegs = u
            self.caRegs = c
            self.mxRegs = m
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("597 · Rail Hazmat DG Rules · Night") { RailHazmatDGRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("597 · Rail Hazmat DG Rules · Light") { RailHazmatDGRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
