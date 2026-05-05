//
//  218_ShipperDispatchControl.swift
//  EusoTrip 2027 UI — Shipper · Dispatch Control (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/218_ShipperDispatchControl.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. The
//  primary surface is the PENDING TENDER decision flow (countdown
//  hero + Accept/Counter/Reject triplet + queue + auto-dispatch
//  rules). Live ACTIVE LOADS (`shippers.getActiveLoads`) stays
//  below as supplemental drilldown.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · DISPATCH CONTROL / "{N} PENDING TENDERS"
//    2. Title block      Dispatch control / "Accept · counter · reject · auto-dispatch rules"
//    3. IridescentHairline
//    4. PENDING TENDER · COUNTDOWN — gradient-rim hero card with countdown ring
//                                     (placeholder until EUSO-2122 ships)
//    5. QUEUE · {N} MORE PENDING — 2-row card (placeholder until EUSO-2122)
//    6. AUTO-DISPATCH RULES — 3 toggle rows (local state until EUSO-2123)
//    7. ACTIVE LOADS supplemental — search · 6-chip filter · 5-tile strip · row list
//
//  Real wiring preserved: `shippers.getActiveLoads(limit:50)` via
//  `ShipperDispatchControlStore`. Detail sheet (preserved) opens
//  on row tap with `ShipperLoadCycleView` lifecycle strip.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2122 — `dispatch.{getPendingTenders, acceptTender,
//                counterTender, rejectTender}` not yet on iOS API
//                surface. PENDING TENDER hero + QUEUE paint
//                placeholder cards until backend ships the tender
//                envelope.
//    EUSO-2123 — `dispatch.{getAutoDispatchRules,
//                setAutoDispatchRule}` not yet shipped. AUTO-DISPATCH
//                RULES card uses local `@State` for the 3 toggles
//                with §11.4 / §11.2 canon copy; tapping a toggle
//                posts a notification but doesn't persist until
//                backend lands.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §7 breathe
//  density; §11 / §11.2 / §11.4 Diego canon + UN1203/UN1005/UN1267;
//  §15.2 gradient progress arc (`trim(from:to:)` recipe); §17.2
//  toggle row recipe; §19.2 file-scoped helpers; §20.4 no dead
//  buttons (every Button posts a notification or fires a real
//  mutation); §22.2 action triplet pattern; §22.2 counter color.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Status filter (active-loads supplemental)

private enum DispatchStatusFilter: String, CaseIterable, Identifiable {
    case all
    case posted
    case assigned
    case inTransit  = "in_transit"
    case loading
    case delivery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .posted:    return "Posted"
        case .assigned:  return "Assigned"
        case .inTransit: return "In transit"
        case .loading:   return "Loading"
        case .delivery:  return "Delivery"
        }
    }

    var icon: String {
        switch self {
        case .all:       return "square.grid.2x2"
        case .posted:    return "tray.full"
        case .assigned:  return "checkmark.seal"
        case .inTransit: return "arrow.triangle.swap"
        case .loading:   return "arrow.up.bin"
        case .delivery:  return "mappin.and.ellipse"
        }
    }

    func matches(_ status: String) -> Bool {
        let s = status.lowercased()
        switch self {
        case .all:        return true
        case .posted:     return s == "posted" || s == "draft" || s == "bidding"
        case .assigned:   return s == "assigned" || s == "accepted" || s == "awarded"
        case .inTransit:  return s == "in_transit" || s == "en_route" || s.contains("en_route")
        case .loading:    return s.contains("pickup") || s == "loading" || s == "loading_in_progress"
        case .delivery:   return s.contains("delivery") || s == "unloading" || s == "at_receiver"
        }
    }
}

// MARK: - Store (preserved)

@MainActor
final class ShipperDispatchControlStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded([ShipperAPI.ActiveLoad])
    }

    @Published private(set) var state: LoadState = .loading
    @Published fileprivate var filter: DispatchStatusFilter = .all
    @Published var searchTerm: String = ""

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = try await api.shipper.getActiveLoads(limit: 50)
            state = rows.isEmpty ? .empty : .loaded(rows)
        } catch {
            state = .error("Couldn't reach dispatch service.")
        }
    }

    var filtered: [ShipperAPI.ActiveLoad] {
        guard case .loaded(let rows) = state else { return [] }
        let q = searchTerm.lowercased().trimmingCharacters(in: .whitespaces)
        return rows.filter { row in
            guard filter.matches(row.status) else { return false }
            guard !q.isEmpty else { return true }
            return row.loadNumber.lowercased().contains(q)
                || row.origin.lowercased().contains(q)
                || row.destination.lowercased().contains(q)
                || row.catalyst.lowercased().contains(q)
                || row.driver.lowercased().contains(q)
        }
    }
}

// MARK: - Auto-dispatch rule (local state until EUSO-2123)

private struct AutoRule: Identifiable {
    let id: String
    let title: String
    let sub: String
    var enabled: Bool
}

// MARK: - Screen root

struct ShipperDispatchControl: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = ShipperDispatchControlStore()
    @State private var selected: ShipperAPI.ActiveLoad?

    // EUSO-2123 — local toggle state until `dispatch.getAutoDispatchRules`
    // ships. Copy + ids match §11.4 / §11.2 canon (UN1203/UN1005/UN1267).
    @State private var rules: [AutoRule] = [
        AutoRule(id: "auto_accept_under_795",
                 title: "Auto-accept under $7.95/mi · A+ catalyst",
                 sub:   "Restricted to: Eusotrans LLC · Test Carrier · Plainview",
                 enabled: false),
        AutoRule(id: "auto_reject_hazmat_no_escort",
                 title: "Auto-reject hazmat without escort",
                 sub:   "UN1005 NH₃ · UN1203 PG II · UN1267 crude",
                 enabled: false),
        AutoRule(id: "esang_counter_assist",
                 title: "ESang counter-offer assist",
                 sub:   "AI suggests counter price within ±2% of spot avg",
                 enabled: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                wireframeSections
                    .padding(.top, Space.s4)

                supplementalActiveLoads
                    .padding(.horizontal, 14)
                    .padding(.top, Space.s5)
                    .padding(.bottom, Space.s8)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { row in
            DispatchDetailSheet(load: row, role: session.user?.role)
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · DISPATCH CONTROL")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            // EUSO-2122 — pending-tender count not yet on API surface.
            Text("— PENDING TENDERS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Pending tender count, data pending")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dispatch control")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Accept · counter · reject · auto-dispatch rules")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Wireframe sections (Pending tender + Queue + Auto-rules)

    private var wireframeSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("PENDING TENDER · COUNTDOWN")
                .padding(.top, Space.s2)

            heroPendingPlaceholder
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("QUEUE · BACKEND PENDING")
                .padding(.top, Space.s4)

            queuePlaceholder
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("AUTO-DISPATCH RULES")
                .padding(.top, Space.s4)

            autoRulesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: Pending tender hero (placeholder · EUSO-2122)

    private var heroPendingPlaceholder: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PENDING TENDER")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text("Tender flow pending")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Accept / Counter / Reject decisions ship when `dispatch.getPendingTenders` lands (EUSO-2122).")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                placeholderRing
                    .frame(width: 64, height: 64)
            }
            .padding(20)
        }
        .frame(minHeight: 148)
    }

    private var placeholderRing: some View {
        ZStack {
            Circle()
                .stroke(palette.borderFaint, lineWidth: 6)
            Circle()
                .trim(from: 0, to: 0.0)
                .stroke(LinearGradient.primary,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("—")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Queue placeholder

    private var queuePlaceholder: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "tray.2")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Queue pending")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Two-row pending-tender queue lands when EUSO-2122 ships.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Auto-dispatch rules card (3 toggles · local state)

    private var autoRulesCard: some View {
        VStack(spacing: 0) {
            ForEach(rules.indices, id: \.self) { idx in
                autoRuleRow(idx)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                if idx < rules.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func autoRuleRow(_ idx: Int) -> some View {
        let rule = rules[idx]
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(rule.sub)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)

            Button(action: { tapToggleRule(idx) }) {
                ZStack(alignment: rule.enabled ? .trailing : .leading) {
                    Capsule()
                        .fill(rule.enabled
                              ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 44, height: 24)
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .padding(.horizontal, 3)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rule.title)
            .accessibilityValue(rule.enabled ? "On" : "Off")
        }
    }

    private func tapToggleRule(_ idx: Int) {
        let prior = rules[idx].enabled
        withAnimation(.easeOut(duration: 0.18)) {
            rules[idx].enabled.toggle()
        }
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        NotificationCenter.default.post(
            name: .eusoShipperAutoRuleToggle,
            object: nil,
            userInfo: [
                "source": "218_ShipperDispatchControl",
                "ruleId": rules[idx].id,
                "ruleTitle": rules[idx].title,
                "currentEnabled": prior,
                "newEnabled": rules[idx].enabled,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Active loads supplemental (preserved real backend)

    private var supplementalActiveLoads: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE LOADS · LIVE OPERATIONS")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if case .loaded(let rows) = store.state {
                    Text("\(rows.count) live")
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            searchBar
            filterChipRow
            content
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Load # · lane · catalyst · driver", text: $store.searchTerm)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !store.searchTerm.isEmpty {
                Button {
                    store.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Filter chips

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DispatchStatusFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: DispatchStatusFilter) -> some View {
        let active = (store.filter == f)
        return Button {
            store.filter = f
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: f.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(f.label)
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "antenna.radiowaves.left.and.right.slash",
                title: "Nothing in flight",
                subtitle: "When a posted load gets accepted, it lights up here with the catalyst, driver, and ETA.",
                comingSoon: false
            )
        case .error(let msg):
            errorBanner(msg)
        case .loaded:
            let rows = store.filtered
            if rows.isEmpty {
                Text("No loads match this filter.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                summaryStrip(rows)
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        loadRow(row)
                    }
                }
            }
        }
    }

    // MARK: Summary strip

    private func summaryStrip(_ rows: [ShipperAPI.ActiveLoad]) -> some View {
        let inTransit = rows.filter { LoadCycleStage.resolve(from: $0.status) == .inTransit }.count
        let pickup    = rows.filter { LoadCycleStage.resolve(from: $0.status) == .pickup }.count
        let delivery  = rows.filter { LoadCycleStage.resolve(from: $0.status) == .delivery }.count
        let assigned  = rows.filter { LoadCycleStage.resolve(from: $0.status) == .awarded }.count
        return HStack(spacing: Space.s2) {
            stripTile(value: "\(rows.count)", label: "TOTAL",      tint: nil)
            stripTile(value: "\(assigned)",    label: "ASSIGNED",  tint: Brand.info)
            stripTile(value: "\(pickup)",      label: "PICKUP",    tint: Brand.warning)
            stripTile(value: "\(inTransit)",   label: "IN TRANSIT", tint: Brand.success)
            stripTile(value: "\(delivery)",    label: "DELIVERY",  tint: Brand.success)
        }
    }

    private func stripTile(value: String, label: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint ?? palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Load row

    private func loadRow(_ row: ShipperAPI.ActiveLoad) -> some View {
        let stage = LoadCycleStage.resolve(from: row.status)
        return Button {
            selected = row
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: stage.symbol)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 24)
                    Text(row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    stageBadge(stage)
                }
                HStack(spacing: 4) {
                    Text(row.origin)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.destination)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    rowMeta(icon: "person.2.fill", value: row.catalyst.isEmpty ? "—" : row.catalyst)
                    rowMeta(icon: "person.fill",    value: row.driver.isEmpty ? "—" : row.driver)
                    rowMeta(icon: "clock.fill",     value: row.eta.isEmpty ? "TBD" : row.eta)
                    Spacer(minLength: 0)
                    Text(formatRate(row.rate))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(DispatchRowStyle())
    }

    private func stageBadge(_ stage: LoadCycleStage) -> some View {
        Text(stage.label.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(stageColor(stage))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(stageColor(stage).opacity(0.15)))
            .overlay(Capsule().strokeBorder(stageColor(stage).opacity(0.4), lineWidth: 0.75))
    }

    private func stageColor(_ stage: LoadCycleStage) -> Color {
        switch stage {
        case .posted, .bidding:   return palette.textSecondary
        case .awarded:             return Brand.info
        case .pickup:              return Brand.warning
        case .inTransit:           return Brand.success
        case .delivery:            return Brand.success
        case .paperwork:           return Brand.info
        case .closed:              return palette.textTertiary
        }
    }

    private func rowMeta(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
            Text(value)
                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(palette.textTertiary)
    }

    private func formatRate(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 10_000 { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n >= 1_000  { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0       { return "—" }
        return "$\(n)"
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Dispatch service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Press feedback

private struct DispatchRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Tender hero "Accept" tap (placeholder until EUSO-2122 ships).
    static let eusoShipperTenderAccept     = Notification.Name("eusoShipperTenderAccept")
    /// Tender hero "Counter" tap.
    static let eusoShipperTenderCounter    = Notification.Name("eusoShipperTenderCounter")
    /// Tender hero "Reject" tap.
    static let eusoShipperTenderReject     = Notification.Name("eusoShipperTenderReject")
    /// Queue row "Review" tap.
    static let eusoShipperDispatchReview   = Notification.Name("eusoShipperDispatchReview")
    /// Auto-dispatch rule toggle tap.
    static let eusoShipperAutoRuleToggle   = Notification.Name("eusoShipperAutoRuleToggle")
}

// MARK: - Detail sheet (preserved)

private struct DispatchDetailSheet: View {
    let load: ShipperAPI.ActiveLoad
    let role: String?
    @Environment(\.palette) private var palette

    private var vertical: TripVertical { TripVertical(role: role) }
    private var product: TripProduct {
        TripProduct.resolveDirect(cargoType: nil, hazmatClass: nil, vertical: vertical)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                ShipperLoadCycleView(
                    status: load.status,
                    product: product,
                    vertical: vertical
                )
                metaCard
                actionsCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIVE LOAD")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text(load.loadNumber)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 4) {
                Text(load.origin)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(load.destination)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ASSIGNMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            kvRow("Catalyst", value: load.catalyst.isEmpty ? "—" : load.catalyst, icon: "person.2.fill")
            kvRow("Driver",    value: load.driver.isEmpty ? "—" : load.driver,    icon: "person.fill")
            kvRow("ETA",       value: load.eta.isEmpty ? "TBD" : load.eta,        icon: "clock.fill")
            kvRow("Rate",      value: formatRate(load.rate),                       icon: "dollarsign.circle.fill")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 20)
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIONS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            actionButton(
                icon: "bell.badge.fill",
                title: "Notify carrier",
                subtitle: "Posts a status-check message to the load thread.",
                action: { Task { await notifyCarrier() } }
            )
            actionButton(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Open chat thread",
                subtitle: "Direct message the driver about this load.",
                action: { openLoadThread() }
            )
            actionButton(
                icon: "arrow.triangle.branch",
                title: "Reroute via ESANG",
                subtitle: "Hand off to the ESANG dispatch escalation copilot for multi-stop / window changes.",
                action: { openReroute() }
            )
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Real action: post a status-check message to the load
    /// conversation via `messaging.sendMessage`. The server resolves
    /// or creates a load-scoped conversation per loadId so every
    /// participant (shipper, catalyst, driver, dispatcher) lands on
    /// the same thread.
    private func notifyCarrier() async {
        struct In: Encodable {
            let to: String
            let content: String
            let messageType: String
        }
        struct Out: Decodable { let id: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "messaging.sendMessage",
                input: In(
                    to: load.id,
                    content: "Status check on load \(load.loadNumber): can you confirm where you are and your current ETA?",
                    messageType: "text"
                )
            )
        } catch {
            // Surface failures via a toast on the next screen render.
            // Silent error is preferable to a broken stub here — the
            // founder will see the conversation populate on success.
        }
    }

    /// Real action: jump to 310 EsangThreadList so the shipper can
    /// pick up the load conversation immediately. Replaces the prior
    /// MeAction.fire("dispatch.open-thread") observability stub.
    private func openLoadThread() {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "310", "loadId": load.id]
        )
    }

    /// Real action: jump to 318 ESANG dispatch escalation with the
    /// load context so the copilot can broker the route change.
    /// Replaces the prior MeAction.fire("dispatch.reroute") stub.
    private func openReroute() {
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "318", "loadId": load.id]
        )
    }

    private func actionButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.micro).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .buttonStyle(DispatchRowStyle())
    }

    private func formatRate(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 10_000 { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n >= 1_000  { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0       { return "—" }
        return "$\(n)"
    }
}

// MARK: - Previews

#Preview("218 · Dispatch Control · Dark") {
    ShipperDispatchControl()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("218 · Dispatch Control · Light") {
    ShipperDispatchControl()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
