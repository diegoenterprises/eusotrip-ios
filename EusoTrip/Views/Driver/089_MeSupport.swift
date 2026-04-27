//
//  089_MeSupport.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Support & Tickets)
//
//  Screen 089 · Me · Support & Tickets — the driver's live ticket
//  lifecycle. Summary counters at the top, the driver's tickets
//  ordered newest-first, a "New ticket" CTA that opens a compose
//  sheet with subject + message + category + priority. Every row
//  shows the real ticket number, category, status, and age.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Counters ship from `support.getSummary` — MCP-verified at
//      `frontend/server/routers/support.ts`. Driver sees their own
//      counts only; admins see company-wide (server-gated).
//    • Tickets ship from `support.getMyTickets`. Scoped driver-side
//      server-side via `ctx.user.id`.
//    • Create hits `support.createTicket`. Server NLP-classifies the
//      category when the driver leaves it as "general", so the
//      auto-routed category on the row can differ from what was sent
//      — that's the server exercising its own smarts, not the client.
//
//    • No knowledge-base surface. `support.getKBArticles` /
//      `getKBCategories` currently return empty arrays on the
//      server (no `knowledge_base_articles` table), so we do NOT
//      ship a KB UI. When the server ships real KB content, the
//      matching Pulse-role-wiring doctrine will pull it in.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero counter + submit CTA.
//         Brand.warning on high-priority status chips.
//    §4   Tokenized Space/Radius/EType throughout.
//    §5   Palette semantic.
//    §7   Ternary ShapeStyle wrapped in `AnyShapeStyle`.
//

import SwiftUI

// MARK: - Status + category helpers

private enum TicketStatusKind {
    case open, inProgress, waitingUser, resolved, closed, other

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "open":          self = .open
        case "in_progress":   self = .inProgress
        case "waiting_user":  self = .waitingUser
        case "resolved":      self = .resolved
        case "closed":        self = .closed
        default:              self = .other
        }
    }

    var label: String {
        switch self {
        case .open:         return "Open"
        case .inProgress:   return "In-progress"
        case .waitingUser:  return "Your turn"
        case .resolved:     return "Resolved"
        case .closed:       return "Closed"
        case .other:        return "Unknown"
        }
    }
}

private enum TicketCategoryKind: String, CaseIterable {
    case general, billing, technical, compliance, loads, account, agreements, safety

    var label: String {
        switch self {
        case .general:    return "General"
        case .billing:    return "Billing"
        case .technical:  return "Technical"
        case .compliance: return "Compliance"
        case .loads:      return "Loads"
        case .account:    return "Account"
        case .agreements: return "Agreements"
        case .safety:     return "Safety"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "questionmark.circle"
        case .billing:    return "creditcard"
        case .technical:  return "wrench.and.screwdriver"
        case .compliance: return "checkmark.shield"
        case .loads:      return "truck.box"
        case .account:    return "person.crop.circle"
        case .agreements: return "doc.text"
        case .safety:     return "exclamationmark.triangle"
        }
    }
}

private enum TicketPriorityKind: String, CaseIterable {
    case low, medium, high, urgent

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Screen root

struct MeSupport: View {
    @Environment(\.palette) var palette
    @StateObject private var store = SupportStore()

    @State private var showingCompose = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                summaryStrip
                newTicketCTA
                ticketsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showingCompose) {
            NewTicketSheet(store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Support")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(store.summary?.avgResponseTime.map { "Avg response · \($0)" }
                     ?? "Open a ticket · your replies land in Inbox")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        HStack(spacing: Space.s2) {
            summaryTile(label: "OPEN",       value: "\(store.summary?.open ?? 0)")
            summaryTile(label: "IN-PROGRESS", value: "\(store.summary?.inProgress ?? 0)")
            summaryTile(label: "RESOLVED",   value: "\(store.summary?.resolved ?? 0)")
        }
    }

    private func summaryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: New ticket CTA

    private var newTicketCTA: some View {
        Button {
            showingCompose = true
        } label: {
            HStack {
                Image(systemName: "plus.message")
                Text("New ticket")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Tickets list

    private var ticketsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("YOUR TICKETS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.tickets.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "tray",
                    title: "No tickets yet",
                    subtitle: "Open a ticket above when you need a human. Response times average a couple of hours on weekdays."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.tickets) { t in
                        ticketRow(t)
                    }
                }
            }
        }
    }

    private func ticketRow(_ t: SupportAPI.Ticket) -> some View {
        let status = TicketStatusKind(t.status)
        let categoryKind = TicketCategoryKind(rawValue: (t.category ?? "general").lowercased()) ?? .general
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.55))
                Image(systemName: categoryKind.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.ticketNumber ?? "Ticket #\(t.id)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
                Text(t.subject)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Space.s1) {
                    Text(categoryKind.label)
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                    Text("·")
                        .foregroundStyle(palette.textTertiary)
                    Text(relativeTime(t.createdAt))
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            Spacer()
            statusChip(status)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    @ViewBuilder
    private func statusChip(_ kind: TicketStatusKind) -> some View {
        let text = kind.label.uppercased()
        switch kind {
        case .waitingUser, .open:
            Text(text)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient.diagonal))
        case .inProgress:
            Text(text)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(Brand.warning, lineWidth: 1))
        case .resolved, .closed:
            Text(text)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.55), lineWidth: 1))
        case .other:
            Text(text)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.4), lineWidth: 1))
        }
    }

    private var footer: some View {
        Text("Your tickets and replies sync to Inbox. Urgent transit, safety, or accident reports should also go through SOS.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func relativeTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "just now" }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}

// MARK: - Compose sheet

private struct NewTicketSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SupportStore

    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var category: TicketCategoryKind = .general
    @State private var priority: TicketPriorityKind = .medium
    @State private var submitError: String?

    private var canSubmit: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !store.isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Subject")) {
                    TextField("What's this about?", text: $subject, axis: .vertical)
                        .lineLimit(1...2)
                }
                Section(header: Text("Message")) {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(TicketCategoryKind.allCases, id: \.self) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    if category == .general {
                        Text("ESANG will auto-route general tickets.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Section(header: Text("Priority")) {
                    Picker("Priority", selection: $priority) {
                        ForEach(TicketPriorityKind.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let err = submitError {
                    Section {
                        Text(err)
                            .foregroundStyle(Brand.warning)
                            .font(EType.caption)
                    }
                }
            }
            .navigationTitle("New ticket")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if store.isCreating {
                            ProgressView()
                        } else {
                            Text("Send").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        submitError = nil
        do {
            _ = try await store.create(
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category.rawValue,
                priority: priority.rawValue
            )
            dismiss()
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't send — try again in a moment."
        }
    }
}

// MARK: - Screen wrapper

struct MeSupportScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeSupport()
        } nav: {
            BottomNav(
                leading: driverNavLeading_089(),
                trailing: driverNavTrailing_089(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_089() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_089() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("089 · Support · Night") {
    MeSupportScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("089 · Support · Afternoon") {
    MeSupportScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
