//
//  227_ShipperSettlementDetail.swift
//  EusoTrip 2027 UI — Shipper · Settlement Detail (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/227_ShipperSettlementDetail.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11. The
//  reference settlement anchors §11.4 row 3 (LD-260427-B41782FF02
//  · KC → Omaha · MC-331 NH₃ UN1005 · Heartland Cryogenics LLC).
//  The sister-port to 206 Settlements (list view).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · SETTLEMENT DETAIL / "{STATUS} · POD" gradient
//    2. Back chevron + breadcrumb "Settlements"
//    3. Title block      32pt gradient amount + sub line
//    4. IridescentHairline
//    5. Hero card        3pt left tier rim · load id + status pill ·
//                        lane title + lane sub · monogram avatar +
//                        carrier name + USDOT · gradient amount + sub
//    6. SETTLEMENT LIFECYCLE · STAGE {N} OF 5 — 5-stage strip
//                        (BOL RECEIVED · AUDIT · APPROVED · FUNDED · CLEARED)
//    7. BREAKDOWN section + line-haul / FSC / accessorial rows
//    8. Tri-color full-width breakdown bar with %
//    9. DOCUMENTS section + 3-chip strip (placeholder pending EUSO-2143)
//   10. ACTIVITY section + timeline (placeholder pending EUSO-2144)
//   11. Primary "Approve & fund" gradient CTA + secondary "File dispute"
//
//  Real wiring preserved: `earnings.getSettlementById` +
//  `earnings.approveSettlement` + `earnings.disputeSettlement` via
//  `ShipperSettlementDetailStore`. Open-on-web hand-off preserved.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2142 — `SettlementDetail` doesn't ship per-stage lifecycle
//                timestamps. The 5-stage strip computes the active
//                stage from `status` (pending → AUDIT, approved →
//                APPROVED, completed/paid → CLEARED, disputed →
//                AUDIT with warn paint). Per-stage timestamps paint
//                "—" pending the envelope extension.
//    EUSO-2143 — Settlement-attached documents (BOL · POD · rate-con)
//                not on the envelope. Documents strip paints honest
//                placeholder chips citing the backend gap.
//    EUSO-2144 — Activity timeline (POD signed · BOL uploaded · audit
//                pass) not on the envelope. Activity section paints
//                placeholder until backend ships
//                `earnings.getSettlementActivity(id)`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("$3,200 payable"); §4.3 single iridescent
//  hairline; §11 / §11.2 / §11.4 Diego canon + LD audit-trail; §13
//  carrier mix; §14.2 tri-color breakdown bar; §15.2 per-row tier
//  vocabulary; §17.2 gradient-rim hero card; §19.2 file-scoped
//  paint extensions; §20.4 no dead buttons; §22.2 textTertiary
//  informational counter.
//

import SwiftUI

// MARK: - Lifecycle stage helpers

private enum LifecycleStageState { case past, active, upcoming, warn }

private struct LifecycleStage {
    let label: String
    let timestamp: String
    let state: LifecycleStageState
}

private func deriveLifecycle(status: String?) -> [LifecycleStage] {
    let s = (status ?? "").lowercased()
    let activeIdx: Int = {
        switch s {
        case "pending":              return 1   // AUDIT
        case "approved":             return 2   // APPROVED
        case "funded":               return 3   // FUNDED
        case "completed", "paid":    return 4   // CLEARED
        case "disputed":             return 1   // hold at AUDIT
        default:                     return 0   // BOL RECEIVED
        }
    }()
    let labels = ["BOL RECEIVED", "AUDIT", "APPROVED", "FUNDED", "CLEARED"]
    var out: [LifecycleStage] = []
    for (i, label) in labels.enumerated() {
        let state: LifecycleStageState
        if i < activeIdx { state = .past }
        else if i == activeIdx {
            state = (s == "disputed") ? .warn : .active
        } else { state = .upcoming }
        out.append(LifecycleStage(label: label, timestamp: "—", state: state))
    }
    return out
}

// MARK: - Status helper

private struct SettlementStatusStyle {
    let label: String
    let color: Color
    let pillLegend: String

    static func from(_ raw: String?) -> SettlementStatusStyle {
        switch (raw ?? "").lowercased() {
        case "pending":    return .init(label: "Pending",   color: Brand.warning, pillLegend: "PAYABLE · POD")
        case "approved":   return .init(label: "Approved",  color: Brand.success, pillLegend: "APPROVED")
        case "completed",
             "paid":       return .init(label: "Paid",      color: Brand.success, pillLegend: "CLEARED")
        case "funded":     return .init(label: "Funded",    color: Brand.success, pillLegend: "FUNDED")
        case "disputed":   return .init(label: "Disputed",  color: Brand.danger,  pillLegend: "DISPUTED")
        case "voided":     return .init(label: "Voided",    color: Brand.danger,  pillLegend: "VOIDED")
        default:           return .init(label: (raw ?? "Unknown").capitalized, color: Brand.neutral, pillLegend: (raw ?? "PENDING").uppercased())
        }
    }
}

// MARK: - Store (preserved)

@MainActor
final class ShipperSettlementDetailStore: ObservableObject {
    enum Phase {
        case loading
        case loaded(ShipperSettlementsAPI.SettlementDetail)
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var working: Bool = false
    @Published var lastAction: String? = nil
    @Published var lastError: String? = nil

    let settlementId: String
    private let api: EusoTripAPI

    init(settlementId: String, api: EusoTripAPI = .shared) {
        self.settlementId = settlementId
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            let detail = try await api.shipperSettlements.getDetail(settlementId: settlementId)
            phase = .loaded(detail)
        } catch {
            phase = .error("Couldn't load settlement.")
        }
    }

    func approve() async {
        working = true
        defer { working = false }
        do {
            _ = try await api.shipperSettlements.approve(settlementId: settlementId)
            lastAction = "Settlement \(settlementId) approved."
            await load()
        } catch {
            lastError = "Couldn't approve."
        }
    }

    func dispute(reason: String) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.shipperSettlements.dispute(settlementId: settlementId, reason: reason, evidence: nil)
            lastAction = "Dispute filed for \(settlementId)."
            await load()
        } catch {
            lastError = "Couldn't file dispute."
        }
    }
}

// MARK: - Screen root

struct ShipperSettlementDetail: View {
    let settlementId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    // Sheet→push (NAV remediation 2026-05-30): the File-dispute form
    // renders in-stack via the surface's `\.rolePushDetail` layer
    // (slide-in + BespokeBackBar) instead of a slide-up sheet. The
    // rate-driver prompt stays modal (self-dismisses on submit).
    @Environment(\.rolePushDetail) private var pushDetail
    @StateObject private var store: ShipperSettlementDetailStore
    @State private var showDispute: Bool = false
    @State private var disputeReason: String = ""
    @State private var showAck: Bool = false
    /// Phase 18 closure: shipper rates the driver after the settlement
    /// clears. Sheet renders RatingPromptView in shipperRatesDriver
    /// direction; loadId resolves from store.phase.value.loadId now
    /// that the backend earnings.getSettlementById ships it scalar.
    @State private var showRateDriver: Bool = false

    init(settlementId: String = "0") {
        self.settlementId = settlementId
        _store = StateObject(wrappedValue: ShipperSettlementDetailStore(settlementId: settlementId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)

                backChevronRow
                    .padding(.top, Space.s2)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        // RealtimeService → settlement state mutates when payable
        // approves clear, disputes resolve, or dispute responses
        // arrive from the carrier-side claim review.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.load() }
        }
        .sheet(isPresented: $showRateDriver) {
            // Resolve everything the prompt needs from store.phase.
            // loadId now ships scalar on the SettlementDetail envelope
            // (see Phase 18 backend amendment in earnings.ts:269).
            let detail: ShipperSettlementsAPI.SettlementDetail? = {
                if case .loaded(let s) = store.phase { return s } else { return nil }
            }()
            RatingPromptView(
                direction: .shipperRatesDriver,
                counterpartyId: detail?.driverId ?? "0",
                counterpartyName: detail?.driverName,
                loadId: detail?.loadId.map(String.init) ?? "0",
                laneSummary: nil
            )
            .environment(\.palette, palette)
        }
        .onChange(of: store.lastAction ?? "") { _, v in if !v.isEmpty { showAck = true } }
        .alert("Done", isPresented: $showAck, actions: {
            Button("OK") { store.lastAction = nil }
        }, message: {
            if let a = store.lastAction { Text(a) }
        })
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · SETTLEMENT DETAIL")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(topBarStatus)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .accessibilityLabel("Settlement status pending")
        }
        .padding(.horizontal, Space.s3)
    }

    private var topBarStatus: String {
        if case .loaded(let s) = store.phase {
            return SettlementStatusStyle.from(s.status).pillLegend
        }
        return "—"
    }

    // MARK: Back chevron + breadcrumb

    private var backChevronRow: some View {
        HStack(spacing: 6) {
            Button(action: tapBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Settlements")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, Space.s3)
        .accessibilityLabel("Back to settlements")
    }

    private func tapBack() {
        dismiss()
        // observability post — telemetry only; real effect is `dismiss()` above
        NotificationCenter.default.post(
            name: .eusoShipperSettlementBack,
            object: nil,
            userInfo: [
                "source": "227_ShipperSettlementDetail",
                "settlementId": settlementId
            ]
        )
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
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
        case .loaded(let s):
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(s)
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                heroCard(s)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s3)

                let lifecycle = deriveLifecycle(status: s.status)
                let activeIdx = lifecycle.firstIndex(where: { $0.state == .active || $0.state == .warn }) ?? 0
                sectionLabel("SETTLEMENT LIFECYCLE · STAGE \(activeIdx + 1) OF 5")
                    .padding(.top, Space.s5)
                lifecycleStrip(lifecycle)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s4)

                if let b = s.breakdown,
                   ((b.lineHaul ?? 0) + (b.fuelSurcharge ?? 0) + (b.accessorials ?? 0)) > 0 {
                    sectionLabel("BREAKDOWN · LINE / FSC / ACC.")
                        .padding(.top, Space.s5)
                    breakdownCard(s, breakdown: b)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s2)
                    totalStrip(s, breakdown: b)
                        .padding(.horizontal, Space.s3)
                        .padding(.top, Space.s3)
                }

                sectionLabel("DOCUMENTS · BACKEND PENDING")
                    .padding(.top, Space.s5)
                documentsStrip
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)

                sectionLabel("ACTIVITY · BACKEND PENDING")
                    .padding(.top, Space.s5)
                activityPlaceholder
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s2)

                actions(s)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s5)
            }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
    }

    // MARK: Title block — gradient amount

    private func titleBlock(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let amount = money(s.netPay ?? s.grossPay ?? 0)
        let label = (s.status ?? "").lowercased() == "pending" ? "payable" : SettlementStatusStyle.from(s.status).label.lowercased()
        let driver = (s.driverName?.isEmpty == false) ? s.driverName! : "carrier"
        let sub = "Eusorone Technologies → \(driver) · \(s.settlementNumber ?? "#\(s.id)")"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(amount)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .tracking(-0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text(sub)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
    }

    // MARK: Hero card — 3pt tier rim · load id + status · lane · carrier · gradient amount

    private func heroCard(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let style = SettlementStatusStyle.from(s.status)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.borderFaint, lineWidth: 1)
                )
            // 3pt left tier rim
            Capsule()
                .fill(rimPaint(for: s.status))
                .frame(width: 3, height: 124)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.settlementNumber ?? "#\(s.id)")
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                    Spacer()
                    Text(style.pillLegend)
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                .padding(.top, 14)

                Text(laneTitle(s))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .padding(.top, 8)

                Text(laneSub(s))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)

                HStack(alignment: .center, spacing: 8) {
                    monogramAvatar(s)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(carrierName(s))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(carrierUSDOT(s))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(money(s.netPay ?? s.grossPay ?? 0))
                            .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(amountSubLine(s))
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, Space.s4)
            .padding(.leading, 8) // rim breathing room
        }
        .frame(minHeight: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Settlement \(s.settlementNumber ?? "#\(s.id)"), \(style.label), \(laneTitle(s)), \(carrierName(s)), \(money(s.netPay ?? s.grossPay ?? 0))"
        )
    }

    private func rimPaint(for status: String?) -> AnyShapeStyle {
        switch (status ?? "").lowercased() {
        case "completed", "paid", "funded": return AnyShapeStyle(Brand.success)
        case "disputed":                    return AnyShapeStyle(Brand.danger)
        case "approved":                    return AnyShapeStyle(LinearGradient.diagonal)
        case "pending":                     return AnyShapeStyle(LinearGradient.diagonal)
        default:                            return AnyShapeStyle(palette.textTertiary)
        }
    }

    private func laneTitle(_ s: ShipperSettlementsAPI.SettlementDetail) -> String {
        // EUSO — settlement detail doesn't ship lane fields; surface
        // the period or settlement number as the line.
        if let period = s.period, !period.isEmpty {
            return "Period \(period)"
        }
        return s.settlementNumber ?? "#\(s.id)"
    }

    private func laneSub(_ s: ShipperSettlementsAPI.SettlementDetail) -> String {
        var parts: [String] = []
        if let pStart = s.periodStart {
            parts.append(String(pStart.prefix(10)))
        }
        if let pEnd = s.periodEnd {
            parts.append(String(pEnd.prefix(10)))
        }
        if let pm = s.paymentMethod, !pm.isEmpty {
            parts.append(pm)
        }
        return parts.isEmpty ? "Settlement detail" : parts.joined(separator: " · ")
    }

    private func carrierName(_ s: ShipperSettlementsAPI.SettlementDetail) -> String {
        s.driverName ?? "Carrier pending"
    }

    private func carrierUSDOT(_ s: ShipperSettlementsAPI.SettlementDetail) -> String {
        // EUSO — USDOT not on settlement envelope; show driver id as a
        // proxy when present.
        if let id = s.driverId { return "DRIVER #\(id)" }
        return "USDOT pending"
    }

    private func amountSubLine(_ s: ShipperSettlementsAPI.SettlementDetail) -> String {
        if let pm = s.paymentMethod, !pm.isEmpty { return pm.uppercased() }
        return s.netPay != nil ? "NET" : "GROSS"
    }

    private func monogramAvatar(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let name = s.driverName ?? "?"
        let initials = name.split(separator: " ")
            .compactMap { $0.first.map(String.init) }
            .prefix(2).joined().uppercased()
        return ZStack {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    // MARK: Lifecycle strip (5 stages)

    private func lifecycleStrip(_ stages: [LifecycleStage]) -> some View {
        GeometryReader { geo in
            let total = geo.size.width
            let count = stages.count
            let stride = total / CGFloat(count - 1)
            let activeIdx = stages.firstIndex(where: { $0.state == .active || $0.state == .warn }) ?? 0

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: total, height: 2)
                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: stride * CGFloat(activeIdx), height: 2)
                ForEach(0..<count, id: \.self) { i in
                    let stage = stages[i]
                    let isActive = stage.state == .active || stage.state == .warn
                    let isCompleted = stage.state == .past
                    Circle()
                        .fill(isCompleted || isActive
                              ? AnyShapeStyle(stage.state == .warn ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(width: isActive ? 9 : 7, height: isActive ? 9 : 7)
                        .offset(x: stride * CGFloat(i) - (isActive ? 4.5 : 3.5))
                }
                ForEach(0..<count, id: \.self) { i in
                    let stage = stages[i]
                    let isActive = stage.state == .active || stage.state == .warn
                    let isCompleted = stage.state == .past
                    Text(stage.label)
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(LinearGradient.primary)
                                : (isCompleted
                                    ? AnyShapeStyle(palette.textSecondary)
                                    : AnyShapeStyle(palette.textTertiary))
                        )
                        .offset(x: anchoredOffset(for: i, count: count, stride: stride, label: stage.label),
                                y: -10)
                }
            }
        }
        .frame(height: 18)
    }

    private func anchoredOffset(for i: Int, count: Int, stride: CGFloat, label: String) -> CGFloat {
        let approxWidth: CGFloat = CGFloat(label.count) * 4.0
        let baseX = stride * CGFloat(i)
        if i == 0 { return baseX }
        if i == count - 1 { return baseX - approxWidth }
        return baseX - approxWidth / 2
    }

    // MARK: Breakdown card + total strip

    private func breakdownCard(_ s: ShipperSettlementsAPI.SettlementDetail,
                               breakdown b: ShipperSettlementsAPI.SettlementDetail.Breakdown) -> some View {
        let lh = b.lineHaul ?? 0
        let fs = b.fuelSurcharge ?? 0
        let ac = b.accessorials ?? 0
        let total = max(lh + fs + ac, 0.0001)
        return VStack(alignment: .leading, spacing: 8) {
            breakdownRow(label: "Line-haul",       sub: nil, amount: money(lh), share: lh / total, paint: AnyShapeStyle(LinearGradient.diagonal))
            breakdownRow(label: "Fuel surcharge",  sub: nil, amount: money(fs), share: fs / total, paint: AnyShapeStyle(Brand.warning))
            breakdownRow(label: "Accessorial",     sub: nil, amount: money(ac), share: ac / total, paint: AnyShapeStyle(Brand.success))
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

    private func breakdownRow(label: String, sub: String?, amount: String, share: Double, paint: AnyShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Circle().fill(paint).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let sub {
                    Text(sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(amount)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(String(format: "%.1f%%", share * 100))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func totalStrip(_ s: ShipperSettlementsAPI.SettlementDetail,
                            breakdown b: ShipperSettlementsAPI.SettlementDetail.Breakdown) -> some View {
        let lh = b.lineHaul ?? 0
        let fs = b.fuelSurcharge ?? 0
        let ac = b.accessorials ?? 0
        let total = max(lh + fs + ac, 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * (lh / total))
                    Rectangle().fill(Brand.warning)
                        .frame(width: geo.size.width * (fs / total))
                    Rectangle().fill(Brand.success)
                        .frame(width: geo.size.width * (ac / total))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack {
                Text("Total gross")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(money(lh + fs + ac))
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    // MARK: Documents strip (placeholder · EUSO-2143)

    private var documentsStrip: some View {
        HStack(spacing: 8) {
            ForEach(["BOL", "POD", "RC"], id: \.self) { kind in
                docChip(kind)
            }
            Spacer(minLength: 0)
        }
    }

    private func docChip(_ kind: String) -> some View {
        Button(action: { tapDocChip(kind) }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Text("Pending")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind) document, backend pending")
    }

    private func tapDocChip(_ kind: String) {
        // Real downstream: web continuation to the per-settlement document
        // surface (POD / rate-conf / invoice / lumper / detention / receipt).
        // Same Bearer cookie auth, no re-login. Telemetry post retained for
        // observability.
        NotificationCenter.default.post(
            name: .eusoShipperSettlementDoc,
            object: nil,
            userInfo: [
                "source": "227_ShipperSettlementDetail",
                "settlementId": settlementId,
                "documentKind": kind
            ]
        )
        let encoded = kind.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? kind
        if let url = URL(string: "https://app.eusotrip.com/shipper/settlements/\(settlementId)/documents/\(encoded)") {
            openURL(url)
        }
    }

    // MARK: Activity placeholder (EUSO-2144)

    private var activityPlaceholder: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Activity timeline pending")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("`earnings.getSettlementActivity` lands when the audit-trail endpoint ships (EUSO-2144).")
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

    // MARK: Actions

    private func actions(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let canApprove = (s.status ?? "").lowercased() == "pending"
        let canDispute = ["pending", "approved"].contains((s.status ?? "").lowercased())
        let amount = money(s.netPay ?? s.grossPay ?? 0)
        let pm = s.paymentMethod?.isEmpty == false ? s.paymentMethod! : "net-7"
        return VStack(spacing: 8) {
            if canApprove {
                Button {
                    Task {
                        await store.approve()
                        // observability post — telemetry only; real effect is `store.approve()` mutation above
                        NotificationCenter.default.post(
                            name: .eusoShipperSettlementApprove,
                            object: nil,
                            userInfo: [
                                "source": "227_ShipperSettlementDetail",
                                "settlementId": s.id,
                                "amount": s.netPay ?? s.grossPay ?? 0
                            ]
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.working {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .heavy))
                        }
                        Text(store.working ? "Working…" : "Approve & fund · \(amount) \(pm)")
                            .font(.system(size: 14, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.primary).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.working)
            }
            if canDispute {
                Button {
                    openDispute()
                    // observability post — telemetry only; real effect is the dispute push above
                    NotificationCenter.default.post(
                        name: .eusoShipperSettlementDispute,
                        object: nil,
                        userInfo: [
                            "source": "227_ShipperSettlementDetail",
                            "settlementId": s.id
                        ]
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 12, weight: .heavy))
                        Text("File dispute").font(.system(size: 12, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(Brand.danger).background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.6)))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            // Phase 18 closure: shipper rates the driver after the
            // settlement clears. Renders only when payment is in a
            // paid / completed state — rating before the funds clear
            // would skew the 'payment promptness' axis incorrectly.
            if ["paid", "completed"].contains((s.status ?? "").lowercased()) {
                Button {
                    showRateDriver = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Rate this driver").font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5)))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            if let e = store.lastError {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: Dispute form (sheet→push)

    /// Sheet→push: render the File-dispute form in-stack via the surface
    /// `\.rolePushDetail` layer (BespokeBackBar provided by the layer).
    /// `showDispute` is retained so the inline `disputeSheet` body's
    /// existing logic is untouched. Re-provides `\.palette`.
    private func openDispute() {
        showDispute = true
        let p = palette
        pushDetail?("File dispute") {
            AnyView(disputeSheet.environment(\.palette, p))
        }
    }

    private var disputeSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("FILE DISPUTE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Why is this settlement wrong?")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Your dispute is sent to the Catalyst + Eusorone audit log. Both parties can attach evidence on the web review screen.")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                ZStack(alignment: .topLeading) {
                    if disputeReason.isEmpty {
                        Text("Detention overage · accessorial missing · weight discrepancy …")
                            .font(EType.body).foregroundStyle(palette.textTertiary)
                            .padding(Space.s3)
                    }
                    TextEditor(text: $disputeReason)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s2)
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                Button {
                    Task {
                        await store.dispute(reason: disputeReason)
                        // Sheet→push: pop the in-stack detail layer instead
                        // of dismissing a sheet. The Shipper surface listens
                        // to `.eusoShipperNavBack` to clear the pushed detail
                        // (detail-first pop).
                        NotificationCenter.default.post(name: .eusoShipperNavBack, object: nil)
                        showDispute = false
                        disputeReason = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .heavy))
                        Text("Submit dispute").font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(disputeReason.trimmingCharacters(in: .whitespaces).count < 5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    // MARK: Error

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Back chevron tap.
    static let eusoShipperSettlementBack    = Notification.Name("eusoShipperSettlementBack")
    /// Approve & fund CTA tap.
    static let eusoShipperSettlementApprove = Notification.Name("eusoShipperSettlementApprove")
    /// File dispute CTA tap.
    static let eusoShipperSettlementDispute = Notification.Name("eusoShipperSettlementDispute")
    /// Document chip tap (BOL/POD/RC).
    static let eusoShipperSettlementDoc     = Notification.Name("eusoShipperSettlementDoc")
}

// MARK: - Previews

#Preview("227 · Settlement Detail · Dark") {
    ShipperSettlementDetail(settlementId: "1")
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("227 · Settlement Detail · Light") {
    ShipperSettlementDetail(settlementId: "1")
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
