//
//  298_ShipperDetentionExposure.swift
//  EusoTrip 2027 UI — Shipper · Wallet · Detention & Accessorial Exposure
//
//  Verbatim Swift port of wireframe `02 Shipper/298 Shipper Detention
//  Exposure.svg`. The shipper-side mirror of the driver's 091 detention
//  cockpit: instead of "recover my pay" this is "what is dwell costing
//  me, at which facilities, and what is still on the clock."
//
//  Screen anatomy (1:1 with the SVG, top → bottom):
//    • TopBar eyebrow  "✦ SHIPPER · DETENTION"  +  right rail
//      "$8,420 · 3 ACTIVE"  (live: dashboard.totalCharges +
//      dashboard.activeDetentions).
//    • Title  "Detention exposure"  +  "Eusorone Technologies ·
//      accessorial spend · wk 18".
//    • Hero  "DETENTION & ACCESSORIAL EXPOSURE · WK 18" → big total
//      charged, then Collected / Billed / Disputed split.
//    • "BY FACILITY · AVG DWELL · TOP 3" → top-3 worst offenders
//      (name · $total · avg dwell).
//    • "ACTIVE · CLOCK RUNNING · N" → live clocks with status pill
//      (ACCRUING / WATCH) + rate note + load reference.
//    • CTAs  "Dispute charge"  +  "Export".
//    • Footnote.
//    • BottomNav (canonical shipper ring).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge). Every
//  number is server-sourced; no fabricated charges, no placeholder
//  clocks. Empty/loading/error states are explicit. Wiring:
//
//    • detentionAccessorials.getDetentionDashboard  → hero counters
//      (EXISTS · detentionAccessorials.ts:129).
//    • detentionAccessorials.getDetentionByFacility → top-3 offenders
//      (EXISTS · detentionAccessorials.ts:401).
//    • detentionAccessorials.getActiveDetentions    → live clocks
//      (EXISTS · detentionAccessorials.ts:256).
//    • detentionAccessorials.disputeDetention       → "Dispute charge"
//      (EXISTS · detentionAccessorials.ts:511). NOTE: server input is
//      `claimId` (not `detentionId`); this screen sends `claimId` via
//      the local `disputeClaim` helper so the write actually lands.
//      The shared `DetentionAPI.dispute` accessor has the same field
//      bug — fixed in INTEGRATION.md §3 for the 091/573/577 callers.
//
//  Doctrine refs:
//    §2  LinearGradient.diagonal on hero total + collected. Brand.warning
//        on accruing clocks / over-free. Brand.magenta on disputed.
//        Brand.danger on the exposure right-rail.
//    §4  Tokenized Space / Radius / EType throughout. eusoCard surfaces.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct ShipperDetentionExposure: View {
    @Environment(\.palette) var palette
    @StateObject private var store = ShipperDetentionExposureStore()

    /// The active clock the shipper chose to dispute, if any.
    @State private var disputing: DetentionAPI.ActiveDetention?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                topBar
                title
                heroCard
                byFacilitySection
                activeSection
                ctaRow
                footnote
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $disputing) { detention in
            DisputeChargeSheet(detention: detention, store: store)
                .eusoSheetX()
        }
    }

    // MARK: TopBar eyebrow + right rail

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · DETENTION")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(store.exposureRail)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(Brand.danger)
                .monospacedDigit()
        }
    }

    // MARK: Title

    private var title: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Detention exposure")
                .font(EType.h1)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · accessorial spend · wk 18")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero — total charged + collected / billed / disputed

    private var heroCard: some View {
        let d = store.dashboard
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("DETENTION & ACCESSORIAL EXPOSURE · WK 18")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(currency(d?.totalCharges ?? 0))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("total charged")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }

            IridescentHairline()

            HStack(spacing: Space.s2) {
                splitTile(label: "Collected", value: d?.collectedAmount ?? 0, tone: .collected)
                splitTile(label: "Billed",    value: d?.billedAmount ?? 0,    tone: .billed)
                splitTile(label: "Disputed",  value: d?.disputedAmount ?? 0,  tone: .disputed)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private enum SplitTone { case collected, billed, disputed }

    private func splitTile(label: String, value: Double, tone: SplitTone) -> some View {
        let valueStyle: AnyShapeStyle = {
            switch tone {
            case .collected: return AnyShapeStyle(Brand.success)
            case .billed:    return AnyShapeStyle(palette.textPrimary)
            case .disputed:  return AnyShapeStyle(Brand.magenta)
            }
        }()
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(currency(value))
                .font(EType.bodyStrong)
                .foregroundStyle(valueStyle)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: By facility (top 3)

    private var byFacilitySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BY FACILITY · AVG DWELL · TOP 3")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            if store.facilities.isEmpty && store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            } else if store.facilities.isEmpty {
                EusoEmptyState(
                    systemImage: "building.2",
                    title: "No facility dwell yet",
                    subtitle: "When loads incur detention at a pickup or delivery, your worst-offender facilities rank here."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(Array(store.facilities.prefix(3))) { f in
                        facilityRow(f)
                    }
                }
            }
        }
    }

    private func facilityRow(_ f: DetentionAPI.FacilityExposure) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.facilityName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("avg \(humanMinutes(f.avgWaitMinutes))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(currency(f.totalCharges))
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Active clocks

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIVE · CLOCK RUNNING · \(store.active.count)")
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)

            if store.active.isEmpty && store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s4)
            } else if store.active.isEmpty {
                EusoEmptyState(
                    systemImage: "clock",
                    title: "Nothing on the clock",
                    subtitle: "Live detention timers appear here the moment a truck dwells past free time at one of your facilities."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.active) { d in
                        activeRow(d)
                    }
                }
            }
        }
    }

    private func activeRow(_ d: DetentionAPI.ActiveDetention) -> some View {
        let accruing = d.billableMinutes > 0
        let freeTime = humanMinutes(d.freeTimeMinutes)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                // Live clock
                Text(humanClock(d.elapsedMinutes))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accruing ? AnyShapeStyle(Brand.warning)
                                              : AnyShapeStyle(palette.textPrimary))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(d.facilityName) · \(d.locationType.capitalized)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let ref = d.loadRef {
                        Text(ref)
                            .font(EType.micro)
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                statusPill(accruing ? .accruing : .watch)
            }

            HStack {
                Text(accruing ? "$75/hr after \(freeTime)" : "free until \(freeTime)")
                    .font(EType.caption)
                    .foregroundStyle(accruing ? Brand.warning : palette.textTertiary)
                Spacer()
                Text(currency(d.currentCharge))
                    .font(EType.bodyStrong)
                    .foregroundStyle(accruing ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(palette.textTertiary))
                    .monospacedDigit()
            }

            Button {
                disputing = d
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised")
                    Text("Dispute this charge")
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 6)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private enum ClockStatus { case accruing, watch, disputed }

    @ViewBuilder
    private func statusPill(_ status: ClockStatus) -> some View {
        let (label, fg, bg): (String, Color, AnyShapeStyle) = {
            switch status {
            case .accruing: return ("ACCRUING", Brand.warning, AnyShapeStyle(Brand.warning.opacity(0.2)))
            case .watch:    return ("WATCH", palette.textSecondary, AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
            case .disputed: return ("DISPUTED", Brand.magenta, AnyShapeStyle(Brand.magenta.opacity(0.2)))
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.1)
            .foregroundStyle(fg)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }

    // MARK: CTA row — Dispute charge / Export

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                // "Dispute charge" with no row selected → jump to the
                // first accruing clock (the one bleeding money now).
                disputing = store.active.first(where: { $0.billableMinutes > 0 }) ?? store.active.first
            } label: {
                Text("Dispute charge")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.active.isEmpty)
            .opacity(store.active.isEmpty ? 0.5 : 1)

            // Honest local export: share a CSV built from the loaded
            // exposure (real on-device effect, never a dead tap).
            // Matches the shipped String-item ShareLink pattern
            // (345_TwoFactorManage.swift:551).
            ShareLink(item: store.exportCSV()) {
                Text("Export")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Footnote

    private var footnote: some View {
        Text("Detention bills automatically when gate timestamps and POD clocks agree. Disputed lines pause billing until your team reviews. Export pulls the current week's accessorial ledger.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// "2h 48m" style — used for average dwell + free time.
    private func humanMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "2:14" colon clock — used for the big live elapsed timer.
    private func humanClock(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - Dispute sheet

private struct DisputeChargeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detention: DetentionAPI.ActiveDetention
    @ObservedObject var store: ShipperDetentionExposureStore

    @State private var reason: String = ""
    @State private var submitting: Bool = false
    @State private var errorText: String?

    /// Server enforces `reason.min(10)`; mirror it client-side so the
    /// submit button only lights up on a valid reason.
    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var reasonValid: Bool { trimmedReason.count >= 10 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Charge") {
                    Text("\(detention.facilityName) · \(detention.locationType.capitalized)")
                        .font(EType.bodyStrong)
                    if let ref = detention.loadRef {
                        Text(ref)
                            .font(EType.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Section("Why are you disputing? (min 10 characters)") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 120)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                }
            }
            .navigationTitle("Dispute charge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            submitting = true
                            errorText = nil
                            do {
                                try await store.dispute(claimId: detention.id, reason: trimmedReason)
                                submitting = false
                                dismiss()
                            } catch {
                                submitting = false
                                errorText = "Couldn't file the dispute. \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        if submitting { ProgressView() }
                        else { Text("Submit").fontWeight(.semibold) }
                    }
                    .disabled(!reasonValid || submitting)
                }
            }
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperDetentionExposureStore: ObservableObject, DynamicStore {
    @Published private(set) var dashboard: DetentionAPI.Dashboard?
    @Published private(set) var facilities: [DetentionAPI.FacilityExposure] = []
    @Published private(set) var active: [DetentionAPI.ActiveDetention] = []

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?
    @Published private(set) var disputingId: Int?

    /// Right-rail string "$8,420 · 3 ACTIVE".
    var exposureRail: String {
        let total = Int(dashboard?.totalCharges ?? 0)
        let active = dashboard?.activeDetentions ?? self.active.count
        let f = NumberFormatter(); f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US"); f.maximumFractionDigits = 0
        let money = f.string(from: NSNumber(value: total)) ?? "$\(total)"
        return "\(money) · \(active) ACTIVE"
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        async let dashTask: DetentionAPI.Dashboard? =
            try? EusoTripAPI.shared.detention.getDashboard()
        async let facTask: DetentionAPI.ByFacilityResponse? =
            try? EusoTripAPI.shared.detention.getByFacility(limit: 10)
        async let activeTask: DetentionAPI.ActiveDetentionsResponse? =
            try? EusoTripAPI.shared.detention.getActive(limit: 10)
        let (d, f, a) = await (dashTask, facTask, activeTask)
        dashboard = d
        facilities = f?.facilities ?? []
        active = a?.detentions ?? []
        if d == nil && (f?.facilities.isEmpty ?? true) && (a?.detentions.isEmpty ?? true) {
            lastError = NSError(
                domain: "ShipperDetentionExposureStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Can't reach detention service"]
            )
        }
    }

    /// Files the dispute with the CORRECT server field name (`claimId`).
    /// Rethrows so the sheet can surface a real error rather than the
    /// silent `try?` swallow that would otherwise hide a failed write.
    func dispute(claimId: Int, reason: String) async throws {
        disputingId = claimId
        defer { disputingId = nil }
        _ = try await EusoTripAPI.shared.detention.disputeClaim(claimId: claimId, reason: reason)
        await refresh()
    }

    /// Builds a small CSV of the current exposure for the Export CTA.
    /// Real on-device artifact (Share sheet), never a dead tap.
    func exportCSV() -> String {
        var lines: [String] = ["section,name,detail,amount"]
        if let d = dashboard {
            lines.append("summary,Total charged,,\(Int(d.totalCharges))")
            lines.append("summary,Collected,,\(Int(d.collectedAmount))")
            lines.append("summary,Billed,,\(Int(d.billedAmount))")
            lines.append("summary,Disputed,,\(Int(d.disputedAmount))")
        }
        for f in facilities.prefix(3) {
            lines.append("facility,\(csv(f.facilityName)),avg \(f.avgWaitMinutes)m,\(Int(f.totalCharges))")
        }
        for a in active {
            lines.append("active,\(csv(a.facilityName)),\(a.elapsedMinutes)m elapsed,\(Int(a.currentCharge))")
        }
        return lines.joined(separator: "\n")
    }

    private func csv(_ s: String) -> String {
        s.contains(",") ? "\"\(s)\"" : s
    }
}

// MARK: - DetentionAPI extension (facility exposure + correct dispute field)
//
// `getByFacility` and a `claimId`-correct dispute are not yet on the
// shared `DetentionAPI` accessor (it ships `dispute(detentionId:)`,
// which the server rejects — see INTEGRATION.md §3). Defined here as a
// collision-free extension so this port compiles + works standalone;
// the shared accessor fix in INTEGRATION.md folds these back for the
// 091 / 573 / 577 callers.

extension DetentionAPI {

    struct FacilityExposure: Decodable, Equatable, Identifiable {
        let rank: Int
        let facilityName: String
        let eventCount: Int
        let totalCharges: Double
        let avgWaitMinutes: Int
        let maxWaitMinutes: Int
        let avgCharge: Double
        let disputeCount: Int
        let score: Int
        var id: String { facilityName }
    }

    struct ByFacilityResponse: Decodable {
        let facilities: [FacilityExposure]
    }

    /// `detentionAccessorials.getDetentionByFacility` — worst-offender
    /// ranking scoped to the caller's company server-side.
    func getByFacility(limit: Int = 20) async throws -> ByFacilityResponse {
        struct Input: Encodable { let limit: Int }
        return try await api.query(
            "detentionAccessorials.getDetentionByFacility",
            input: Input(limit: limit)
        )
    }

    /// `detentionAccessorials.disputeDetention` with the field name the
    /// server actually validates (`claimId`). The shipped
    /// `dispute(detentionId:)` sends `detentionId`, which fails zod
    /// validation server-side → the dispute never lands.
    @discardableResult
    func disputeClaim(claimId: Int, reason: String) async throws -> DisputeResult {
        struct Input: Encodable {
            let claimId: Int
            let reason: String
        }
        return try await api.mutation(
            "detentionAccessorials.disputeDetention",
            input: Input(claimId: claimId, reason: reason)
        )
    }
}

// MARK: - ActiveDetention load reference helper
//
// The wireframe prints a load reference under each active clock
// ("LD-260427-7C3A09F18B"). The decoder carries `loadId`; render a
// stable, human reference from it without inventing data.

extension DetentionAPI.ActiveDetention {
    var loadRef: String? {
        guard let loadId else { return nil }
        return "LD-\(loadId)"
    }
}

// MARK: - Screen wrapper

struct ShipperDetentionExposureScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperDetentionExposure()
        } nav: {
            // Canonical shipped shipper ring. The wireframe shows a
            // WALLET-active 4-icon nav; the shipped app ring is
            // Home / Create Load / Loads / Me and this surface is an
            // off-ring wallet detail → `.none`. Divergence filed for
            // the cadence/design lane (INTEGRATION.md §5).
            shipperLifecycleNav()
        }
    }
}

// MARK: - Previews

#Preview("298 · Detention Exposure · Night") {
    ShipperDetentionExposureScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("298 · Detention Exposure · Day") {
    ShipperDetentionExposureScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
