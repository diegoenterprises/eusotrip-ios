//
//  824_VesselRiskProfile.swift
//  EusoTrip - Vessel Operator - Vessel compliance profile.
//
//  Production contract:
//    vesselShipments.getVesselRiskEvidence({ imoNumber })
//
//  The server does not publish a composite screening score, flag history, or a
//  vessel sanctions verdict. This screen renders only scoped registry identity
//  and recorded compliance evidence returned by the contract above.
//

import SwiftUI

private struct VesselRecord824: Decodable, Identifiable {
    let id: Int
    let name: String
    let imoNumber: String?
    let flag: String?
    let vesselType: String
    let classificationSociety: String?
    let status: String?
}

private struct VesselCompliance824: Decodable {
    let status: String
    let totalInspections: Int
    let adverseInspectionCount: Int?
    let expiredInsuranceCount: Int?
    let expiredIspsCount: Int?
}

private struct USCGCheck824: Decodable, Identifiable {
    let name: String
    let status: String
    let details: String
    let sourceType: String
    let sourceRecordId: Int?
    let recordedAt: String?

    var id: String { name }
}

private struct VesselRiskEvidence824: Decodable {
    let vessel: VesselRecord824
    let summary: VesselCompliance824
    let checks: [USCGCheck824]
    let allRecordedChecksSatisfied: Bool
    let evidenceUpdatedAt: String?
}

private struct VesselRiskInput824: Encodable {
    let imoNumber: String
}

struct VesselRiskProfileScreen: View {
    let theme: Theme.Palette
    var imo: String

    init(theme: Theme.Palette, imo: String = "") {
        self.theme = theme
        self.imo = imo
    }

    var body: some View {
        Shell(theme: theme) {
            VesselRiskProfileBody824(imo: imo)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

private struct VesselRiskProfileBody824: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let imo: String

    @State private var evidence: VesselRiskEvidence824?
    @State private var loading = false
    @State private var loadError: String?
    @State private var emptyMessage: String?

    private var vessel: VesselRecord824? { evidence?.vessel }
    private var compliance: VesselCompliance824? { evidence?.summary }
    private var checks: [USCGCheck824] { evidence?.checks ?? [] }
    private var issueCount: Int {
        (compliance?.adverseInspectionCount ?? 0)
            + (compliance?.expiredInsuranceCount ?? 0)
            + (compliance?.expiredIspsCount ?? 0)
    }
    private var recordedCheckCount: Int {
        checks.filter { !["no_record", "unknown"].contains($0.status.lowercased()) }.count
    }
    private var posture: (label: String, color: Color) {
        if issueCount > 0 || checks.contains(where: { $0.status.lowercased() == "issue" }) {
            return ("ISSUES FOUND", Brand.danger)
        }
        if evidence?.allRecordedChecksSatisfied == true && recordedCheckCount > 0 {
            return ("RECORDED CHECKS SATISFIED", Brand.success)
        }
        if recordedCheckCount > 0 || (compliance?.totalInspections ?? 0) > 0 {
            return ("EVIDENCE RECORDED", Brand.info)
        }
        return ("NO RECORDED EVIDENCE", palette.textTertiary)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading && vessel == nil {
                    loadingCard
                } else if let loadError, vessel == nil {
                    errorCard(loadError)
                    refreshButton
                } else if let emptyMessage, vessel == nil {
                    emptyCard(emptyMessage)
                    refreshButton
                } else if vessel != nil {
                    identityCard
                    summaryStrip
                    checksLedger
                    if let loadError { errorCard(loadError) }
                    refreshButton
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · COMPLIANCE EVIDENCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(evidenceTimestamp824(evidence?.evidenceUpdatedAt))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            HStack(spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Vessel compliance profile")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vessel?.name ?? "Vessel")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("IMO \(vessel?.imoNumber ?? normalizedIMO824(imo))")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                Text(posture.label)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(posture.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(posture.color.opacity(0.14)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Divider().overlay(palette.borderFaint)

            identityRow(label: "FLAG", value: nonempty824(vessel?.flag) ?? "Not recorded")
            identityRow(label: "TYPE", value: displayValue824(vessel?.vesselType))
            identityRow(label: "CLASS", value: nonempty824(vessel?.classificationSociety) ?? "Not recorded")
            identityRow(label: "STATUS", value: displayValue824(vessel?.status))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
    }

    private func identityRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Space.s2) {
            summaryCell("INSPECTIONS", compliance?.totalInspections ?? 0, Brand.info)
            summaryCell("ADVERSE", compliance?.adverseInspectionCount ?? 0, Brand.danger)
            summaryCell("EXPIRED", (compliance?.expiredInsuranceCount ?? 0) + (compliance?.expiredIspsCount ?? 0), Brand.warning)
        }
    }

    private func summaryCell(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? tint : palette.textPrimary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private var checksLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECORDED VESSEL CHECKS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(recordedCheckCount) WITH EVIDENCE")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if checks.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.shield",
                    title: "No compliance checks returned",
                    subtitle: "No vessel check records were returned for this authorized vessel."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                        checkRow(check)
                        if index < checks.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 50)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func checkRow(_ check: USCGCheck824) -> some View {
        let state = check.status.lowercased()
        let tint: Color
        let icon: String
        switch state {
        case "satisfied":
            tint = Brand.success
            icon = "checkmark.seal.fill"
        case "issue":
            tint = Brand.danger
            icon = "exclamationmark.triangle.fill"
        default:
            tint = palette.textTertiary
            icon = "questionmark.circle"
        }

        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(check.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(check.details)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source = evidenceSource824(check) {
                    Text(source)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s2)
            Text(displayValue824(check.status))
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(tint)
        }
        .padding(Space.s3)
    }

    private var refreshButton: some View {
        CTAButton(
            title: loading ? "Refreshing…" : "Refresh evidence",
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

    private func emptyCard(_ message: String) -> some View {
        EusoEmptyState(
            systemImage: "ferry",
            title: "Vessel not available",
            subtitle: message
        )
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

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        loadError = nil
        emptyMessage = nil

        let requestedIMO = normalizedIMO824(imo)
        guard requestedIMO.count == 7 else {
            evidence = nil
            emptyMessage = "Open this profile from a vessel with a recorded IMO number."
            return
        }

        do {
            evidence = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselRiskEvidence",
                input: VesselRiskInput824(imoNumber: requestedIMO)
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

    }
}

private func normalizedIMO824(_ value: String) -> String {
    value
        .uppercased()
        .replacingOccurrences(of: "IMO", with: "")
        .filter { $0.isNumber }
}

private func nonempty824(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func displayValue824(_ value: String?) -> String {
    guard let value = nonempty824(value) else { return "Not recorded" }
    return value.replacingOccurrences(of: "_", with: " ").capitalized
}

private func evidenceSource824(_ check: USCGCheck824) -> String? {
    guard let sourceRecordId = check.sourceRecordId else { return nil }
    let source = displayValue824(check.sourceType)
    if let recordedAt = nonempty824(check.recordedAt) {
        return "\(source) #\(sourceRecordId) · \(shortEvidenceDate824(recordedAt))"
    }
    return "\(source) #\(sourceRecordId)"
}

private func evidenceTimestamp824(_ value: String?) -> String {
    guard let value = nonempty824(value) else { return "NO SOURCE DATE" }
    return "EVIDENCE · \(shortEvidenceDate824(value).uppercased())"
}

private func shortEvidenceDate824(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    guard let date else { return String(value.prefix(16)) }
    let output = DateFormatter()
    output.dateFormat = "MMM d, yyyy HH:mm"
    return output.string(from: date)
}

#Preview("824 · Vessel Compliance Profile · Night") {
    VesselRiskProfileScreen(theme: Theme.dark, imo: "1234567")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("824 · Vessel Compliance Profile · Light") {
    VesselRiskProfileScreen(theme: Theme.light, imo: "1234567")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
