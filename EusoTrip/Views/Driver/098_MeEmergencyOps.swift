//
//  098_MeEmergencyOps.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Emergency Ops)
//
//  Screen 098 · Me · Emergency Ops — the driver's emergency-
//  mobilization surface. When FEMA calls up fuel haulers during a
//  hurricane or a pipeline outage throws the Southeast into
//  shortage, qualified drivers see the active mobilization orders
//  here with commodity + region + surge pay. One-tap accept or
//  decline. Active responses get an en-route → on-site → completed
//  status flow. Aggregate counters show total loads hauled +
//  miles contributed across all emergency ops.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • All orders + responses from `emergencyResponse.
//      getMyMobilizations` — MCP-verified at
//      `frontend/server/routers/emergencyResponse.ts`. Note the
//      server currently stores this state in-memory (not DB-
//      backed), so an active mobilization resets on server
//      restart. iOS surfaces whatever the server sees RIGHT NOW;
//      no client-side persistence overlay.
//    • Accept / decline fires `respondToMobilization` with the
//      driver's chosen accept flag + optional ETA.
//    • Status updates fire `updateMobilizationStatus`.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero stats + accept CTA.
//         Brand.warning on high-severity ops, Brand.magenta on
//         critical-severity ops.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeEmergencyOps: View {
    @Environment(\.palette) var palette
    @StateObject private var store = EmergencyOpsStore()

    @State private var responding: EmergencyAPI.MobilizationOrder?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                heroStats
                availableSection
                activeSection
                completedSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $responding) { order in
            RespondSheet(order: order, store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Emergency Ops")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FEMA · hurricane surge · pipeline outage")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Hero stats

    private var heroStats: some View {
        let f = store.feed
        return HStack(spacing: Space.s2) {
            statTile(
                label: "LOADS HAULED",
                value: "\(f?.totalLoadsCompleted ?? 0)",
                gradient: true
            )
            statTile(
                label: "MILES",
                value: compactMiles(f?.totalMilesHauled ?? 0),
                gradient: true
            )
            statTile(
                label: "ACTIVE",
                value: "\(f?.myActiveResponses.count ?? 0)",
                gradient: false
            )
        }
    }

    private func statTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Available

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("AVAILABLE MOBILIZATIONS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if (store.feed?.availableOrders.isEmpty ?? true) && !store.isLoading {
                EusoEmptyState(
                    systemImage: "shield.lefthalf.filled",
                    title: "No active emergencies",
                    subtitle: "When FEMA or a state EOC declares a mobilization, qualified drivers get the call here with surge pay + deadline."
                )
            } else {
                ForEach(store.feed?.availableOrders ?? []) { order in
                    orderCard(order)
                }
            }
        }
    }

    private func orderCard(_ order: EmergencyAPI.MobilizationOrder) -> some View {
        let severity = (order.operation?.severity ?? "").uppercased()
        let critical = severity.contains("CRIT") || severity.contains("HIGH")
        let alreadyResponded = order.myResponse != nil
        let accepted = (order.myResponse?.status ?? "").uppercased().contains("ACCEPT")
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let op = order.operation?.name, !op.isEmpty {
                        Text(op.uppercased())
                            .font(EType.micro)
                            .tracking(1.2)
                            .foregroundStyle(critical ? Brand.magenta : Brand.warning)
                    }
                    Text(order.title ?? "Mobilization \(order.id)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let desc = order.description, !desc.isEmpty {
                        Text(desc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if !severity.isEmpty {
                    severityChip(severity, critical: critical)
                }
            }

            HStack(spacing: Space.s3) {
                if let commodity = order.commodity, !commodity.isEmpty {
                    metaPill(icon: "shippingbox", text: commodity.capitalized)
                }
                if let region = order.region, !region.isEmpty {
                    metaPill(icon: "mappin.and.ellipse", text: region)
                }
                if order.hazmatRequired == true {
                    metaPill(icon: "exclamationmark.triangle", text: "HAZMAT")
                }
            }

            HStack {
                if let surge = order.surgeMultiplier, surge > 1.0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt")
                        Text(String(format: "%.1f×", surge))
                            .monospacedDigit()
                        Text("SURGE")
                    }
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(LinearGradient.diagonal)
                }
                if let cents = order.payPerMileCents, cents > 0 {
                    Spacer()
                    Text(String(format: "$%.2f / mi", Double(cents) / 100.0))
                        .font(EType.bodyStrong)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                }
            }

            if let deadline = order.deadline, !deadline.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Respond by \(humanizeDate(deadline))")
                        .font(EType.caption)
                }
                .foregroundStyle(Brand.warning)
            }

            if alreadyResponded {
                HStack(spacing: 4) {
                    Image(systemName: accepted ? "checkmark.seal.fill" : "xmark.seal")
                    Text(accepted ? "You accepted" : "You declined")
                }
                .font(EType.caption)
                .foregroundStyle(accepted ? .green : palette.textTertiary)
            } else {
                HStack(spacing: Space.s2) {
                    Button {
                        responding = order
                    } label: {
                        Label("Accept", systemImage: "checkmark.circle.fill")
                            .font(EType.bodyStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.mutatingId == order.id)

                    Button {
                        Task {
                            await store.respond(to: order, accept: false)
                        }
                    } label: {
                        Label("Decline", systemImage: "xmark.circle")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s2)
                            .overlay(
                                Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.mutatingId == order.id)
                    Spacer()
                }
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(
                            critical ? Brand.magenta.opacity(0.6) : palette.borderFaint,
                            lineWidth: critical ? 1 : 0.5
                        )
                )
        )
    }

    @ViewBuilder
    private func severityChip(_ severity: String, critical: Bool) -> some View {
        let tint: Color = critical ? Brand.magenta : Brand.warning
        Text(severity)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(tint, lineWidth: 1))
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(EType.micro)
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(palette.tintNeutral.opacity(0.55))
        )
    }

    // MARK: Active responses

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !(store.feed?.myActiveResponses.isEmpty ?? true) {
                Text("YOUR ACTIVE RESPONSES")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(store.feed?.myActiveResponses ?? []) { r in
                    activeResponseRow(r)
                }
            }
        }
    }

    private func activeResponseRow(_ r: EmergencyAPI.MobilizationResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.status ?? "ACTIVE")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let state = r.currentState, !state.isEmpty {
                        Text("Location · \(state)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(r.loadsCompleted ?? 0) loads")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    Text("\(compactMiles(r.milesHauled ?? 0)) mi")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: Space.s2) {
                statusAdvanceButton(r, targetStatus: "EN_ROUTE", label: "En route")
                statusAdvanceButton(r, targetStatus: "ON_SITE", label: "On site")
                statusAdvanceButton(r, targetStatus: "COMPLETED", label: "Complete")
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func statusAdvanceButton(
        _ r: EmergencyAPI.MobilizationResponse,
        targetStatus: String,
        label: String
    ) -> some View {
        let isCurrent = (r.status ?? "").uppercased() == targetStatus
        return Button {
            Task { await store.updateStatus(response: r, status: targetStatus) }
        } label: {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(isCurrent
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textSecondary))
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isCurrent
                                   ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                   : AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
                )
        }
        .buttonStyle(.plain)
        .disabled(store.mutatingId == r.id || isCurrent)
    }

    // MARK: Completed

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !(store.feed?.myCompletedResponses.isEmpty ?? true) {
                Text("COMPLETED")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(store.feed?.myCompletedResponses ?? []) { r in
                    completedRow(r)
                }
            }
        }
    }

    private func completedRow(_ r: EmergencyAPI.MobilizationResponse) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(LinearGradient.diagonal)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.loadsCompleted ?? 0) loads · \(compactMiles(r.milesHauled ?? 0)) mi")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                if let ts = r.respondedAt {
                    Text(humanizeDate(ts))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Emergency mobilizations are voluntary. Surge pay + federal reimbursement typically apply. You can decline without penalty to your rating.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func compactMiles(_ miles: Double) -> String {
        if miles >= 100_000 { return String(format: "%.0fK", miles / 1000.0) }
        if miles >= 1_000   { return String(format: "%.1fK", miles / 1000.0) }
        if miles == miles.rounded() { return String(format: "%.0f", miles) }
        return String(format: "%.1f", miles)
    }

    private func humanizeDate(_ iso: String) -> String {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let s = -date.timeIntervalSinceNow
        if s > 0 {
            if s < 3600 { return "\(Int(s / 60))m ago" }
            if s < 86400 { return "\(Int(s / 3600))h ago" }
            return "\(Int(s / 86400))d ago"
        } else {
            let ahead = -s
            if ahead < 3600 { return "in \(Int(ahead / 60))m" }
            if ahead < 86400 { return "in \(Int(ahead / 3600))h" }
            return "in \(Int(ahead / 86400))d"
        }
    }
}

// MARK: - Respond sheet

private struct RespondSheet: View {
    @Environment(\.dismiss) private var dismiss
    let order: EmergencyAPI.MobilizationOrder
    @ObservedObject var store: EmergencyOpsStore

    @State private var state: String = ""
    @State private var etaHours: Int = 4

    var body: some View {
        NavigationStack {
            Form {
                Section("Mobilization") {
                    Text(order.title ?? "Mobilization \(order.id)")
                        .font(EType.bodyStrong)
                    if let desc = order.description {
                        Text(desc)
                            .foregroundStyle(.secondary)
                            .font(EType.caption)
                    }
                }
                Section("Your current state") {
                    TextField("e.g. TX, OK", text: $state)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Estimated arrival") {
                    Stepper(
                        "\(etaHours) hour\(etaHours == 1 ? "" : "s")",
                        value: $etaHours,
                        in: 1...72
                    )
                }
            }
            .navigationTitle("Accept mobilization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.respond(
                                to: order,
                                accept: true,
                                currentState: state.isEmpty ? nil : state,
                                etaMinutes: etaHours * 60
                            )
                            dismiss()
                        }
                    } label: {
                        if store.mutatingId == order.id {
                            ProgressView()
                        } else {
                            Text("Accept").fontWeight(.semibold)
                        }
                    }
                    .disabled(store.mutatingId == order.id)
                }
            }
        }
    }
}

// MARK: - Screen wrapper

struct MeEmergencyOpsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeEmergencyOps()
        } nav: {
            BottomNav(
                leading: driverNavLeading_098(),
                trailing: driverNavTrailing_098(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_098() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_098() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("098 · Emergency Ops · Night") {
    MeEmergencyOpsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("098 · Emergency Ops · Afternoon") {
    MeEmergencyOpsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
