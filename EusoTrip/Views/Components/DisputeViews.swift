//
//  DisputeViews.swift
//  EusoTrip — Dispute lifecycle UI (shipper + driver, single surface).
//
//  Closes Phase 16 (Dispute) of the 8000-scenario shipper↔driver parity
//  audit (docs/parity-2026/EXECUTIVE_VERDICT.md §4.3) — UF just shipped
//  TMS Financials with bulk dispute tooling claiming 20% faster
//  resolution; we ship a real two-sided lifecycle on iOS.
//
//  Two production-grade surfaces in this file:
//
//    1. DisputeListView   — full inbox of disputes the caller is named
//                           in (filed by them OR against them).
//                           Category chips at top; tap-to-detail rows.
//
//    2. DisputeDetailView — single-dispute surface: header (category
//                           pill, status badge, amount, lane), evidence
//                           thread (chronological, side-aware bubbles),
//                           respond composer, escalate CTA.
//
//  Both consume `EusoTripAPI.shared.disputes.*`. Server contract is
//  `disputes.list / getById / respond / escalate` — see
//  `frontend/server/routers/disputes.ts` for the unified envelope.
//
//  Production-grade per [feedback_swiftui_previews] + animation
//  doctrine §B.4. Dark + Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Inbox

struct DisputeListView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var rows: [DisputesAPI.Dispute] = []
    @State private var selectedCategory: DisputesAPI.Category? = nil
    @State private var loading: Bool = false
    @State private var error: String? = nil
    @State private var detail: DisputesAPI.Dispute? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryChips
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s2)
            IridescentHairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s3) {
                    if loading && rows.isEmpty {
                        skeletonStack
                    } else if rows.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleRows) { row in
                            Button {
                                detail = row
                            } label: {
                                rowCard(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let err = error {
                        errorBanner(err)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .refreshable { await load() }
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $detail) { d in
            DisputeDetailView(initial: d, onChanged: { Task { await load() } })
                .environment(\.palette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var visibleRows: [DisputesAPI.Dispute] {
        if let c = selectedCategory {
            return rows.filter { $0.categoryKind == c }
        }
        return rows
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "All", isOn: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(DisputesAPI.Category.allCases) { cat in
                    chip(label: cat.label, isOn: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(EType.caption).fontWeight(.semibold)
                .foregroundStyle(isOn ? palette.textOnGradient : palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isOn
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.bgCard))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.clear : palette.borderFaint
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func rowCard(_ d: DisputesAPI.Dispute) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: d.categoryKind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(d.categoryKind.label.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    if let amt = d.amount {
                        Text(currency(amt))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                    }
                }
                Text(d.reason ?? "—")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let l = d.loadId {
                    Text("Load #\(l)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var skeletonStack: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCardSoft)
                    .frame(height: 80)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No active disputes")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Filed disputes will land here. The counterparty also sees them — both sides exchange evidence in-app, no email back-and-forth.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await EusoTripAPI.shared.disputes.list(limit: 40)
            rows = resp.rows
            error = nil
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Detail + respond

struct DisputeDetailView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession

    /// Initial server payload from the inbox row tap. Refreshes on
    /// open + after every respond/escalate action so the thread
    /// stays current.
    let initial: DisputesAPI.Dispute
    /// Caller-supplied callback so the inbox can re-list after a
    /// status change.
    let onChanged: () -> Void

    @State private var dispute: DisputesAPI.Dispute
    @State private var responseDraft: String = ""
    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var toast: String? = nil

    init(initial: DisputesAPI.Dispute, onChanged: @escaping () -> Void = {}) {
        self.initial = initial
        self.onChanged = onChanged
        _dispute = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    reasonCard
                    threadCard
                    if let err = error {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    Color.clear.frame(height: 132)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("DISPUTE")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(dispute.id)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await escalate() }
                    } label: {
                        Text("Escalate")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(Brand.warning)
                    }
                    .disabled(inFlight)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composerBar
                    .background(palette.bgPrimary)
            }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Brand.success,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, 132)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            withAnimation { toast = nil }
                        }
                }
            }
        }
        .task { await refresh() }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(dispute.categoryKind.label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text(statusLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(statusColor)
            }
            HStack(alignment: .firstTextBaseline) {
                if let amt = dispute.amount {
                    Text(currency(amt))
                        .font(.system(size: 28, weight: .heavy).monospacedDigit())
                        .tracking(-0.4)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 0)
            }
            if let l = dispute.loadId {
                Text("Load #\(l)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REASON")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(dispute.reason ?? "—")
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var threadCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("THREAD")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            if dispute.evidence.isEmpty {
                Text("No replies yet. Add a response below — both sides see every message.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(Array(dispute.evidence.enumerated()), id: \.offset) { _, e in
                    threadEntry(e)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func threadEntry(_ e: DisputesAPI.Dispute.EvidenceItem) -> some View {
        // Match the entry's author id (Int) against the signed-in
        // user. AuthUser.id ships as String over the wire so we
        // coerce both sides to String for the compare.
        let myId: String? = session.user.map { String($0.id) }
        let isMe: Bool = e.byUserId.flatMap { uid -> Bool? in
            guard let mine = myId else { return false }
            return String(uid) == mine
        } ?? false
        HStack {
            if isMe { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 4) {
                Text(threadLabel(for: e))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Text(e.message ?? e.description ?? "—")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let ts = e.timestamp {
                    Text(ts)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .background(threadBubbleBackground(isMe: isMe))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            if !isMe { Spacer(minLength: 32) }
        }
    }

    /// Side-aware bubble background. Wrapped as a returned View
    /// because `.background(_:)` won't infer a unified ShapeStyle
    /// from a LinearGradient+Color ternary; ZStack is the
    /// type-uniform escape hatch.
    @ViewBuilder
    private func threadBubbleBackground(isMe: Bool) -> some View {
        if isMe {
            LinearGradient.diagonal.opacity(0.15)
        } else {
            palette.bgCardSoft
        }
    }

    private func threadLabel(for e: DisputesAPI.Dispute.EvidenceItem) -> String {
        switch e.type {
        case "message": return "MESSAGE · \(e.byRole ?? "user")"
        case "audit":   return "AUDIT"
        case "photo":   return "PHOTO EVIDENCE"
        case "doc":     return "DOC EVIDENCE"
        case "gps":     return "GPS BREADCRUMB"
        default:        return e.type.uppercased()
        }
    }

    private var composerBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR RESPONSE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .bottom, spacing: Space.s2) {
                    TextField("Reply with context, evidence, or a counter-offer…",
                              text: $responseDraft,
                              axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .font(EType.body)
                        .padding(Space.s3)
                        .background(palette.bgCardSoft,
                                    in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(palette.borderFaint))
                        .disabled(inFlight)

                    Button {
                        Task { await respond() }
                    } label: {
                        HStack(spacing: 4) {
                            if inFlight {
                                ProgressView().tint(palette.textOnGradient)
                            }
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(palette.textOnGradient)
                        .frame(width: 56, height: 44)
                        .background(LinearGradient.diagonal,
                                    in: RoundedRectangle(cornerRadius: Radius.sm))
                        .opacity(canSend ? 1.0 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
        }
    }

    private var canSend: Bool {
        let trimmed = responseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 1 && !inFlight
    }

    private var statusLabel: String {
        switch dispute.status {
        case "filed":         return "Filed"
        case "under_review":  return "Under review"
        case "responded":     return "Responded"
        case "escalated":     return "Escalated"
        case "resolved":      return "Resolved"
        case "denied":        return "Denied"
        case "paid":          return "Paid"
        case "voided":        return "Voided"
        default:              return dispute.status
        }
    }

    private var statusColor: Color {
        switch dispute.status {
        case "resolved", "paid":           return Brand.success
        case "denied", "voided":           return Brand.danger
        case "escalated":                  return Brand.warning
        default:                           return palette.textSecondary
        }
    }

    // MARK: - Network

    private func refresh() async {
        do {
            dispute = try await EusoTripAPI.shared.disputes.getById(id: dispute.id)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func respond() async {
        let trimmed = responseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await EusoTripAPI.shared.disputes
                .respond(id: dispute.id, message: trimmed)
            responseDraft = ""
            withAnimation { toast = "Response sent" }
            await refresh()
            onChanged()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func escalate() async {
        let reason = responseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Escalating for arbitration"
            : responseDraft
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await EusoTripAPI.shared.disputes
                .escalate(id: dispute.id, reason: reason)
            withAnimation { toast = "Escalated to arbitration" }
            await refresh()
            onChanged()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Previews

#Preview("Dispute list · Dark") {
    DisputeListView()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Dispute list · Light") {
    DisputeListView()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
