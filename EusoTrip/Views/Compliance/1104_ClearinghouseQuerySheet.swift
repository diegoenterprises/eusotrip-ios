//
//  1104_ClearinghouseQuerySheet.swift
//  EusoTrip — Compliance · FMCSA Drug & Alcohol Clearinghouse consent (RIOS §11).
//
//  A .sheet-content capture surface (1104). The compliance officer (or
//  onboarding flow) records a driver's electronic consent for a FMCSA
//  Clearinghouse query — pre-employment (full), annual (limited), or a
//  limited query — and the server (registration.attachClearinghouseConsent)
//  files it.
//
//  HONESTY DOCTRINE (RIOS §11):
//    The Clearinghouse has no live B2B feed in this environment. We file the
//    CONSENT, we do not fabricate a result. So we render the server's status
//    verbatim:
//      - "registered_pre_employment" / "consent_filed" / "verified" → green
//        "Consent on file" only when the server actually confirms it.
//      - null / "pending" / "provider_unavailable" → neutral "Pending review"
//        / "Provider unavailable — manual review" with Brand.warning. NEVER a
//        fake success.
//      - any status containing "prohibit" → RED "PROHIBITED — dispatch blocked".
//      - "not_enrolled" → neutral "Driver not enrolled in Clearinghouse".
//
//  Push-nav mandate: this is sheet content, presented via .sheet by the
//  caller (capture precedent — 1100-1110 are acceptable sheets). It is NOT a
//  pushed Shell screen and carries no bottom nav.
//

import SwiftUI

struct ClearinghouseQuerySheet: View {

    /// Driver whose consent is being recorded.
    let driverId: Int
    /// Optional human label for the driver, shown in the header so the
    /// officer is sure who they're filing for. Falls back to the id.
    var driverName: String? = nil

    init(driverId: Int, driverName: String? = nil) {
        self.driverId = driverId
        self.driverName = driverName
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    // MARK: Query type

    private enum QueryType: String, CaseIterable, Identifiable {
        case preEmployment = "pre_employment"
        case annual
        case limited

        var id: String { rawValue }

        var title: String {
            switch self {
            case .preEmployment: return "Pre-employment"
            case .annual:        return "Annual"
            case .limited:       return "Limited"
            }
        }

        var detail: String {
            switch self {
            case .preEmployment:
                return "Full query — required before the driver performs any safety-sensitive function. Returns all violation data on file."
            case .annual:
                return "Limited annual query — confirms whether any new information exists in the driver's record over the prior 12 months."
            case .limited:
                return "One-off limited query — checks only for the presence of new information; does not return the underlying records."
            }
        }
    }

    // MARK: State

    @State private var queryType: QueryType = .preEmployment
    @State private var consentGiven = false
    @State private var submitting = false
    @State private var error: String? = nil
    @State private var result: RegistrationAPI.AttachResult? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    queryTypeCard
                    consentCard
                    if let error { errorCard(error) }
                    if let result { resultCard(result) }
                    submitButton
                    Color.clear.frame(height: Space.s6)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Clearinghouse consent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .environment(\.palette, palette)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FMCSA · DRUG & ALCOHOL CLEARINGHOUSE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Record query consent")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(driverName.map { "Driver: \($0)" } ?? "Driver #\(driverId)")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Query type picker

    private var queryTypeCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("QUERY TYPE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            Picker("Query type", selection: $queryType) {
                ForEach(QueryType.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .disabled(submitting || result != nil)

            Text(queryType.detail)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard()
    }

    // MARK: Consent toggle

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Toggle(isOn: $consentGiven) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Driver consent obtained")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("I confirm the driver has provided electronic consent for this \(queryType.title.lowercased()) Clearinghouse query, per 49 CFR §382.701.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Brand.success)
            .disabled(submitting || result != nil)

            if !consentGiven {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.warning)
                    Text("Consent is required before a query can be filed.")
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                }
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard()
    }

    // MARK: Error

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintDanger)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Result (honest)

    /// Maps the server's raw status string to a strictly honest presentation.
    /// We refuse to render a green "cleared" state unless the server actually
    /// confirms the consent is on file. Anything ambiguous reads as a neutral
    /// pending / provider-unavailable state; anything indicating prohibition
    /// reads as a blocking red state.
    private enum Verdict {
        case onFile          // server confirmed the consent is filed
        case prohibited      // driver is prohibited → dispatch blocked
        case notEnrolled     // driver not enrolled in the Clearinghouse
        case providerDown    // provider unavailable → manual review
        case pending         // pending / unknown → manual review

        var title: String {
            switch self {
            case .onFile:       return "Consent on file"
            case .prohibited:   return "PROHIBITED — dispatch blocked"
            case .notEnrolled:  return "Driver not enrolled"
            case .providerDown: return "Provider unavailable — manual review"
            case .pending:      return "Pending review"
            }
        }

        var color: Color {
            switch self {
            case .onFile:                       return Brand.success
            case .prohibited:                   return Brand.danger
            case .notEnrolled, .providerDown,
                 .pending:                      return Brand.warning
            }
        }

        var icon: String {
            switch self {
            case .onFile:       return "checkmark.seal.fill"
            case .prohibited:   return "hand.raised.fill"
            case .notEnrolled:  return "person.fill.questionmark"
            case .providerDown: return "wifi.exclamationmark"
            case .pending:      return "clock.fill"
            }
        }

        var detail: String {
            switch self {
            case .onFile:
                return "The query consent is recorded with FMCSA. No prohibitions were returned at filing time."
            case .prohibited:
                return "FMCSA reports this driver is in prohibited status. They may NOT perform safety-sensitive functions. Dispatch is blocked until a negative return-to-duty test and follow-up plan are on file."
            case .notEnrolled:
                return "This driver has no Clearinghouse enrollment on record. They must register and grant consent before a query can return data."
            case .providerDown:
                return "The Clearinghouse query provider did not respond. The consent is recorded; a compliance officer must complete the query manually before dispatch."
            case .pending:
                return "Consent recorded. The query result is not yet available — a compliance officer must verify the return before this driver is cleared to dispatch."
            }
        }
    }

    private func verdict(for result: RegistrationAPI.AttachResult) -> Verdict {
        let raw = (result.status ?? "").lowercased()

        // Prohibition is the hard stop — check it first regardless of other
        // tokens in the status string.
        if raw.contains("prohibit") {
            return .prohibited
        }
        if raw.contains("not_enrolled") || raw.contains("unenrolled") || raw.contains("no_enrollment") {
            return .notEnrolled
        }
        if raw.contains("provider_unavailable") || raw.contains("unavailable") || raw.contains("provider_down") {
            return .providerDown
        }
        // Only treat as confirmed when the server explicitly says so.
        if raw == "verified" || raw == "clear" || raw == "consent_filed"
            || raw == "consent_on_file" || raw == "registered"
            || raw.hasPrefix("registered_") || raw == "filed" || raw == "active" {
            return .onFile
        }
        // Empty / "pending" / "unknown" / anything else → neutral pending.
        return .pending
    }

    @ViewBuilder
    private func resultCard(_ result: RegistrationAPI.AttachResult) -> some View {
        let v = verdict(for: result)
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: v.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(v.color)
                Text(v.title)
                    .font(EType.title)
                    .foregroundStyle(v.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(v.detail)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Verbatim server status so the officer always sees the raw
            // truth, never just our interpretation of it.
            HStack(spacing: 6) {
                Text("SERVER STATUS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text((result.status?.isEmpty == false ? result.status! : "null"))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            if let expires = result.expiresAt, !expires.isEmpty {
                HStack(spacing: 6) {
                    Text("CONSENT EXPIRES")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    Text(expires)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if let warnings = result.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Brand.warning)
                                .padding(.top, 2)
                            Text(w)
                                .font(EType.caption)
                                .foregroundStyle(Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v.color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(v.color.opacity(0.5), lineWidth: v == .prohibited ? 1.75 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Submit

    @ViewBuilder
    private var submitButton: some View {
        if result == nil {
            CTAButton(
                title: submitting ? "Filing consent…" : "File Clearinghouse consent",
                action: { Task { await submit() } },
                trailingIcon: submitting ? nil : "arrow.right",
                isLoading: submitting
            )
            .opacity(consentGiven ? 1.0 : 0.5)
            .disabled(!consentGiven || submitting)
            .animation(.easeOut(duration: 0.15), value: consentGiven)
        }
    }

    private func submit() async {
        guard consentGiven, !submitting else { return }
        submitting = true
        error = nil
        result = nil
        do {
            let r = try await EusoTripAPI.shared.registration.attachClearinghouseConsent(
                driverId: driverId,
                queryType: queryType.rawValue,
                consentGiven: true
            )
            result = r
        } catch let apiErr as LocalizedError {
            error = apiErr.errorDescription ?? "Couldn't file Clearinghouse consent."
        } catch {
            self.error = error.localizedDescription
        }
        submitting = false
    }
}

#Preview("1104 · Clearinghouse consent · Night") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            ClearinghouseQuerySheet(driverId: 4821, driverName: "M. Okafor")
                .environment(\.palette, Theme.dark)
                .preferredColorScheme(.dark)
        }
}

#Preview("1104 · Clearinghouse consent · Afternoon") {
    Color.white
        .sheet(isPresented: .constant(true)) {
            ClearinghouseQuerySheet(driverId: 4821, driverName: "M. Okafor")
                .environment(\.palette, Theme.light)
                .preferredColorScheme(.light)
        }
}
