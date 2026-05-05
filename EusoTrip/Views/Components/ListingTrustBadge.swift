//
//  ListingTrustBadge.swift
//  EusoTrip — Public-facing trust chip for every load listing.
//
//  Renders the verdict from `fraud.getLoadTrust(loadId)` as a chip:
//    • verified         — green checkmark, "Verified poster".
//    • review_pending   — amber clock, "Review pending".
//    • flagged          — magenta shield, "Listing flagged".
//
//  Tap → presents `ListingTrustExplainSheet` with the human-readable
//  reason + signals + an inline "Report this listing" CTA. Drivers
//  see one tap-target on every load card; bidders see the full
//  breakdown before they commit.
//

import SwiftUI

/// Public-facing trust verdict for a load. Mirrors the server-side
/// enum so wire-format decoding is direct.
enum ListingTrustVerdict: String, Decodable {
    case verified
    case reviewPending = "review_pending"
    case flagged
}

/// Decodable shape returned by `fraud.getLoadTrust`. Optional fields
/// tolerate older server builds where the proc isn't deployed yet —
/// the badge renders as `review_pending` with a "trust check
/// unavailable" reason in that case.
struct ListingTrust: Decodable, Hashable {
    let score: Double
    let verdict: ListingTrustVerdict
    let riskSignals: [String]
    let reason: String
}

/// Small chip — fits inline next to the load number, lane, or
/// rate. Tap opens the explain sheet. Compact form (default)
/// shows just the icon + one-word verdict; expanded shows the
/// full reason line.
struct ListingTrustBadge: View {
    let trust: ListingTrust?
    var compact: Bool = true
    var loadId: String? = nil
    @Environment(\.palette) private var palette
    @State private var showExplain: Bool = false

    var body: some View {
        Button {
            // Only present the explain sheet when we actually have
            // a verdict to explain — drivers shouldn't get an empty
            // sheet during the brief loading window before the
            // first fetch resolves.
            if trust != nil { showExplain = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                if !compact, let reason = trust?.reason, !reason.isEmpty {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.6))
                    Text(reason)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tintColor))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(trust?.reason ?? "")
        .sheet(isPresented: $showExplain) {
            if let t = trust {
                ListingTrustExplainSheet(trust: t, loadId: loadId)
                    .environment(\.palette, palette)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var verdict: ListingTrustVerdict { trust?.verdict ?? .reviewPending }

    private var icon: String {
        switch verdict {
        case .verified:       return "checkmark.shield.fill"
        case .reviewPending:  return "clock.badge.questionmark"
        case .flagged:        return "exclamationmark.shield.fill"
        }
    }
    private var label: String {
        switch verdict {
        case .verified:       return "VERIFIED"
        case .reviewPending:  return "REVIEW"
        case .flagged:        return "FLAGGED"
        }
    }
    private var tintColor: Color {
        switch verdict {
        case .verified:      return Color(red: 0.10, green: 0.65, blue: 0.40)
        case .reviewPending: return Color(red: 0.90, green: 0.65, blue: 0.10)
        case .flagged:       return Color(red: 0.74, green: 0.00, blue: 1.00)
        }
    }
}

// MARK: - Explain sheet

/// Bottom sheet presented when a driver taps the trust chip. Shows
/// the verdict, the reason, the signal list (for transparency), and
/// a "Report this listing" CTA that opens the report flow.
struct ListingTrustExplainSheet: View {
    let trust: ListingTrust
    let loadId: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var showReportSheet: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                reasonCard
                signalsCard
                if loadId != nil {
                    reportCTA
                }
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .sheet(isPresented: $showReportSheet) {
            if let loadId {
                ReportListingSheet(loadId: loadId) {
                    showReportSheet = false
                    dismiss()
                }
                .environment(\.palette, palette)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LISTING TRUST")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(headerTitle)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var headerTitle: String {
        switch trust.verdict {
        case .verified:      return "Verified poster"
        case .reviewPending: return "Review pending"
        case .flagged:       return "Listing flagged"
        }
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trust.reason)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if trust.score > 0 {
                Text("Trust score \(Int(trust.score)) / 100")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var signalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT WE CHECKED")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if trust.riskSignals.isEmpty {
                Text("No risk signals on this listing.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(trust.riskSignals, id: \.self) { signal in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 6)
                        Text(humanize(signal))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var reportCTA: some View {
        Button {
            showReportSheet = true
        } label: {
            HStack {
                Image(systemName: "flag.fill")
                Text("Report this listing")
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.74, green: 0.00, blue: 1.00))
            )
        }
        .buttonStyle(.plain)
    }

    /// Stable signal codes are upper-snake-case for admin filtering.
    /// This function turns them into the human-readable phrase a
    /// driver actually understands.
    private func humanize(_ signal: String) -> String {
        if signal.hasPrefix("USER_REPORT:") {
            return "Reported by another user — \(signal.replacingOccurrences(of: "USER_REPORT:", with: "").lowercased().replacingOccurrences(of: "_", with: " "))."
        }
        if signal.hasPrefix("ADMIN_") {
            return "Admin override applied."
        }
        switch signal {
        case "UNVERIFIED_ACCOUNT":             return "Poster has not completed account verification."
        case "ACCOUNT_BRAND_NEW":              return "Poster's account is less than a week old."
        case "ACCOUNT_NEW":                    return "Poster's account is new (under 30 days)."
        case "FIRST_LOAD_POSTED":              return "First load this poster has put on the platform."
        case "FMCSA_INACTIVE_OR_REVOKED":      return "Poster's FMCSA authority is inactive or revoked."
        case "RATE_UNREALISTICALLY_HIGH":      return "Rate is far above market median for this lane."
        case "RATE_ABOVE_MARKET":              return "Rate is moderately above market median."
        case "RATE_UNREALISTICALLY_LOW":       return "Rate is far below market median."
        case "OFF_PLATFORM_CONTACT_REDIRECT":  return "Listing asks you to contact off-platform."
        case "SUSPICIOUS_DOMAIN_REFERENCE":    return "Listing references a suspicious domain."
        case "MISSING_LANE":                   return "Listing is missing origin or destination."
        case "NOT_SCORED":                     return "Listing predates the trust scoring layer."
        default:                               return signal.lowercased().replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Report sheet

/// Form a driver fills to report a suspect listing. Posts to
/// `fraud.reportLoad`; on success calls `onClose` so the parent
/// sheet can dismiss too.
struct ReportListingSheet: View {
    let loadId: String
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @State private var reason: ReportReason = .offPlatformContact
    @State private var detail: String = ""
    @State private var sending: Bool = false
    @State private var error: String? = nil

    enum ReportReason: String, CaseIterable, Identifiable {
        case offPlatformContact = "off_platform_contact"
        case rateTooGood        = "rate_too_good"
        case rateBelowMarket    = "rate_below_market"
        case fakeAuthority      = "fake_authority"
        case doubleBrokering    = "double_brokering"
        case phishingPayload    = "phishing_payload"
        case duplicateListing   = "duplicate_listing"
        case other              = "other"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .offPlatformContact: return "Wants me to contact off-platform"
            case .rateTooGood:        return "Rate is too good to be true"
            case .rateBelowMarket:    return "Rate is well below market"
            case .fakeAuthority:      return "Looks like fake MC/DOT authority"
            case .doubleBrokering:    return "Looks like double-brokering"
            case .phishingPayload:    return "Phishing payload (links/attachments)"
            case .duplicateListing:   return "Duplicate of another listing"
            case .other:              return "Other"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                reasonPicker
                detailField
                if let error {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                }
                submitCTA
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REPORT THIS LISTING")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("Tell us what's off")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Reports go straight to the platform safety queue. We block reposting from the same source while we review.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonPicker: some View {
        VStack(spacing: 6) {
            ForEach(ReportReason.allCases) { r in
                Button {
                    reason = r
                } label: {
                    HStack {
                        Image(systemName: reason == r ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(reason == r
                                ? Color(red: 0.74, green: 0.00, blue: 1.00)
                                : palette.textTertiary)
                        Text(r.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(12)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var detailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DETAIL (OPTIONAL)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $detail)
                .font(.system(size: 13))
                .foregroundStyle(palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 100)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var submitCTA: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Reporting…" : "Submit report")
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.74, green: 0.00, blue: 1.00))
            )
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .opacity(sending ? 0.7 : 1.0)
    }

    private func submit() async {
        sending = true; error = nil
        struct In: Encodable { let loadId: String; let reason: String; let detail: String? }
        struct Out: Decodable { let accepted: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "fraud.reportLoad",
                input: In(loadId: loadId,
                          reason: reason.rawValue,
                          detail: detail.isEmpty ? nil : detail)
            )
            sending = false
            onClose()
        } catch {
            sending = false
            self.error = (error as? LocalizedError)?.errorDescription ?? "Could not submit. Try again."
        }
    }
}
