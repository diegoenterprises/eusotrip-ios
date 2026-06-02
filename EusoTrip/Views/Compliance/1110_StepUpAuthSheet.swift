//
//  1110_StepUpAuthSheet.swift
//  EusoTrip — Compliance · Step-up authentication for high-risk changes.
//
//  RIOS spec §2 / §12 — out-of-band step-up authentication gating
//  bank-account, payout-destination, and corporate-officer changes.
//  This is a .sheet content View (capture/confirm precedent — the
//  1100-1110 range are acceptable as sheets per the push-nav mandate;
//  only the 1111 wizard is a pushed Shell screen).
//
//  Flow (two steps, NEVER an instant apply):
//    Step 1 · Collect the change fields for the selected kind
//             (bank / payout / officer) → requestBankChange /
//             requestPayoutChange / requestOfficerChange. The server
//             returns a Challenge: a requestId, a 24h cooldown that
//             must elapse, and an out-of-band code delivered to the
//             account's verified contact (we never show the code here).
//    Step 2 · Enter the out-of-band code → confirmStepUp(requestId,code).
//             The result is rendered HONESTLY: the change reads
//             "applied" ONLY when verified==true AND applied==true.
//
//  CRITICAL UX HONESTY (spec §12):
//    - The 24h cooldown is shown as a live countdown. The change is NOT
//      applied while the cooldown is running, regardless of code entry.
//    - If simSwapClean == false OR == null (no provider attestation),
//      we surface a Brand.danger "SIM-swap risk — review required"
//      banner and make explicit the change will NOT auto-apply.
//    - We never present an instant apply. confirmStepUp returning
//      verified==true but applied!=true reads as "verified — pending
//      apply", never as done.
//

import SwiftUI

// MARK: - StepUpAuthSheet

struct StepUpAuthSheet: View {

    /// Which high-risk change this step-up gates. Drives the field set
    /// in step 1 and the request endpoint.
    enum ChangeKind: String, CaseIterable, Identifiable {
        case bank
        case payout
        case officer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bank:    return "Change bank account"
            case .payout:  return "Change payout destination"
            case .officer: return "Change corporate officer"
            }
        }
        var eyebrow: String {
            switch self {
            case .bank:    return "COMPLIANCE · BANK CHANGE"
            case .payout:  return "COMPLIANCE · PAYOUT CHANGE"
            case .officer: return "COMPLIANCE · OFFICER CHANGE"
            }
        }
        var icon: String {
            switch self {
            case .bank:    return "building.columns.fill"
            case .payout:  return "arrow.left.arrow.right.circle.fill"
            case .officer: return "person.crop.circle.badge.checkmark"
            }
        }
        var blurb: String {
            switch self {
            case .bank:
                return "Changing the settlement bank account is a high-risk action. We send a one-time code out-of-band and hold the change behind a 24-hour cooldown."
            case .payout:
                return "Changing where payouts are sent is a high-risk action. We send a one-time code out-of-band and hold the change behind a 24-hour cooldown."
            case .officer:
                return "Changing a corporate officer is a high-risk action. We send a one-time code out-of-band and hold the change behind a 24-hour cooldown."
            }
        }
    }

    /// The change being authorized. Defaults to .bank so the sheet can
    /// be presented without a kind selection where the host already
    /// knows the context.
    var kind: ChangeKind = .bank

    /// Company under change (officer changes). When nil, the API resolves
    /// the caller's company server-side.
    var companyId: Int? = nil

    /// Fired once when the operator dismisses after a verdict, so the host
    /// (Me / officer queue) can re-read state. Passes the final confirm
    /// status string verbatim ("APPLIED", "VERIFIED", "PENDING", etc.),
    /// or "incomplete" when dismissed before a confirm verdict.
    var onComplete: (String) -> Void = { _ in }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Step machine

    private enum Step { case collect, challenge, verdict }
    @State private var step: Step = .collect

    // MARK: Bank fields
    @State private var accountHolderName = ""
    @State private var bankName = ""
    @State private var routingNumber = ""
    @State private var accountNumberLast4 = ""

    // MARK: Payout fields
    @State private var payoutMethod = ""
    @State private var destinationRef = ""
    @State private var destinationLast4 = ""

    // MARK: Officer fields
    @State private var officerName = ""
    @State private var officerTitle = ""
    @State private var officerAction = "add"   // add | remove | replace

    // MARK: Shared
    @State private var reason = ""

    // MARK: Challenge + confirm state
    @State private var challenge: StepUpAuthAPI.Challenge? = nil
    @State private var confirmResult: StepUpAuthAPI.ConfirmResult? = nil
    @State private var code = ""

    @State private var requesting = false
    @State private var confirming = false
    @State private var error: String? = nil

    /// Drives the live cooldown countdown tick.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let officerActions: [(String, String)] = [
        ("add", "Add officer"),
        ("remove", "Remove officer"),
        ("replace", "Replace officer"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.bgPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if let err = error { errorBanner(err) }

                    switch step {
                    case .collect:   collectSection
                    case .challenge: challengeSection
                    case .verdict:   verdictSection
                    }

                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s5)
            }

            footer
        }
        .environment(\.palette, palette)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(kind.eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 0)
                Button {
                    onComplete(confirmStatusForDismiss)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(palette.bgCardSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(kind.title)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)

            Text(kind.blurb)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            stepIndicator
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepDot(1, "Details",  active: step == .collect,   done: step != .collect)
            connector
            stepDot(2, "Code",     active: step == .challenge, done: step == .verdict)
            connector
            stepDot(3, "Result",   active: step == .verdict,   done: false)
        }
        .padding(.top, 2)
    }

    private var connector: some View {
        Rectangle()
            .fill(palette.borderSoft)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    private func stepDot(_ n: Int, _ label: String, active: Bool, done: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done
                          ? AnyShapeStyle(Brand.success)
                          : (active ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft)))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(active ? .white : palette.textTertiary)
                }
            }
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(active || done ? palette.textPrimary : palette.textTertiary)
        }
    }

    // MARK: - Step 1 · Collect change fields

    private var collectSection: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            switch kind {
            case .bank:    bankFields
            case .payout:  payoutFields
            case .officer: officerFields
            }

            GlassField(label: "Reason for change",
                       placeholder: "e.g. corrected routing number",
                       icon: "text.bubble",
                       text: $reason,
                       autocapitalization: .sentences)

            // Make the gate explicit before they request.
            infoNote("Requesting sends a one-time code to your verified contact and starts a 24-hour cooldown. The change is not applied until the cooldown elapses and the code is confirmed.")
        }
    }

    private var bankFields: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            GlassField(label: "Account holder name",
                       placeholder: "Legal name on the account",
                       icon: "person.fill",
                       text: $accountHolderName,
                       autocapitalization: .words)
            GlassField(label: "Bank name",
                       placeholder: "e.g. First National",
                       icon: "building.columns.fill",
                       text: $bankName,
                       autocapitalization: .words)
            GlassField(label: "Routing number",
                       placeholder: "9-digit ABA routing number",
                       icon: "number",
                       text: $routingNumber,
                       keyboardType: .numberPad)
            GlassField(label: "Account number · last 4",
                       placeholder: "Last 4 digits only",
                       icon: "lock.fill",
                       text: $accountNumberLast4,
                       keyboardType: .numberPad)
        }
    }

    private var payoutFields: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            GlassField(label: "Payout method",
                       placeholder: "e.g. ACH, wire, card",
                       icon: "creditcard.fill",
                       text: $payoutMethod,
                       autocapitalization: .words)
            GlassField(label: "Destination reference",
                       placeholder: "Token or account reference",
                       icon: "link",
                       text: $destinationRef)
            GlassField(label: "Destination · last 4",
                       placeholder: "Last 4 digits only",
                       icon: "lock.fill",
                       text: $destinationLast4,
                       keyboardType: .numberPad)
        }
    }

    private var officerFields: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ACTION")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 8) {
                    ForEach(officerActions, id: \.0) { opt in
                        let selected = officerAction == opt.0
                        Button { officerAction = opt.0 } label: {
                            Text(opt.1)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(selected ? .white : palette.textSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selected
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            GlassField(label: "Officer name",
                       placeholder: "Legal name",
                       icon: "person.fill",
                       text: $officerName,
                       autocapitalization: .words)
            GlassField(label: "Officer title",
                       placeholder: "e.g. CFO, Managing Member",
                       icon: "briefcase.fill",
                       text: $officerTitle,
                       autocapitalization: .words)
        }
    }

    // MARK: - Step 2 · Challenge (cooldown + OOB code entry)

    private var challengeSection: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // SIM-swap banner — danger when not cleanly attested.
            simSwapBanner

            // 24h cooldown countdown.
            cooldownCard

            // OOB delivery state.
            oobCard

            // Code entry.
            VStack(alignment: .leading, spacing: Space.s2) {
                GlassField(label: "Out-of-band code",
                           placeholder: "Enter the code we sent",
                           icon: "key.fill",
                           text: $code,
                           keyboardType: .numberPad)
                Text("We sent a one-time code to your verified contact. We never display it here.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let rec = challenge?.recommendation, !rec.isEmpty {
                infoNote(rec)
            }
        }
    }

    /// SIM-swap risk. simSwapClean == true is the ONLY clean state.
    /// false → confirmed risk; null → no provider attestation, treat as risk.
    private var simSwapBanner: some View {
        let clean = challenge?.simSwapClean
        return Group {
            if clean == true {
                statusRow(icon: "checkmark.shield.fill",
                          color: Brand.success,
                          title: "SIM-swap check clean",
                          body: "No recent SIM port detected on the verified number.")
            } else {
                statusRow(icon: "exclamationmark.triangle.fill",
                          color: Brand.danger,
                          title: "SIM-swap risk — review required",
                          body: clean == false
                            ? "A recent SIM port was detected on the verified number. This change will NOT auto-apply and is routed to manual review."
                            : "No SIM-swap attestation was returned. This change will NOT auto-apply and is routed to manual review.")
            }
        }
    }

    private var cooldownCard: some View {
        let remaining = cooldownRemaining
        let active = remaining > 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: active ? "hourglass" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(active ? Brand.warning : Brand.success)
                Text(active ? "24-HOUR COOLDOWN ACTIVE" : "COOLDOWN ELAPSED")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(active ? Brand.warning : Brand.success)
                Spacer(minLength: 0)
            }
            if active {
                Text(formatCountdown(remaining))
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("The change is held until the cooldown elapses. Confirming the code now records your authorization; it cannot apply early.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The cooldown has elapsed. Confirm the out-of-band code to authorize the change.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((active ? Brand.warning : Brand.success).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder((active ? Brand.warning : Brand.success).opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var oobCard: some View {
        let delivered = challenge?.oobDelivered
        return Group {
            if delivered == true {
                statusRow(icon: "paperplane.fill",
                          color: Brand.info,
                          title: "Code sent out-of-band",
                          body: "A one-time code was delivered to your verified contact.")
            } else {
                statusRow(icon: "clock.fill",
                          color: Brand.warning,
                          title: "Code delivery pending",
                          body: "We could not confirm out-of-band delivery yet. If you don't receive a code, route to manual review.")
            }
        }
    }

    // MARK: - Step 3 · Verdict (honest confirm result)

    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            verdictHeadline

            if let r = confirmResult {
                verdictDetailCard(r)
            }

            // Keep the SIM-swap context visible at verdict time so the
            // operator never reads "verified" as "applied" when risk
            // forced a hold.
            if challenge?.simSwapClean != true {
                simSwapBanner
            }
        }
    }

    private var verdictHeadline: some View {
        let s = verdictState
        return HStack(spacing: Space.s3) {
            Image(systemName: s.icon)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(s.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(s.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(s.color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(s.color.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func verdictDetailCard(_ r: StepUpAuthAPI.ConfirmResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Text("STEP-UP RESULT")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                StatusPill(text: verdictState.pillText, kind: verdictState.pillKind)
            }
            detailRow("Code verified", boolText(r.verified))
            detailRow("Change applied", boolText(r.applied))
            detailRow("Status", (r.status ?? "—").capitalized)
            if let req = r.requestId { detailRow("Request", "#\(req)") }
            if let reason = r.reason, !reason.isEmpty { detailRow("Reason", reason) }
            if let rec = r.recommendation, !rec.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.info)
                    Text(rec)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoRow()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func boolText(_ b: Bool?) -> String {
        switch b {
        case .some(true):  return "Yes"
        case .some(false): return "No"
        case .none:        return "Unconfirmed"
        }
    }

    // MARK: - Footer (primary CTA per step)

    private var footer: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            Group {
                switch step {
                case .collect:
                    Button { Task { await request() } } label: {
                        ctaLabel(requesting ? "Requesting…" : "Request step-up", loading: requesting)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRequest)
                    .opacity(canRequest ? 1 : 0.5)

                case .challenge:
                    Button { Task { await confirm() } } label: {
                        ctaLabel(confirming ? "Confirming…" : "Confirm code", loading: confirming)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.5)

                case .verdict:
                    Button {
                        onComplete(confirmStatusForDismiss)
                        dismiss()
                    } label: {
                        ctaLabel("Done", loading: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s5)
        }
        .background(palette.bgSheet)
        .background(.regularMaterial)
    }

    private func ctaLabel(_ title: String, loading: Bool) -> some View {
        HStack(spacing: 8) {
            if loading { ProgressView().tint(.white) }
            Text(title)
                .font(EType.title)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(LinearGradient.primary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Shared subviews

    private func statusRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(body)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func infoNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintDanger)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Enablement

    private var canRequest: Bool {
        guard !requesting else { return false }
        switch kind {
        case .bank:
            return !accountHolderName.trimmingCharacters(in: .whitespaces).isEmpty
                && routingNumber.trimmingCharacters(in: .whitespaces).count >= 4
                && accountNumberLast4.trimmingCharacters(in: .whitespaces).count >= 2
        case .payout:
            return !payoutMethod.trimmingCharacters(in: .whitespaces).isEmpty
                && !destinationRef.trimmingCharacters(in: .whitespaces).isEmpty
        case .officer:
            return !officerName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var canConfirm: Bool {
        !confirming
            && (challenge?.requestId != nil)
            && code.trimmingCharacters(in: .whitespaces).count >= 4
    }

    // MARK: - Cooldown math

    /// ISO-8601 parser tolerant of fractional seconds, shared lazily.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private var cooldownExpiry: Date? {
        guard let s = challenge?.cooldownExpiresAt, !s.isEmpty else { return nil }
        return Self.isoFractional.date(from: s) ?? Self.isoPlain.date(from: s)
    }

    /// Seconds remaining on the cooldown. 0 when no expiry is known or it
    /// has already elapsed.
    private var cooldownRemaining: TimeInterval {
        guard let exp = cooldownExpiry else { return 0 }
        return max(0, exp.timeIntervalSince(now))
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    // MARK: - Honest verdict mapping

    private struct VState {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let pillText: String
        let pillKind: StatusPill.Kind
    }

    /// The change reads "applied" ONLY when verified==true AND applied==true.
    /// verified==true but applied!=true reads "verified — pending apply".
    /// Anything else is danger/warning, never a fake success.
    private var verdictState: VState {
        guard let r = confirmResult else {
            return VState(title: "Pending confirmation",
                          subtitle: "Awaiting code confirmation.",
                          icon: "clock.fill", color: Brand.warning,
                          pillText: "Pending", pillKind: .warning)
        }
        let statusLower = (r.status ?? "").lowercased()

        if r.verified == true && r.applied == true {
            return VState(title: "Change applied",
                          subtitle: "Code verified, cooldown satisfied, and the change is now applied.",
                          icon: "checkmark.seal.fill", color: Brand.success,
                          pillText: "Applied", pillKind: .success)
        }
        if r.verified == true {
            // Verified but NOT applied — held by cooldown / SIM-swap / review.
            let held = challenge?.simSwapClean != true || cooldownRemaining > 0
            return VState(title: "Verified — pending apply",
                          subtitle: held
                            ? "Your code was verified, but the change is held for review (cooldown or SIM-swap risk). It is not yet applied."
                            : "Your code was verified. The change is queued to apply and is not yet live.",
                          icon: "hourglass", color: Brand.warning,
                          pillText: "Pending apply", pillKind: .warning)
        }
        if r.verified == false
            || statusLower == "failed" || statusLower == "denied"
            || statusLower == "rejected" || statusLower == "cancelled" {
            return VState(title: "Verification failed",
                          subtitle: r.reason?.isEmpty == false
                            ? (r.reason ?? "")
                            : "The code did not verify. The change was not applied.",
                          icon: "xmark.seal.fill", color: Brand.danger,
                          pillText: "Failed", pillKind: .danger)
        }
        // Unknown / null — surface verbatim, never green.
        return VState(title: "Pending review",
                      subtitle: "The step-up returned without a confirmed apply. Routed to manual review — the change is not applied.",
                      icon: "exclamationmark.triangle.fill", color: Brand.warning,
                      pillText: (r.status ?? "Pending").capitalized, pillKind: .warning)
    }

    /// Status string handed back to the host on dismiss.
    private var confirmStatusForDismiss: String {
        if let r = confirmResult {
            if r.verified == true && r.applied == true { return r.status ?? "APPLIED" }
            return r.status ?? (r.verified == true ? "VERIFIED" : "PENDING")
        }
        if challenge != nil { return "CHALLENGE_PENDING" }
        return "incomplete"
    }

    // MARK: - Actions

    @MainActor
    private func request() async {
        guard canRequest else { return }
        requesting = true
        error = nil
        defer { requesting = false }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonArg = trimmedReason.isEmpty ? nil : trimmedReason

        do {
            let result: StepUpAuthAPI.Challenge
            switch kind {
            case .bank:
                result = try await EusoTripAPI.shared.stepUpAuth.requestBankChange(
                    accountHolderName: trimmedOrNil(accountHolderName),
                    routingNumber: trimmedOrNil(routingNumber),
                    accountNumberLast4: trimmedOrNil(accountNumberLast4),
                    bankName: trimmedOrNil(bankName),
                    reason: reasonArg
                )
            case .payout:
                result = try await EusoTripAPI.shared.stepUpAuth.requestPayoutChange(
                    payoutMethod: trimmedOrNil(payoutMethod),
                    destinationRef: trimmedOrNil(destinationRef),
                    destinationLast4: trimmedOrNil(destinationLast4),
                    reason: reasonArg
                )
            case .officer:
                result = try await EusoTripAPI.shared.stepUpAuth.requestOfficerChange(
                    companyId: companyId,
                    officerName: trimmedOrNil(officerName),
                    officerTitle: trimmedOrNil(officerTitle),
                    officerUserId: nil,
                    action: officerAction,
                    reason: reasonArg
                )
            }
            challenge = result
            confirmResult = nil
            code = ""
            withAnimation(.easeInOut(duration: 0.2)) { step = .challenge }
        } catch let apiErr as EusoTripAPIError {
            error = apiErr.errorDescription ?? "Couldn't request step-up authentication."
        } catch let e as LocalizedError {
            error = e.errorDescription ?? "Couldn't request step-up authentication."
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func confirm() async {
        guard canConfirm, let requestId = challenge?.requestId else { return }
        confirming = true
        error = nil
        defer { confirming = false }

        do {
            let result = try await EusoTripAPI.shared.stepUpAuth.confirmStepUp(
                requestId: requestId,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            confirmResult = result
            withAnimation(.easeInOut(duration: 0.2)) { step = .verdict }
        } catch let apiErr as EusoTripAPIError {
            error = apiErr.errorDescription ?? "Couldn't confirm the code."
        } catch let e as LocalizedError {
            error = e.errorDescription ?? "Couldn't confirm the code."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func trimmedOrNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Previews

#Preview("1110 · Step-up · Bank · Night") {
    StepUpAuthSheet(kind: .bank)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("1110 · Step-up · Officer · Afternoon") {
    StepUpAuthSheet(kind: .officer)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
