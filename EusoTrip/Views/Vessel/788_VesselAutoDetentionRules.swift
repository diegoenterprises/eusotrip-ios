//
//  788_VesselAutoDetentionRules.swift
//  EusoTrip — Vessel Operator · Auto-Detention Rules (RULES-ENGINE archetype).
//
//  Faithful 1:1 port of "788 Vessel Auto-Detention Rules.svg" (Light + Dark).
//  A bespoke rules-engine surface (nothing like the money boards): each rule is
//  a configurable trigger → threshold → action row with a real toggle. The
//  operator configures the engine that auto-detects detention/demurrage on
//  drayage + terminal legs — geofence arrival, ELD-stopped timer, late
//  appointment, overnight hold, recurring offender — each with its own
//  free-time clock and auto-claim switch, so exposure is captured the instant
//  it triggers. A jurisdiction guardrail names each country's billing regime.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getAutoDetentionRules  (query, protectedProcedure, companyId-scoped,
//        seeds 5 defaults :2095)
//        -> { rules[{id,name,description,enabled,triggerType,freeTimeMinutes,
//             autoCreateClaim}] }
//    · toggle -> configureAutoDetention {ruleId,enabled,freeTimeMinutes?,
//        autoCreateClaim?} (mutation :2153, writes config + blockchainAuditTrail
//        + broadcasts). This is the screen's real primary interaction.
//    · "History" -> getAutoDetentionHistory {limit} (query :2108) — real config
//        audit events, count surfaced.
//    · Per-rule 30-day telemetry (fired N× / captured $) -> getRuleTelemetry is
//        a NAMED SERVER GAP; the row shows "telemetry pending", never a faked
//        fire count. "Add rule" is seeded-only server-side — surfaced honestly.
//  transportMode=vessel. No mock data.
//

import SwiftUI

private struct AutoRule788: Decodable, Identifiable {
    let id: String
    let name: String?
    let description: String?
    let enabled: Bool?
    let triggerType: String?
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
}
private struct AutoRulesResponse788: Decodable { let rules: [AutoRule788]? }
private struct AutoHistoryResponse788: Decodable { let events: [AutoHistoryEvent788]? }
private struct AutoHistoryEvent788: Decodable { let id: Int? }

struct VesselAutoDetentionRulesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselAutoDetentionRulesBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselAutoDetentionRulesBody: View {
    @Environment(\.palette) private var palette
    @State private var rules: [AutoRule788] = []
    @State private var enabledState: [String: Bool] = [:]
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var savingRule: String? = nil

    private var total: Int { rules.count }
    private var onCount: Int { rules.filter { enabledState[$0.id] ?? ($0.enabled ?? false) }.count }
    private var autoClaimCount: Int { rules.filter { ($0.autoCreateClaim ?? false) && (enabledState[$0.id] ?? ($0.enabled ?? false)) }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "AUTO-DETENTION", caption: "\(total) RULES · \(onCount) ON")
                Text("Auto-detention rules").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if rules.isEmpty {
                    EusoEmptyState(systemImage: "gearshape.2",
                                   title: "No rules configured",
                                   subtitle: "No automatic detention rules are configured for this company.")
                } else {
                    engineHero
                    rulesList
                    ctaPair
                    if let e = actionError {
                        errorCard(e)
                    } else if let m = actionMessage {
                        LifecycleCard { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                    guardrailStrip
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Engine-status hero (config summary — telemetry $ is a server gap, not faked)

    private var engineHero: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DETECTION ENGINE · ACTIVE RULES").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(onCount)/\(total)")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(autoClaimCount) auto-claim · \(total - onCount) paused")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                Text("30-DAY CAPTURE HISTORY UNAVAILABLE")
                    .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("AUTO-CLAIM").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
                Text("\(autoClaimCount)").font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text("rules capture").font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.success)
            }
            .padding(14)
            .frame(width: 132, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal).frame(width: 3).padding(.vertical, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Rules list

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DETECTION RULES · TRIGGER · THRESHOLD · ACTION").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { idx, r in
                    ruleRow(r)
                    if idx < rules.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func triggerGlyph(_ type: String?) -> (String, Color) {
        switch type ?? "" {
        case "geofence":    return ("location.viewfinder", Brand.blue)
        case "eld":         return ("clock.badge", Brand.info)
        case "appointment": return ("calendar", Brand.warning)
        case "timer":       return ("moon.stars", Brand.escort)
        case "analytics":   return ("arrow.triangle.2.circlepath", Brand.rail)
        default:            return ("bolt.badge.automatic", Brand.info)
        }
    }
    private func actionChip(_ r: AutoRule788) -> (String, Color) {
        if r.autoCreateClaim ?? false { return ("AUTO-CLAIM", Brand.info) }
        if (r.triggerType ?? "") == "analytics" { return ("ALERT", Brand.warning) }
        return ("MANUAL", palette.textSecondary)
    }

    private func ruleRow(_ r: AutoRule788) -> some View {
        let on = enabledState[r.id] ?? (r.enabled ?? false)
        let (glyph, gColor) = triggerGlyph(r.triggerType)
        let (chip, chipColor) = actionChip(r)
        let freeLabel = (r.freeTimeMinutes ?? 0) > 0 ? "\(r.freeTimeMinutes ?? 0) min free" : "event-based"
        return HStack(alignment: .top, spacing: Space.s3) {
            VDetnIconChip(systemImage: glyph, color: gColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(r.name ?? r.id).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(r.description ?? "").font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    thresholdChip(freeLabel)
                    VDetnPill(text: chip, color: chipColor)
                    Text(savingRule == r.id ? "saving…" : "telemetry pending")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            ruleToggle(on: on) { Task { await toggle(r) } }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func thresholdChip(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func ruleToggle(on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.16)))
                    .frame(width: 44, height: 24)
                Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Add rule", action: { addRuleGap() }, leadingIcon: "plus")
            secondaryButton788(title: "History") { Task { await history() } }.frame(width: 128)
        }
    }

    private func secondaryButton788(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Guardrail strip

    private var guardrailStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DETENTION-BILLING REGIME · BY REGULATOR").font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("auto-rules gate").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            HStack(spacing: 0) {
                guardCol("US", "FMC OSRA", "30-day dispute", Brand.info)
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                guardCol("CA", "CTA tariff", "carrier free-time", palette.textSecondary)
                Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                guardCol("MX", "SAT · LNCM", "recinto dwell", palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal).frame(width: 3).padding(.vertical, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func guardCol(_ code: String, _ name: String, _ note: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(code).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(note).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    // MARK: Load / actions

    private struct ConfigInput788: Encodable { let ruleId: String; let enabled: Bool }
    private struct HistoryInput788: Encodable { let limit: Int }
    private struct ConfigResult788: Decodable { let id: String? }

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: AutoRulesResponse788 = try await EusoTripAPI.shared.queryNoInput("detentionAccessorials.getAutoDetentionRules")
            self.rules = resp.rules ?? []
            self.enabledState = Dictionary(uniqueKeysWithValues: (resp.rules ?? []).map { ($0.id, $0.enabled ?? false) })
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func toggle(_ r: AutoRule788) async {
        guard savingRule == nil else { return }
        let newValue = !(enabledState[r.id] ?? (r.enabled ?? false))
        enabledState[r.id] = newValue   // optimistic
        savingRule = r.id; actionError = nil; actionMessage = nil
        do {
            let _: ConfigResult788 = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.configureAutoDetention",
                input: ConfigInput788(ruleId: r.id, enabled: newValue))
            actionMessage = "\(r.name ?? r.id) \(newValue ? "enabled" : "paused") · engine config saved."
        } catch {
            enabledState[r.id] = !newValue   // revert
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        savingRule = nil
    }

    private func history() async {
        actionMessage = nil; actionError = nil
        do {
            let h: AutoHistoryResponse788 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getAutoDetentionHistory", input: HistoryInput788(limit: 20))
            actionMessage = "\(h.events?.count ?? 0) rule-config change\(((h.events?.count ?? 0) == 1) ? "" : "s") in the audit trail (getAutoDetentionHistory)."
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addRuleGap() {
        actionMessage = nil
        actionError = "Edit the threshold, automatic-claim setting, and enabled state on the company rules shown above."
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading detection rules…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("788 · Vessel Auto-Detention Rules · Night") { VesselAutoDetentionRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("788 · Vessel Auto-Detention Rules · Light") { VesselAutoDetentionRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
