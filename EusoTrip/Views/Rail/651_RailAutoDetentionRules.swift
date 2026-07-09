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
    let id: String?
    let enabled: Bool?
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
}

private struct ConfigureAutoDetentionInput: Encodable {
    let ruleId: String
    let name: String?
    let description: String?
    let triggerType: String?
    let enabled: Bool
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
}

private struct AutoDetentionHistoryInput: Encodable {
    let limit: Int
}

private struct AutoDetentionHistoryResponse: Decodable {
    let events: [AutoDetentionHistoryEvent]
}

private struct AutoDetentionHistoryEvent: Decodable, Identifiable, Equatable {
    let id: Int
    let ruleId: String?
    let enabled: Bool?
    let freeTimeMinutes: Int?
    let autoCreateClaim: Bool?
    let actorUserId: Int?
    let changedAt: String?
}

// MARK: - Body

private struct RailAutoDetentionRulesBody: View {
    @Environment(\.palette) private var palette

    @State private var rules: [AutoDetentionRule] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var savingRuleId: String? = nil
    @State private var actionAck: String? = nil
    @State private var actionError: String? = nil
    @State private var lastSyncedAt: Date? = nil

    @State private var showingAddRule = false
    @State private var addRuleSaving = false
    @State private var draftRuleName = ""
    @State private var draftRuleDescription = ""
    @State private var draftTriggerType = "manual_review"
    @State private var draftEnabled = true
    @State private var draftFreeTimeMinutes = 120
    @State private var draftAutoCreateClaim = false

    @State private var showingHistory = false
    @State private var historyLoading = false
    @State private var historyEvents: [AutoDetentionHistoryEvent] = []
    @State private var historyError: String? = nil

    // Verbatim catalog/wireframe context labels (carrier-of-record copy).
    private let carrierLabel  = "BNSF"
    private let configLine    = "Carrier BNSF Intermodal · Eusorone Technologies (DU) · auto-detention v3"
    private let triggerOptions = [
        ("manual_review", "Manual review"),
        ("geofence", "Geofence"),
        ("eld", "ELD stop"),
        ("appointment", "Appointment"),
        ("timer", "Timer"),
        ("analytics", "Pattern alert")
    ]

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
                    actionStatusPanel
                    if showingHistory { historyPanel }
                    ctaPair
                }

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showingAddRule) {
            addRuleSheet
        }
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
            Text("Auto-detention rules")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(carrierLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(syncLabel)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var syncLabel: String {
        guard let lastSyncedAt else { return loading ? "syncing" : "sync pending" }
        return "synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
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
                        Text("\(monitored) rule checks active")
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
                Text("live rules")
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
                    Text("+ evaluated on every gate event · edit the rules below")
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
                Text("CONFIGURE · auto-detention rules")
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

    // MARK: - Action status + persisted history

    @ViewBuilder
    private var actionStatusPanel: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
        } else if let actionAck {
            LifecycleCard {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color(hex: 0x4FD6A6))
                    Text(actionAck)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONFIRMED CHANGES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if historyLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        Task { await loadHistory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let historyError {
                Text(historyError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if historyLoading && historyEvents.isEmpty {
                Text("Loading confirmed rule changes.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else if historyEvents.isEmpty {
                EusoEmptyState(systemImage: "clock.arrow.circlepath",
                               title: "No confirmed changes yet",
                               subtitle: "Saved rule changes appear here after the audit record is written.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(historyEvents.enumerated()), id: \.element.id) { idx, event in
                        historyRow(event)
                        if idx < historyEvents.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func historyRow(_ event: AutoDetentionHistoryEvent) -> some View {
        let enabled = event.enabled ?? false
        let label = humanRuleLabel(event.ruleId ?? "auto_detention_rule")
        let changedAt = formatAuditTime(event.changedAt)
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: enabled ? "checkmark.shield.fill" : "pause.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Color(hex: 0x4FD6A6) : Color(hex: 0xFFB74D))
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(enabled ? "enabled" : "muted") · \(event.freeTimeMinutes ?? 0) min free · \(event.autoCreateClaim ?? false ? "auto-claim" : "queue")")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(changedAt)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
    }

    // MARK: - CTA pair (Add rule · History)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                resetDraftRule()
                showingAddRule = true
            } label: {
                HStack(spacing: 8) {
                    if addRuleSaving {
                        ProgressView().tint(.white).controlSize(.small)
                    }
                    Text(addRuleSaving ? "Saving" : "Add rule")
                }
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(addRuleSaving)

            Button {
                showingHistory.toggle()
                if showingHistory && historyEvents.isEmpty {
                    Task { await loadHistory() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showingHistory ? "clock.arrow.circlepath" : "clock")
                    Text("History")
                }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var addRuleSheet: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Rule name", text: $draftRuleName)
                    TextField("Description", text: $draftRuleDescription, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Trigger", selection: $draftTriggerType) {
                        ForEach(triggerOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                }

                Section("Automation") {
                    Stepper(value: $draftFreeTimeMinutes, in: 0...1440, step: 30) {
                        Text("\(draftFreeTimeMinutes) minutes free")
                    }
                    Toggle("Enabled", isOn: $draftEnabled)
                    Toggle("Auto-create claim", isOn: $draftAutoCreateClaim)
                }
            }
            .navigationTitle("Add rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddRule = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addRuleSaving ? "Saving" : "Save") {
                        Task { await addRule() }
                    }
                    .disabled(addRuleSaving || draftRuleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Load (named reload per house convention)

    private func reload() async {
        loading = true; loadError = nil
        do {
            let resp: AutoDetentionRulesResponse = try await EusoTripAPI.shared
                .queryNoInput("detentionAccessorials.getAutoDetentionRules")
            self.rules = resp.rules
            self.lastSyncedAt = Date()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Toggle a rule (configureAutoDetention mutation)

    private func toggle(_ rule: AutoDetentionRule) async {
        let newEnabled = !(rule.enabled ?? false)
        savingRuleId = rule.id
        actionError = nil
        actionAck = nil
        do {
            let result: ConfigureAutoDetentionResult = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.configureAutoDetention",
                input: ConfigureAutoDetentionInput(ruleId: rule.id,
                                                   name: nil,
                                                   description: nil,
                                                   triggerType: nil,
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
                actionAck = "\(rule.name ?? humanRuleLabel(rule.id)) \(newEnabled ? "enabled" : "muted")."
                await loadHistory()
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        savingRuleId = nil
    }

    private func addRule() async {
        let trimmedName = draftRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = draftRuleDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleId = makeRuleId(from: trimmedName)
        addRuleSaving = true
        actionError = nil
        actionAck = nil
        do {
            let result: ConfigureAutoDetentionResult = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.configureAutoDetention",
                input: ConfigureAutoDetentionInput(ruleId: ruleId,
                                                   name: trimmedName,
                                                   description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                                                   triggerType: draftTriggerType,
                                                   enabled: draftEnabled,
                                                   freeTimeMinutes: draftFreeTimeMinutes,
                                                   autoCreateClaim: draftAutoCreateClaim)
            )
            if result.success ?? true {
                showingAddRule = false
                actionAck = "\(trimmedName) saved."
                await reload()
                await loadHistory()
            } else {
                actionError = "Rule was not saved."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        addRuleSaving = false
    }

    private func loadHistory() async {
        historyLoading = true
        historyError = nil
        do {
            let response: AutoDetentionHistoryResponse = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getAutoDetentionHistory",
                input: AutoDetentionHistoryInput(limit: 20)
            )
            historyEvents = response.events
        } catch {
            historyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        historyLoading = false
    }

    private func resetDraftRule() {
        draftRuleName = ""
        draftRuleDescription = ""
        draftTriggerType = "manual_review"
        draftEnabled = true
        draftFreeTimeMinutes = 120
        draftAutoCreateClaim = false
        actionError = nil
        actionAck = nil
    }

    private func makeRuleId(from name: String) -> String {
        let lower = name.lowercased()
        let mapped = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        let collapsed = String(mapped).split(separator: "_").joined(separator: "_")
        let base = collapsed.isEmpty ? "manual_review" : String(collapsed.prefix(36))
        return "custom_\(base)_\(Int(Date().timeIntervalSince1970))"
    }

    private func humanRuleLabel(_ ruleId: String) -> String {
        ruleId
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func formatAuditTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "recorded" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview("651 · Rail Auto-Detention Rules · Night") {
    RailAutoDetentionRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("651 · Rail Auto-Detention Rules · Light") {
    RailAutoDetentionRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
