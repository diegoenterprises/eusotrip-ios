//
//  1103_InsuranceCOIViewer.swift
//  EusoTrip — Compliance · Insurance COI capture + lapse banner (RIOS §11, brick 1103).
//
//  Captures a Certificate of Insurance (carrier / policy number / coverage
//  amount / expiry) and attaches it to the company's RIOS compliance file via
//  `registration.attachInsuranceCOI`, then subscribes the entity to the
//  `INSURANCE_COI` monitoring signal so we get told when it's about to lapse.
//
//  HONEST STATES (RIOS doctrine):
//    - The attach result `status` is rendered verbatim. Only a literal
//      "verified" / "active" status paints green; "pending",
//      "provider_unavailable", or a null/blank status paints the neutral
//      Brand.warning "pending review / manual review" treatment — never a
//      fabricated success.
//    - A Brand.danger lapse banner fires when the entered expiry is within
//      30 days (or already past), independent of any server response.
//    - Thrown errors surface their LocalizedError.errorDescription verbatim.
//
//  Push-nav mandate: this is a PUSHED full screen (Shell), not a slide-up.
//
//  Bottom nav frozen per doctrine — content only.
//

import SwiftUI

// MARK: - Screen (pushed full screen)

struct InsuranceCOIViewer: View {
    let theme: Theme.Palette
    /// Numeric company id for the attach. When the caller already knows it
    /// (e.g. a vetting flow on another company) it's passed in; otherwise the
    /// body resolves it from the signed-in session.
    var companyId: Int? = nil

    var body: some View {
        Shell(theme: theme) {
            InsuranceCOIBody(injectedCompanyId: companyId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",                        isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",                isCurrent: false)],
                trailing: [NavSlot(label: "Audits", systemImage: "doc.text.magnifyingglass",     isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person",                       isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct InsuranceCOIBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    let injectedCompanyId: Int?

    // Form state
    @State private var carrier: String = ""
    @State private var policyNumber: String = ""
    @State private var coverageAmount: String = ""    // raw USD digits, parsed to Double
    @State private var country: String = "US"
    /// Expiry date. Defaults to one year out so the picker opens on a sane
    /// value; the user adjusts it to the certificate's real expiry.
    @State private var expiresAt: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasSetExpiry: Bool = false

    // Submit state
    @State private var submitting = false
    @State private var result: RegistrationAPI.AttachResult?
    @State private var subscription: MonitoringAPI.Subscription?
    @State private var subscribeWarning: String? = nil
    @State private var submitError: String? = nil

    private var resolvedCompanyId: Int? {
        injectedCompanyId ?? session.user?.companyId.flatMap { Int($0) }
    }

    /// Lapse fires when the entered expiry is within 30 days OR already past.
    private var lapseDaysRemaining: Int {
        let secs = expiresAt.timeIntervalSinceNow
        return Int(floor(secs / 86_400))
    }
    private var lapseSoon: Bool { hasSetExpiry && lapseDaysRemaining <= 30 }
    private var lapsed: Bool { hasSetExpiry && lapseDaysRemaining < 0 }

    private var canSubmit: Bool {
        !submitting
            && resolvedCompanyId != nil
            && !carrier.trimmingCharacters(in: .whitespaces).isEmpty
            && !policyNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if lapseSoon { lapseBanner }

                captureCard

                if resolvedCompanyId == nil { missingCompanyCard }
                if let err = submitError { errorCard(err) }
                if let r = result { resultCard(r) }

                submitButton

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · INSURANCE COI")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Certificate of Insurance")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Capture the carrier's COI and attach it to the company file. We'll watch the expiry and alert before it lapses.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: lapse banner

    private var lapseBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: lapsed ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lapsed ? "Coverage has lapsed" : "Coverage lapsing soon")
                        .font(EType.bodyStrong)
                        .foregroundStyle(Brand.danger)
                    Text(lapseMessage)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var lapseMessage: String {
        if lapsed {
            let days = abs(lapseDaysRemaining)
            return "This certificate expired \(days) day\(days == 1 ? "" : "s") ago. The company cannot transact until a current COI is on file."
        }
        let days = max(lapseDaysRemaining, 0)
        return "Expires in \(days) day\(days == 1 ? "" : "s") (\(Self.dateFormatter.string(from: expiresAt))). Capture a renewal before it lapses."
    }

    // MARK: capture card

    private var captureCard: some View {
        LifecycleCard {
            LifecycleSection(label: "POLICY DETAILS", icon: "doc.text.fill")

            GlassField(label: "Carrier / Insurer",
                       placeholder: "e.g. Progressive Commercial",
                       icon: "building.2",
                       text: $carrier,
                       autocapitalization: .words)

            GlassField(label: "Policy number",
                       placeholder: "POL-000000",
                       icon: "number",
                       text: $policyNumber,
                       autocapitalization: .characters)

            GlassField(label: "Coverage amount (USD)",
                       placeholder: "1,000,000",
                       icon: "dollarsign.circle",
                       text: $coverageAmount,
                       keyboardType: .numberPad)

            GlassField(label: "Country",
                       placeholder: "US",
                       icon: "globe",
                       text: $country,
                       autocapitalization: .characters)

            // Expiry — drives the lapse banner. Marking hasSetExpiry on first
            // touch so we don't flash a lapse warning against the default
            // one-year placeholder before the officer has confirmed a date.
            VStack(alignment: .leading, spacing: 6) {
                Text("EXPIRES")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                DatePicker("",
                           selection: $expiresAt,
                           displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Brand.blue)
                    .onChange(of: expiresAt) { _, _ in hasSetExpiry = true }
            }
            .padding(.top, 2)
        }
    }

    // MARK: missing-company card

    private var missingCompanyCard: some View {
        LifecycleCard(accentWarning: true) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No company on file")
                        .font(EType.bodyStrong).foregroundStyle(Brand.warning)
                    Text("This account isn't linked to a numeric company id, so the COI can't be attached. Complete company registration first.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: error card

    private func errorCard(_ message: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text(message)
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: result card (honest status)

    private func resultCard(_ r: RegistrationAPI.AttachResult) -> some View {
        let state = CoiStatusState(r.status)
        return LifecycleCard(accentWarning: state == .pending, accentGradient: state == .verified) {
            VStack(alignment: .leading, spacing: Space.s2) {
                LifecycleSection(label: "ATTACH RESULT", icon: "checkmark.shield.fill")

                HStack(spacing: 8) {
                    StatusPill(text: state.pillText(rawStatus: r.status), kind: state.pillKind)
                    Spacer(minLength: 0)
                    if let id = r.id {
                        Text("COI #\(id)")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                Text(state.explanation)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let exp = r.expiresAt, !exp.isEmpty {
                    LifecycleRow(label: "Recorded expiry", value: Self.shortDate(exp))
                }

                // Server-side warnings rendered verbatim.
                if let warnings = r.warnings, !warnings.isEmpty {
                    ForEach(warnings, id: \.self) { w in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                            Text(w)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Monitoring subscription outcome — also honest.
                Divider().overlay(palette.borderFaint)
                monitoringRow
            }
        }
    }

    @ViewBuilder
    private var monitoringRow: some View {
        if let sub = subscription, sub.active == true {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lapse monitoring active")
                        .font(EType.caption).foregroundStyle(palette.textPrimary)
                    if let due = sub.nextCheckDue, !due.isEmpty {
                        Text("Next check \(Self.shortDate(due))")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        } else if let warn = subscribeWarning {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("COI attached, but lapse monitoring couldn't be enabled: \(warn). Re-check from the monitoring console.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else if subscription != nil {
            // Subscription returned but not active — render the honest neutral state.
            HStack(spacing: 6) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("Lapse monitoring pending — the subscription is registered but not yet active.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: submit

    private var submitButton: some View {
        CTAButton(
            title: submitting ? "Attaching…" : "Attach COI",
            action: { Task { await submit() } },
            trailingIcon: submitting ? nil : "checkmark.shield",
            isLoading: submitting
        )
        .opacity(canSubmit ? 1 : 0.5)
        .disabled(!canSubmit)
    }

    private func submit() async {
        guard let companyId = resolvedCompanyId else { return }
        submitting = true
        submitError = nil
        result = nil
        subscription = nil
        subscribeWarning = nil

        // Parse coverage amount — strip any commas/currency the user typed.
        let cleanedCoverage = coverageAmount
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .joined()
        let coverage = Double(cleanedCoverage)

        // ISO-8601 date (date-only) for the attach + lapse signal.
        let isoExpiry = hasSetExpiry ? Self.isoDate(expiresAt) : nil

        do {
            let r = try await EusoTripAPI.shared.registration.attachInsuranceCOI(
                companyId: companyId,
                country: country.trimmingCharacters(in: .whitespaces).isEmpty ? "US" : country.trimmingCharacters(in: .whitespaces),
                carrier: carrier.trimmingCharacters(in: .whitespaces),
                policyNumber: policyNumber.trimmingCharacters(in: .whitespaces),
                coverageAmount: coverage,
                expiresAt: isoExpiry
            )
            result = r

            // Subscribe the company to the INSURANCE_COI lapse signal. A
            // failure here doesn't undo the attach, so we surface it as a
            // non-fatal warning rather than throwing the whole flow away.
            do {
                subscription = try await EusoTripAPI.shared.monitoring.subscribeEntity(
                    entityId: companyId,
                    entityType: "company",
                    signal: "INSURANCE_COI",
                    intervalDays: 1
                )
            } catch {
                subscribeWarning = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription ?? "Couldn't attach the COI. \(error)"
        }

        submitting = false
    }

    // MARK: date helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Date-only ISO string (yyyy-MM-dd) for the server payload.
    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Render a server ISO timestamp/date down to yyyy-MM-dd for display.
    private static func shortDate(_ iso: String) -> String {
        let withTime = ISO8601DateFormatter()
        withTime.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withTime.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        // Server may already send a bare yyyy-MM-dd — pass it through.
        return iso
    }
}

// MARK: - Honest status mapping

/// Collapses the verbatim server `status` into one of three honest UI states.
/// Only an explicit verified/active status earns the green treatment; anything
/// else (pending, provider_unavailable, null, unknown) renders as a neutral
/// "review" state — never a fabricated success.
private enum CoiStatusState {
    case verified
    case pending
    case rejected

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "verified", "active", "clear", "valid", "approved":
            self = .verified
        case "rejected", "failed", "denied", "invalid", "blocked":
            self = .rejected
        default:
            // "pending", "provider_unavailable", "needs_review", "", nil → review.
            self = .pending
        }
    }

    var pillKind: StatusPill.Kind {
        switch self {
        case .verified: return .success
        case .pending:  return .warning
        case .rejected: return .danger
        }
    }

    func pillText(rawStatus: String?) -> String {
        let raw = (rawStatus ?? "").trimmingCharacters(in: .whitespaces)
        switch self {
        case .verified:
            return raw.isEmpty ? "Verified" : raw.replacingOccurrences(of: "_", with: " ")
        case .rejected:
            return raw.isEmpty ? "Rejected" : raw.replacingOccurrences(of: "_", with: " ")
        case .pending:
            // Surface the real server word when present so it's never hidden.
            return raw.isEmpty ? "Pending review" : raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    var explanation: String {
        switch self {
        case .verified:
            return "Certificate accepted and attached to the company compliance file."
        case .pending:
            return "Submitted for verification. The provider hasn't returned a confirmed result yet — this stays in manual review until it clears. Not yet counted as active coverage."
        case .rejected:
            return "The provider could not validate this certificate. Review the policy details and re-submit, or escalate for manual review."
        }
    }
}

// MARK: - Previews

#Preview("1103 · Insurance COI · Night") {
    InsuranceCOIViewer(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("1103 · Insurance COI · Afternoon") {
    InsuranceCOIViewer(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
