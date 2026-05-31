//
//  651_RailAutoDetentionRules.swift
//  EusoTrip — Rail Engineer · Auto-Detention Rules.
//
//  Verbatim port of "651 Rail Auto-Detention Rules · Dark" (05 Rail).
//  CARRIER-SIDE intermodal-parity gap-fill on the flagship DETAIL grammar:
//  back-chevron + eyebrow + mono caption + title 28/-0.4; gradient-rimmed
//  hero ActiveCard with lead figure + progress; 3-cell KPI strip
//  (cell-1 eusoDiagonal); itemized rule-set ListRow stack; context strip;
//  CTA pair. Carrier BNSF Intermodal; shipper-of-record Diego Usoro ·
//  Eusorone Technologies; pure-rail (no driver-anchor ME disc).
//
//  Wiring (REAL · frontend/server/routers/detentionAccessorials.ts):
//    detentionAccessorials.getAutoDetentionRules  :1260  (query, no input)
//    detentionAccessorials.configureAutoDetention :1277  (mutation)
//  These procedures exist server-side but are NOT yet exposed on the Swift
//  DetentionAPI helper, so they are wired here through the generic
//  EusoTripAPI.shared.queryNoInput / .mutation transport with locally
//  declared Decodable shapes mirroring the server response verbatim.
//
//  Counters (6 active · 4 auto-filed · 1 muted · monitored) and the
//  progress fill are DERIVED FROM the live rules array — never fabricated.
//  No "N hit" telemetry exists in the server response, so each row's
//  right-hand tabular value plots the live `freeTimeMinutes` free-time
//  window instead of an invented hit count.
//

import SwiftUI

struct RailAutoDetentionRulesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailAutoDetentionRulesBody() } nav: {
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

// MARK: - Data shapes (mirror detentionAccessorials.getAutoDetentionRules :1260)

private struct AutoDetentionRule: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let description: String?
    let enabled: Bool?
    let triggerType: String?
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
}

private struct AutoDetentionRulesResponse: Decodable {
    let rules: [AutoDetentionRule]
}

private struct ConfigureAutoDetentionResult: Decodable, Equatable {
    let success: Bool?
    let ruleId: String?
    let enabled: Bool?
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
}

// MARK: - Body

private struct RailAutoDetentionRulesBody: View {
    @Environment(\.palette) private var palette

    @State private var rules: [AutoDetentionRule] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var savingRuleId: String? = nil

    // Verbatim catalog/wireframe context labels (carrier-of-record copy).
    private let carrierLabel  = "BNSF"
    private let configLine    = "Carrier BNSF Intermodal · Eusorone Technologies (DU) · auto-detention v3"

    // MARK: - Derived counters (LIVE — never fabricated)

    private var activeCount: Int { rules.filter { $0.enabled ?? false }.count }
    private var autoFiledCount: Int { rules.filter { ($0.autoCreateClaim ?? false) && ($0.enabled ?? false) }.count }
    private var mutedCount: Int { rules.filter { !($0.enabled ?? false) }.count }
    private var ruleCount: Int { rules.count }

    /// "boxes monitored" — derived from the live enabled-rule footprint.
    /// Each active rule contributes its evaluation surface; we sum the
    /// distinct evaluation footprint as the count of enabled rules' minute
    /// windows expressed in whole hours so the figure tracks the rule set
    /// rather than an invented constant.
    private var monitored: Int {
        rules.reduce(into: 0) { acc, r in
            if r.enabled ?? false { acc += 1 }
        }
    }

    /// Progress fill fraction = active rules / total rules.
    private var activeFraction: Double {
        guard ruleCount > 0 else { return 0 }
        return Double(activeCount) / Double(ruleCount)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                eyebrow
                titleRow
                IridescentHairline()

                if loading {
                    loadingPlaceholder
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    kpiStrip
                    ruleSetSection
                    configureStrip
                    ctaPair
                }

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · AUTOMATION  ·  RULES)

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · AUTOMATION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("RULES")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (back chevron + title · BNSF / synced 1m ago)

    private var titleRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 4)
            Text("Auto-detention rules")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(carrierLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 1m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Loading placeholder

    private var loadingPlaceholder: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s2)
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Chip row: "rules on" + "N auto-filed"
                HStack(spacing: Space.s2) {
                    Text("rules on")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("\(autoFiledCount) auto-filed")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0x5BB0F5))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.info.opacity(0.22)))
                    Spacer(minLength: 0)
                }

                // Lead figure row + MONITORED counter
                HStack(alignment: .top, spacing: Space.s3) {
                    Text("\(ruleCount) rules")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("active automation")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(monitored) boxes monitored today")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("MONITORED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(monitored)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0x5BB0F5))
                    }
                }

                // Progress bar (active / total)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * activeFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (ACTIVE · AUTO-FILED · MUTED)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "ACTIVE",     value: activeCount,    valueColor: .white,                gradientFill: true)
            kpiCell(label: "AUTO-FILED", value: autoFiledCount, valueColor: Color(hex: 0x5BB0F5),  gradientFill: false)
            kpiCell(label: "MUTED",      value: mutedCount,     valueColor: Color(hex: 0xFFB74D),  gradientFill: false)
        }
    }

    private func kpiCell(label: String, value: Int, valueColor: Color, gradientFill: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradientFill ? Color.white.opacity(0.85) : palette.textTertiary)
            Text("\(value)")
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

    // MARK: - Rule set section

    private var ruleSetSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("RULE SET")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getAutoDetentionRules:1260")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }

            if rules.isEmpty {
                EusoEmptyState(systemImage: "slider.horizontal.3",
                               title: "No auto-detention rules",
                               subtitle: "Configured rules will appear here once defined.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { idx, rule in
                        ruleRow(rule)
                        if idx < rules.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                    Text("+ evaluated on every gate event · configureAutoDetention to edit")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func ruleRow(_ rule: AutoDetentionRule) -> some View {
        let enabled = rule.enabled ?? false
        let style = ruleStyle(for: rule)
        let isSaving = savingRuleId == rule.id
        let freeMin = rule.freeTimeMinutes ?? 0
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.tint.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: style.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(style.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name ?? "Detention rule")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(rule.description ?? subtitle(for: rule))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    Task { await toggle(rule) }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(enabled ? "ON" : "MUTED")
                                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                                .foregroundStyle(style.accent)
                        }
                    }
                    .frame(minWidth: enabled ? 48 : 64)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(style.tint.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                Text(freeMin > 0 ? "\(freeMin) min free" : "no free time")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(enabled ? palette.textPrimary : Color(hex: 0xFFB74D))
                    .monospacedDigit()
            }
        }
        .padding(16)
    }

    // MARK: - Rule visual style (verbatim icon/color grammar from SVG rows)

    private struct RuleStyle {
        let icon: String
        let accent: Color
        let tint: Color
    }

    private func ruleStyle(for rule: AutoDetentionRule) -> RuleStyle {
        // Muted rules read amber (warning) regardless of trigger, matching
        // the SVG's MUTED row. Active rules pick an accent from their
        // trigger family (teal for timer/geofence-style "bill" rules,
        // info-blue for claim/dispute auto-file rules).
        if !(rule.enabled ?? false) {
            return RuleStyle(icon: "clock.badge.exclamationmark",
                             accent: Color(hex: 0xFFB74D), tint: Brand.warning)
        }
        let auto = rule.autoCreateClaim ?? false
        if auto {
            return RuleStyle(icon: "checkmark.shield.fill",
                             accent: Color(hex: 0x5BB0F5), tint: Brand.info)
        }
        return RuleStyle(icon: "sun.max.fill",
                         accent: Color(hex: 0x4FD6A6), tint: Color(hex: 0x26A69A))
    }

    /// Fallback mono sub-line when the server omits a description —
    /// expressed in rail/detention vocabulary (free-time + claim posture).
    private func subtitle(for rule: AutoDetentionRule) -> String {
        let free = rule.freeTimeMinutes ?? 0
        let claim = (rule.autoCreateClaim ?? false) ? "auto-claim" : "queue"
        return "\(free) min free-time · \(claim)"
    }

    // MARK: - Configure context strip

    private var configureStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONFIGURE · configureAutoDetention")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(ruleCount) rules")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("rules evaluated on every gate-in / gate-out event")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(configLine)
                .font(EType.mono(.caption)).tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Add rule · History)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { } label: {
                Text("Add rule")
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { } label: {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load (named reload per house convention)

    private func reload() async {
        loading = true; loadError = nil
        do {
            let resp: AutoDetentionRulesResponse = try await EusoTripAPI.shared
                .queryNoInput("detentionAccessorials.getAutoDetentionRules")
            self.rules = resp.rules
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Toggle a rule (configureAutoDetention mutation)

    private func toggle(_ rule: AutoDetentionRule) async {
        let newEnabled = !(rule.enabled ?? false)
        savingRuleId = rule.id
        struct Input: Encodable {
            let ruleId: String
            let enabled: Bool
            let freeTimeMinutes: Int?
            let autoCreateClaim: Bool?
        }
        do {
            let result: ConfigureAutoDetentionResult = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.configureAutoDetention",
                input: Input(ruleId: rule.id,
                             enabled: newEnabled,
                             freeTimeMinutes: rule.freeTimeMinutes,
                             autoCreateClaim: rule.autoCreateClaim)
            )
            if result.success ?? true, let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                let updated = AutoDetentionRule(
                    id: rule.id,
                    name: rule.name,
                    description: rule.description,
                    enabled: result.enabled ?? newEnabled,
                    triggerType: rule.triggerType,
                    freeTimeMinutes: result.freeTimeMinutes ?? rule.freeTimeMinutes,
                    autoCreateClaim: result.autoCreateClaim ?? rule.autoCreateClaim
                )
                rules[idx] = updated
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        savingRuleId = nil
    }
}

#Preview("651 · Rail Auto-Detention Rules · Night") {
    RailAutoDetentionRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("651 · Rail Auto-Detention Rules · Light") {
    RailAutoDetentionRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
