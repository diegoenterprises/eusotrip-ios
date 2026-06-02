//
//  1112_ComplianceGatesStrip.swift
//  EusoTrip — Compliance · RIOS §11 · Inline load-party sanctions gate strip.
//
//  REUSABLE INLINE COMPONENT (not a sheet, not a numbered screen). Hosts embed
//  it on a Load Detail surface to surface the live OFAC / sanctions screening
//  state of every party on a load (shipper · carrier · broker · consignee …)
//  as a compact chip strip with an expandable detail breakdown.
//
//  Honest states (spec §11):
//    - Green "Cleared" ONLY on status == "clear"/"cleared"/"pass".
//    - Red "Blocked" on a "blocked"/"match"/"hit" status (also flips
//      `gateLocked = true` so the host can disable Accept/Dispatch).
//    - Amber "Pending review" on "pending"/"review"/"provider_unavailable"
//      / null — never a fabricated success.
//  Thrown errors are surfaced verbatim via (error as? LocalizedError)?.errorDescription.
//

import SwiftUI

/// Compact, embeddable strip that screens every party on a load against the
/// sanctions service and renders a per-party gate chip. Drives `gateLocked`
/// for the host so a blocked / matched party can hard-stop Accept / Dispatch.
struct ComplianceGatesStrip: View {
    /// The load whose parties should be screened.
    let loadId: Int
    /// Host role context (e.g. "shipper", "carrier", "dispatcher"). Used only
    /// to phrase the lock copy so it reads naturally for the surface it sits
    /// on; the screening itself is role-agnostic.
    var role: String = "shipper"
    /// When any party is blocked / matched, this flips to `true` so the host
    /// Load Detail can disable its Accept / Dispatch CTA. Cleared back to
    /// `false` when a re-screen comes back clean.
    @Binding var gateLocked: Bool

    /// Preview-/host-friendly seam: when supplied, the strip renders these
    /// parties immediately instead of hitting the network. Used by `#Preview`
    /// and by hosts that already hold a screening result and just want the
    /// presentation. When `nil` (the default) the strip loads live on `.task`.
    var previewParties: [SanctionsAPI.LoadPartyResult]? = nil
    var previewOverallStatus: String? = nil
    var previewClearedToTransact: Bool? = nil

    @Environment(\.palette) private var palette

    @State private var parties: [SanctionsAPI.LoadPartyResult] = []
    @State private var overallStatus: String? = nil
    @State private var clearedToTransact: Bool? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var expanded = false
    /// Guards `.task` against re-running its live load when the strip was
    /// seeded with preview / host-provided parties.
    @State private var seeded = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            headerRow

            if loading {
                loadingRow
            } else if let loadError {
                errorRow(loadError)
            } else if parties.isEmpty {
                emptyRow
            } else {
                chipStrip
                if expanded {
                    detailList
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(intensity: blocked ? .feature : .standard)
        .task { await loadIfNeeded() }
    }

    // MARK: - Derived state

    /// True when ANY party comes back blocked / matched. Source of truth for
    /// `gateLocked` and the strip's alarm styling.
    private var blocked: Bool {
        if clearedToTransact == false { return true }
        if overallStatus.map(Self.classify) == .blocked { return true }
        return parties.contains { Self.classify($0.status) == .blocked }
    }

    /// True only on an explicit all-clear: server cleared-to-transact OR every
    /// party individually cleared. Drives the header summary badge.
    private var allClear: Bool {
        guard !parties.isEmpty else { return false }
        if clearedToTransact == true { return true }
        if blocked { return false }
        return parties.allSatisfy { Self.classify($0.status) == .clear }
    }

    private var pendingCount: Int {
        parties.filter { Self.classify($0.status) == .pending }.count
    }
    private var blockedCount: Int {
        parties.filter { Self.classify($0.status) == .blocked }.count
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(blocked ? AnyShapeStyle(Brand.danger)
                                         : AnyShapeStyle(LinearGradient.diagonal))
            Text("SANCTIONS SCREENING")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(blocked ? AnyShapeStyle(Brand.danger)
                                         : AnyShapeStyle(LinearGradient.diagonal))
            Spacer(minLength: 0)
            summaryBadge
            if !parties.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse party detail" : "Expand party detail")
            }
        }
    }

    @ViewBuilder
    private var summaryBadge: some View {
        if loading || parties.isEmpty {
            EmptyView()
        } else if blocked {
            StatusPill(text: blockedCount > 0 ? "\(blockedCount) blocked" : "Blocked", kind: .danger)
        } else if pendingCount > 0 {
            StatusPill(text: "\(pendingCount) pending", kind: .warning)
        } else if allClear {
            StatusPill(text: "All cleared", kind: .success)
        } else {
            StatusPill(text: overallStatus?.capitalized ?? "Review", kind: .warning)
        }
    }

    // MARK: - Chip strip

    private var chipStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(parties) { party in
                    GateChip(party: party)
                }
            }
            .padding(.vertical, 2)
        }
        // Lock notice sits under the strip so it's always visible even when
        // collapsed — the host needs the operator to understand WHY the CTA
        // is disabled.
        .overlay(alignment: .bottom) { EmptyView() }
        .safeAreaInset(edge: .bottom, spacing: blocked ? Space.s3 : 0) {
            if blocked { lockNotice }
        }
    }

    private var lockNotice: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Brand.danger)
            Text(lockCopy)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintDanger)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1)
        )
    }

    private var lockCopy: String {
        let actor: String
        switch role.lowercased() {
        case "carrier", "driver", "dispatcher": actor = "Dispatch is locked"
        case "broker":                           actor = "Tendering is locked"
        default:                                 actor = "Accepting is locked"
        }
        return "\(actor): a party on this load matched a sanctions list. Clear the match by manual review before this load can transact."
    }

    // MARK: - Expandable detail

    private var detailList: some View {
        VStack(spacing: Space.s2) {
            IridescentHairline()
            ForEach(parties) { party in
                GateDetailRow(party: party)
            }
            if let overallStatus, !overallStatus.isEmpty {
                HStack(spacing: 6) {
                    Text("OVERALL")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(overallStatus.capitalized)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Non-data rows

    private var loadingRow: some View {
        HStack(spacing: Space.s2) {
            ProgressView().controlSize(.small)
            Text("Screening load parties…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry screening") { Task { await reload() } }
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(Brand.info)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintWarning)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.45), lineWidth: 1)
        )
    }

    private var emptyRow: some View {
        Text("No parties on this load have been screened yet.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Load

    private func loadIfNeeded() async {
        // Host-/preview-seeded path: render the provided parties, never touch
        // the network, and still publish the lock state to the host.
        if let previewParties {
            guard !seeded else { return }
            seeded = true
            parties = previewParties
            overallStatus = previewOverallStatus
            clearedToTransact = previewClearedToTransact
            loading = false
            publishLock()
            return
        }
        await reload()
    }

    private func reload() async {
        loading = true
        loadError = nil
        do {
            let result = try await EusoTripAPI.shared.sanctions.screenLoadParties(loadId: loadId)
            parties = result.parties ?? []
            overallStatus = result.overallStatus
            clearedToTransact = result.clearedToTransact
            publishLock()
        } catch let apiErr as EusoTripAPIError {
            loadError = apiErr.errorDescription ?? "Couldn't screen the parties on this load."
            // Fail safe: an unscreened load is NOT cleared to transact.
            gateLocked = true
        } catch let localized as LocalizedError {
            loadError = localized.errorDescription ?? "Couldn't screen the parties on this load."
            gateLocked = true
        } catch {
            loadError = error.localizedDescription
            gateLocked = true
        }
        loading = false
    }

    /// Pushes the derived block state up to the host binding.
    private func publishLock() {
        gateLocked = blocked
    }

    // MARK: - Status classification (shared)

    enum GateState { case clear, pending, blocked }

    /// Maps a free-form server status string to the strip's tri-state.
    /// Unknown / null statuses fall through to `.pending` (never a fake pass).
    static func classify(_ status: String?) -> GateState {
        switch (status ?? "").lowercased() {
        case "clear", "cleared", "pass", "passed", "ok", "verified":
            return .clear
        case "blocked", "block", "match", "matched", "hit", "denied", "rejected", "failed":
            return .blocked
        default:
            // "pending", "review", "in_review", "provider_unavailable",
            // "", and anything unrecognized → pending review.
            return .pending
        }
    }
}

// MARK: - GateChip (compact per-party pill)

private struct GateChip: View {
    let party: SanctionsAPI.LoadPartyResult
    @Environment(\.palette) private var palette

    private var state: ComplianceGatesStrip.GateState {
        ComplianceGatesStrip.classify(party.status)
    }
    private var tint: Color {
        switch state {
        case .clear:   return Brand.success
        case .pending: return Brand.warning
        case .blocked: return Brand.danger
        }
    }
    private var icon: String {
        switch state {
        case .clear:   return "checkmark.seal.fill"
        case .pending: return "clock.fill"
        case .blocked: return "xmark.octagon.fill"
        }
    }
    private var stateLabel: String {
        switch state {
        case .clear:   return "Cleared"
        case .pending: return "Pending review"
        case .blocked: return "Blocked"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(roleLabel)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(party.name ?? "Unnamed party")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(stateLabel)
                    .font(EType.micro)
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(roleLabel): \(party.name ?? "unnamed party"), \(stateLabel)")
    }

    private var roleLabel: String {
        (party.role ?? "Party")
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }
}

// MARK: - GateDetailRow (expanded breakdown line)

private struct GateDetailRow: View {
    let party: SanctionsAPI.LoadPartyResult
    @Environment(\.palette) private var palette

    private var state: ComplianceGatesStrip.GateState {
        ComplianceGatesStrip.classify(party.status)
    }
    private var tint: Color {
        switch state {
        case .clear:   return Brand.success
        case .pending: return Brand.warning
        case .blocked: return Brand.danger
        }
    }
    private var statusText: String {
        switch state {
        case .clear:   return "Cleared"
        case .pending:
            // Surface the raw server status when it's informative (e.g.
            // "provider_unavailable") so the operator knows WHY it's pending.
            let raw = (party.status ?? "").lowercased()
            if raw == "provider_unavailable" { return "Provider unavailable — manual review" }
            return party.status?.capitalized ?? "Pending review"
        case .blocked: return party.status?.capitalized ?? "Blocked"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(party.name ?? "Unnamed party")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let role = party.role, !role.isEmpty {
                        Text("· \(role.replacingOccurrences(of: "_", with: " "))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    if let risk = party.overallRisk, !risk.isEmpty {
                        Text("Risk: \(risk.capitalized)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let entityId = party.entityId {
                        Text("#\(entityId)")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("1112 · Gates strip · Mixed · Night") {
    StripPreviewHost(
        parties: [
            .init(role: "shipper", entityId: 101, name: "Acme Freight Co.", status: "clear", overallRisk: "low"),
            .init(role: "carrier", entityId: 202, name: "Northbound Logistics", status: "pending", overallRisk: "medium"),
            .init(role: "broker", entityId: 303, name: "Sky Brokerage LLC", status: "provider_unavailable", overallRisk: nil),
        ],
        overallStatus: "review",
        cleared: nil
    )
    .padding()
    .background(Theme.dark.bgPrimary)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("1112 · Gates strip · Blocked · Afternoon") {
    StripPreviewHost(
        parties: [
            .init(role: "shipper", entityId: 101, name: "Acme Freight Co.", status: "clear", overallRisk: "low"),
            .init(role: "consignee", entityId: 404, name: "Sanctioned Holdings", status: "blocked", overallRisk: "critical"),
        ],
        overallStatus: "blocked",
        cleared: false
    )
    .padding()
    .background(Theme.light.bgPrimary)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}

/// Tiny preview harness that owns the `gateLocked` binding and echoes its
/// resolved value so the honest lock behaviour is visible in canvas.
private struct StripPreviewHost: View {
    let parties: [SanctionsAPI.LoadPartyResult]
    let overallStatus: String?
    let cleared: Bool?

    @State private var gateLocked = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ComplianceGatesStrip(
                loadId: 0,
                role: "shipper",
                gateLocked: $gateLocked,
                previewParties: parties,
                previewOverallStatus: overallStatus,
                previewClearedToTransact: cleared
            )
            CTAButton(title: gateLocked ? "Accept blocked" : "Accept load",
                      isLoading: gateLocked)
        }
    }
}
