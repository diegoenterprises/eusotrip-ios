//
//  DriverInviteBulkStep.swift
//  EusoTrip — onboarding step: bulk-invite drivers / staff.
//
//  Shown after fleet registration for any role that operates a team
//  (CATALYST / BROKER / RAIL_CATALYST / VESSEL_OPERATOR / DISPATCH).
//  The user pastes a list of teammates and we fire one email +
//  deep link per row through `fleetRegistration.bulkInviteDrivers`.
//  Recipients land in the registration wizard with the carrier's
//  companyId pre-set.
//

import SwiftUI

struct PendingInvitee: Identifiable, Hashable {
    let id: UUID = UUID()
    var firstName: String
    var lastName: String
    var email: String
    var phone: String = ""
    var cdlNumber: String = ""
    var cdlState: String = ""
    var vertical: String = "truck"   // "truck" | "rail" | "vessel"
}

struct DriverInviteBulkStep: View {
    let vertical: String
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    @Environment(\.palette) private var palette

    @State private var pending: [PendingInvitee] = []
    @State private var message: String = ""
    @State private var inflight: Bool = false
    @State private var result: ResultSummary? = nil
    @State private var errorBanner: String? = nil

    init(
        vertical: String = "truck",
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.vertical = vertical
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                messageBlock
                addRow
                if !pending.isEmpty {
                    pendingList
                }
                if let r = result { resultCard(r) }
                if let e = errorBanner {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }
                actionRail
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(palette.bgPage)
    }

    // MARK: — Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INVITE YOUR TEAM").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(headerTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text("Each teammate gets an email + deep link. Their EusoTrip account links to your company automatically.")
                .font(EType.body).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerTitle: String {
        switch vertical {
        case "rail": return "Invite engineers + conductors"
        case "vessel": return "Invite mariners + captains"
        default: return "Invite drivers + dispatchers"
        }
    }

    private var messageBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPTIONAL MESSAGE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $message)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
                .padding(8)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .font(EType.body)
        }
    }

    private var addRow: some View {
        Button {
            pending.append(PendingInvitee(firstName: "", lastName: "", email: "", vertical: vertical))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("Add teammate")
                    .font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PENDING · \(pending.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Button { pending.removeAll() } label: {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            ForEach($pending) { $row in
                pendingRow($row)
            }
        }
    }

    private func pendingRow(_ row: Binding<PendingInvitee>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(row.wrappedValue.firstName.isEmpty
                     ? "New teammate"
                     : "\(row.wrappedValue.firstName) \(row.wrappedValue.lastName)")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Button {
                    pending.removeAll(where: { $0.id == row.wrappedValue.id })
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                inputField("First name", text: row.firstName, capitalize: .words)
                inputField("Last name", text: row.lastName, capitalize: .words)
            }
            inputField("Email", text: row.email, keyboard: .emailAddress, capitalize: .never)
            HStack(spacing: 8) {
                inputField("Phone (optional)", text: row.phone, keyboard: .phonePad)
                inputField("CDL # (optional)", text: row.cdlNumber, capitalize: .characters)
            }
            verticalPicker(row)
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func inputField(_ placeholder: String,
                            text: Binding<String>,
                            keyboard: UIKeyboardType = .default,
                            capitalize: TextInputAutocapitalization = .never) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalize)
            .autocorrectionDisabled()
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(palette.bgCardSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .font(EType.caption)
    }

    private func verticalPicker(_ row: Binding<PendingInvitee>) -> some View {
        HStack(spacing: 6) {
            ForEach(["truck", "rail", "vessel"], id: \.self) { v in
                Button { row.wrappedValue.vertical = v } label: {
                    Text(v.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(row.wrappedValue.vertical == v ? .white : palette.textSecondary)
                        .background(row.wrappedValue.vertical == v
                                    ? AnyView(LinearGradient.diagonal)
                                    : AnyView(palette.bgCardSoft))
                        .overlay(
                            row.wrappedValue.vertical == v
                            ? AnyView(EmptyView())
                            : AnyView(Capsule().strokeBorder(palette.borderSoft))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func resultCard(_ r: ResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("INVITES SENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.success)
            }
            Text("\(r.sent) sent · \(r.failed.count) failed")
                .font(EType.body).foregroundStyle(palette.textPrimary)
            if !r.failed.isEmpty {
                ForEach(r.failed, id: \.email) { f in
                    Text("• \(f.email) — \(f.reason)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.success.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionRail: some View {
        VStack(spacing: 8) {
            Button {
                Task { await commit() }
            } label: {
                HStack(spacing: 8) {
                    if inflight {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    Text(commitTitle).font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(canCommit ? AnyView(LinearGradient.diagonal) : AnyView(Color.gray.opacity(0.4)))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            .opacity(canCommit ? 1.0 : 0.55)

            HStack(spacing: 8) {
                if let onSkip {
                    Button { onSkip() } label: {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(palette.textPrimary)
                            .background(palette.bgCardSoft)
                            .overlay(Capsule().strokeBorder(palette.borderSoft))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if result != nil {
                    Button { onContinue() } label: {
                        Text("Continue")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(LinearGradient.diagonal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var canCommit: Bool {
        !inflight && pending.contains(where: isValid)
    }

    private var commitTitle: String {
        if inflight { return "Sending…" }
        let valid = pending.filter(isValid).count
        if valid == 0 { return "Add a teammate first" }
        return "Send \(valid) \(valid == 1 ? "invite" : "invites")"
    }

    // MARK: — Behavior

    private func isValid(_ i: PendingInvitee) -> Bool {
        !i.firstName.isEmpty && !i.lastName.isEmpty
            && i.email.contains("@") && i.email.contains(".")
    }

    @MainActor
    private func commit() async {
        let valid = pending.filter(isValid)
        guard !valid.isEmpty else { return }
        inflight = true
        defer { inflight = false }
        errorBanner = nil

        let inputs = valid.map { p in
            FleetRegistrationAPI.DriverInviteInput(
                firstName: p.firstName, lastName: p.lastName,
                email: p.email,
                phone: p.phone.isEmpty ? nil : p.phone,
                cdlNumber: p.cdlNumber.isEmpty ? nil : p.cdlNumber,
                cdlState: p.cdlState.isEmpty ? nil : p.cdlState,
                hireDate: nil,
                vertical: p.vertical,
                notes: nil
            )
        }
        do {
            let resp = try await EusoTripAPI.shared.fleetRegistration.bulkInviteDrivers(
                inputs,
                message: message.isEmpty ? nil : message
            )
            result = ResultSummary(
                sent: resp.summary.sent,
                failed: resp.failed
            )
            // Drop the successfully sent emails from pending so the
            // user can fix the failures and resubmit.
            let sentEmails = Set(resp.sent.map { $0.email.lowercased() })
            pending.removeAll { sentEmails.contains($0.email.lowercased()) }
        } catch let e {
            errorBanner = "Send failed: \((e as? EusoTripAPIError)?.errorDescription ?? e.localizedDescription)"
        }
    }

    private struct ResultSummary: Equatable {
        let sent: Int
        let failed: [FleetRegistrationAPI.InviteFailed]
    }
}

// MARK: - Previews

#Preview("Invite Step · Dark") {
    DriverInviteBulkStep(vertical: "truck", onContinue: {}, onSkip: {})
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Invite Step · Light") {
    DriverInviteBulkStep(vertical: "rail", onContinue: {}, onSkip: {})
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
