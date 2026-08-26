//
//  662_RailDemurrageChargeApproval.swift
//  EusoTrip - Rail - Demurrage review.
//
//  Production contract:
//    railDemurrageAuto.dashboard() -> { summary, perCarRunway, ... }
//    railDemurrageAuto.getDisputeDocket() -> tenant-scoped open disputes
//    railDemurrageAuto.resolveDispute({ disputeId, decision, requestKey, ... })
//

import SwiftUI

private struct DemurrageSummary662: Decodable {
    let activeAccruals: Int
    let totalChargesAccruing: Double
    let disputesOpen: Int
    let waiversPending: Int
}

private struct RunwayCar662: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String
    let freeTimeHours: Double
    let chargeableHours: Double
    let ratePerHour: Double
    let usdToday: Double
    let usdProjected: Double

    private enum CodingKeys: String, CodingKey {
        case id = "demurrageId"
        case railcarNumber, freeTimeHours, chargeableHours, ratePerHour
        case usdToday, usdProjected
    }
}

private struct DemurrageDashboard662: Decodable {
    let summary: DemurrageSummary662
    let perCarRunway: [RunwayCar662]
}

private struct EmptyInput662: Encodable {}

private struct DemurrageDispute662: Decodable, Identifiable {
    let id: Int
    let demurrageId: Int
    let status: String
    let reason: String
    let notes: String?
    let requestedWaiverAmount: Double?
    let submittedBy: Int?
    let createdAt: String
    let shipmentId: Int
    let shipmentNumber: String?
    let railcarNumber: String?
    let totalCharge: Double
    let chargeableHours: Double
    let ratePerHour: Double
}

private struct DemurrageDocket662: Decodable {
    let disputes: [DemurrageDispute662]
    let total: Int
}

private struct ResolveDisputeInput662: Encodable {
    let confirm: Bool
    let disputeId: Int
    let decision: String
    let resolutionNotes: String?
    let requestKey: String
}

private struct ResolveDisputeResult662: Decodable {
    let success: Bool
    let disputeId: Int
    let demurrageId: Int
    let decision: String
    let chargeStatus: String
    let alreadyResolved: Bool
}

struct RailDemurrageChargeApproval_662: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailDemurrageReviewBody662()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

private struct RailDemurrageReviewBody662: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reachability = OfflineReachabilityHub.shared

    @State private var dashboard: DemurrageDashboard662?
    @State private var docket: [DemurrageDispute662] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var clock = Date()
    @State private var selectedDispute: DemurrageDispute662?
    @State private var actionMessage: String?
    @State private var actionError: String?

    private var summary: DemurrageSummary662? { dashboard?.summary }
    private var runway: [RunwayCar662] { dashboard?.perCarRunway ?? [] }
    private var openDisputes: Int { docket.count }
    private var activeAccruals: Int { summary?.activeAccruals ?? 0 }
    private var accruingAmount: Double { summary?.totalChargesAccruing ?? 0 }

    private var freshness: (text: String, color: Color) {
        guard let lastLoadedAt else { return ("READING", palette.textTertiary) }
        let minutes = max(0, Int(clock.timeIntervalSince(lastLoadedAt)) / 60)
        if !reachability.isOnline {
            return ("OFFLINE · \(minutes)M", Brand.warning)
        }
        if minutes >= 5 {
            return ("STALE · \(minutes)M", Brand.warning)
        }
        return ("LIVE · \(time662(lastLoadedAt))", Brand.success)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading && dashboard == nil {
                    loadingCard
                } else {
                    hero
                    postureStrip
                    decisionPosture
                    docketSection
                    runwaySection
                    if let loadError { errorCard(loadError) }
                    if let actionError { errorCard(actionError) }
                    if let actionMessage { successCard(actionMessage) }
                    refreshButton
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .task { await runFreshnessClock() }
        .eusoRefreshable { await load() }
        .sheet(item: $selectedDispute) { dispute in
            DemurrageDecisionSheet662(dispute: dispute) { result in
                actionError = nil
                actionMessage = result.alreadyResolved
                    ? "Dispute #\(result.disputeId) was already \(result.decision)."
                    : "Dispute #\(result.disputeId) was \(result.decision); charge is now \(pretty662(result.chargeStatus))."
                Task { await load() }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "RAIL · DEMURRAGE REVIEW")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(freshness.text)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(freshness.color)
            }

            HStack(spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Demurrage review")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(openDisputes)")
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(openDisputes > 0 ? Brand.warning : Brand.success)
                Text(openDisputes == 1 ? "open dispute" : "open disputes")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }

            Text(openDisputes == 0
                 ? "No disputed rail demurrage charges are reported for this company."
                 : "Disputed charges remain blocked from invoicing or settlement until a recorded decision is available.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
    }

    private var postureStrip: some View {
        HStack(spacing: Space.s2) {
            postureCell(label: "ACCRUING", value: "\(activeAccruals)", tint: Brand.info)
            postureCell(label: "AMOUNT", value: money662(accruingAmount), tint: Brand.warning)
            postureCell(label: "RUNWAY", value: "\(runway.count)", tint: Brand.rail)
        }
    }

    private func postureCell(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private var decisionPosture: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: openDisputes > 0 ? "lock.shield" : "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(openDisputes > 0 ? Brand.warning : Brand.success)
            VStack(alignment: .leading, spacing: 4) {
                Text(openDisputes > 0 ? "Decision docket required" : "No decision pending")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(openDisputes > 0
                     ? "Each decision below is bound to a persisted dispute and its company-owned rail shipment."
                     : "There is no open dispute to approve or deny.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((openDisputes > 0 ? Brand.warning : Brand.success).opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder((openDisputes > 0 ? Brand.warning : Brand.success).opacity(0.35)))
    }

    @ViewBuilder
    private var docketSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("OPEN DECISION DOCKET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(docket.count) TENANT-SCOPED")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if docket.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.seal",
                    title: "No open decisions",
                    subtitle: "No submitted or under-review demurrage disputes are linked to this company."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(docket.enumerated()), id: \.element.id) { index, dispute in
                        docketRow(dispute)
                        if index < docket.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 52)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func docketRow(_ dispute: DemurrageDispute662) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.warning)
                .frame(width: 38, height: 38)
                .background(Brand.warning.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(nonempty662(dispute.railcarNumber) ?? nonempty662(dispute.shipmentNumber) ?? "Dispute #\(dispute.id)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text("\(pretty662(dispute.reason)) · \(money662(dispute.totalCharge)) charge")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if let requested = dispute.requestedWaiverAmount {
                    Text("Requested waiver \(money662(requested))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }
            }

            Spacer(minLength: Space.s2)

            Button {
                actionMessage = nil
                actionError = nil
                selectedDispute = dispute
            } label: {
                Label("Decide", systemImage: "checkmark.seal")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
    }

    @ViewBuilder
    private var runwaySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACTIVE ACCRUAL RUNWAY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("TODAY → +24H")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if runway.isEmpty {
                EusoEmptyState(
                    systemImage: "train.side.front.car",
                    title: "No active accruals",
                    subtitle: "No accruing railcar charges were returned for this company."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(runway.enumerated()), id: \.element.id) { index, car in
                        runwayRow(car)
                        if index < runway.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 52)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func runwayRow(_ car: RunwayCar662) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "train.side.front.car")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.rail)
                .frame(width: 38, height: 38)
                .background(Brand.rail.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(nonempty662(car.railcarNumber) ?? "Charge #\(car.id)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(runwayBasis662(car))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 3) {
                Text(money662(car.usdToday))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("→ \(money662(car.usdProjected))")
                    .font(.system(size: 10, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3)
    }

    private var refreshButton: some View {
        CTAButton(
            title: loading ? "Refreshing…" : "Refresh demurrage",
            action: { Task { await load() } },
            trailingIcon: "arrow.clockwise",
            isLoading: loading
        )
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 220)
            .overlay(ProgressView().tint(palette.textPrimary))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
    }

    private func successCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.success.opacity(0.4)))
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        loadError = nil

        do {
            async let dashboardRequest: DemurrageDashboard662 = EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard",
                input: EmptyInput662()
            )
            async let docketRequest: DemurrageDocket662 = EusoTripAPI.shared.query(
                "railDemurrageAuto.getDisputeDocket",
                input: EmptyInput662()
            )
            let (dashboardResult, docketResult) = try await (dashboardRequest, docketRequest)
            dashboard = dashboardResult
            docket = docketResult.disputes
            lastLoadedAt = Date()
            clock = Date()
        } catch {
            loadError = error.eusoUserCopy
        }

    }

    @MainActor
    private func runFreshnessClock() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            clock = Date()
        }
    }
}

private struct DemurrageDecisionSheet662: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reachability = OfflineReachabilityHub.shared

    let dispute: DemurrageDispute662
    let onResolved: (ResolveDisputeResult662) -> Void

    @State private var decision = "approved"
    @State private var resolutionNotes = ""
    @State private var saving = false
    @State private var actionError: String?
    @State private var requestKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(nonempty662(dispute.railcarNumber) ?? nonempty662(dispute.shipmentNumber) ?? "Dispute #\(dispute.id)")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Stored charge \(money662(dispute.totalCharge)) · \(pretty662(dispute.reason))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        if let notes = nonempty662(dispute.notes) {
                            Text(notes)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Picker("Decision", selection: $decision) {
                        Text("Approve waiver").tag("approved")
                        Text("Deny dispute").tag("denied")
                    }
                    .pickerStyle(.segmented)

                    Text(decision == "approved"
                         ? "Approval waives the disputed charge."
                         : "Denial restores the charge to its recorded pre-dispute billable state.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("RESOLUTION NOTES")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        TextEditor(text: $resolutionNotes)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    }

                    if let actionError {
                        Text(actionError)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CTAButton(
                        title: saving ? "Recording…" : (decision == "approved" ? "Approve waiver" : "Deny dispute"),
                        action: { Task { await resolve() } },
                        trailingIcon: decision == "approved" ? "checkmark" : "xmark",
                        isLoading: saving
                    )
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Demurrage decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func resolve() async {
        guard !saving else { return }
        guard reachability.isOnline else {
            actionError = "Reconnect to record this financial decision."
            return
        }
        guard resolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2_000 else {
            actionError = "Resolution notes must be 2,000 characters or fewer."
            return
        }
        saving = true
        actionError = nil
        defer { saving = false }

        do {
            let result: ResolveDisputeResult662 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.resolveDispute",
                input: ResolveDisputeInput662(
                    confirm: true,
                    disputeId: dispute.id,
                    decision: decision,
                    resolutionNotes: nonempty662(resolutionNotes),
                    requestKey: requestKey
                )
            )
            guard result.success else {
                actionError = "The demurrage decision was not recorded. Review the charge and try again."
                return
            }
            onResolved(result)
            dismiss()
        } catch {
            actionError = error.eusoUserCopy
        }
    }
}

private func runwayBasis662(_ car: RunwayCar662) -> String {
    String(
        format: "%.0fh free · %.1fh @ %@/h",
        car.freeTimeHours,
        car.chargeableHours,
        money662(car.ratePerHour)
    )
}

private func money662(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = value == value.rounded() ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
}

private func time662(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func nonempty662(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func pretty662(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}

#Preview("662 · Rail Demurrage Review · Night") {
    RailDemurrageChargeApproval_662(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("662 · Rail Demurrage Review · Light") {
    RailDemurrageChargeApproval_662(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
