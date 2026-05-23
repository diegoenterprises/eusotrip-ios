//
//  902_ComplianceViolations.swift
//  EusoTrip — Compliance Officer · Recent violations + resolve mutation.
//
//  RESURRECTED 2026-05-01 — was previously shelved behind `#if false`
//  due to a reference to `OrbeSang.State.alert`, which doesn't exist
//  in the canonical 3-case `OrbeSang.State` enum. Mapped to `.idle`;
//  the violation severity chips inside `ViolationsBody` carry the
//  visual urgency.
//
//  Reshaped 2026-05-23 from a flat list with a per-card "Mark
//  resolved" button into a 2-column Kanban (OPEN / RESOLVED) with
//  drag-to-resolve. The button-flow stays wired on each card as a
//  tap fallback so accessibility / non-drag users land the same
//  mutation. Both paths fire `compliance.resolveViolation`.
//

import SwiftUI

struct ComplianceViolationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ViolationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Audits", systemImage: "doc.text.magnifyingglass", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct Violation: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let driver: String?
    let date: String?
    let severity: String?
    let status: String?
}

private struct ViolationKanbanColumn: Identifiable, Hashable {
    let id: String       // matches server status value
    let label: String
    let icon: String
}

private let violationKanbanColumns: [ViolationKanbanColumn] = [
    .init(id: "open",     label: "OPEN",     icon: "exclamationmark.triangle.fill"),
    .init(id: "resolved", label: "RESOLVED", icon: "checkmark.seal.fill"),
]

private struct ViolationsBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [Violation] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var resolvingId: String? = nil
    @State private var actionError: String? = nil
    @State private var lastResolved: String? = nil
    @State private var selected: String = "open"
    @State private var dragHoverColumn: String? = nil

    private var byColumn: [String: [Violation]] {
        Dictionary(grouping: rows) { ($0.status ?? "open").lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if let m = lastResolved {
                        LifecycleCard(accentGradient: true) {
                            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                        }
                    }
                    if let e = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    scrubber
                    if loading && rows.isEmpty {
                        LifecycleCard {
                            Text("Loading…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if rows.isEmpty {
                        EusoEmptyState(
                            systemImage: "checkmark.seal",
                            title: "Clean record",
                            subtitle: "No violations on file."
                        )
                    } else {
                        columnPager
                            .frame(minHeight: 480)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · VIOLATIONS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Recent violations")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag an OPEN card to RESOLVED to close it. Major (>2 defects) cards flag in red. Tap-resolve button stays on each open card.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(violationKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(violationKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: ViolationKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if col.id == "resolved" {
                        Text("DROP OPEN HERE TO CLOSE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: col.id == "open" ? "No open violations" : "No closed records yet",
                        subtitle: col.id == "open"
                            ? "Fleet's clean. New inspection violations land here."
                            : "Drag a violation from OPEN here to close it."
                    )
                } else {
                    ForEach(cards) { v in
                        cardView(v, columnId: col.id)
                            .draggable(v.id) {
                                cardView(v, columnId: col.id)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first else { return false }
            guard let src = rows.first(where: { $0.id == droppedId }) else { return false }
            // Only one transition is user-driven: open → resolved.
            // RESOLVED is terminal; the server doesn't expose a re-open
            // mutation, so dragging back is a no-op that mirrors policy.
            guard col.id == "resolved", (src.status ?? "open").lowercased() == "open" else {
                return false
            }
            Task { await resolve(src.id) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ v: Violation, columnId: String) -> some View {
        let isMajor = v.severity == "major"
        let isResolving = resolvingId == v.id
        return LifecycleCard(accentDanger: isMajor && columnId == "open") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LifecycleSection(label: (v.type ?? "VIOLATION").uppercased(), icon: "exclamationmark.octagon")
                    Spacer(minLength: 0)
                    if let s = v.severity {
                        Text(s.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill((isMajor ? Brand.danger : .orange).opacity(0.18)))
                            .foregroundStyle(isMajor ? Brand.danger : .orange)
                    }
                }
                LifecycleRow(label: "Driver",   value: dashIfEmpty(v.driver))
                LifecycleRow(label: "Date",     value: dashIfEmpty(v.date))
                LifecycleRow(label: "Status",   value: (v.status ?? "—").uppercased())
                if columnId == "open" {
                    Button { Task { await resolve(v.id) } } label: {
                        HStack(spacing: 6) {
                            if isResolving { ProgressView().tint(.white) }
                            Text(isResolving ? "Resolving…" : "Mark resolved")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(resolvingId != nil)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let r: [Violation] = try await EusoTripAPI.shared.query("compliance.getRecentViolations", input: In(limit: 100))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func resolve(_ id: String) async {
        await MainActor.run { resolvingId = id; actionError = nil }
        let bare = id.replacingOccurrences(of: "vio_", with: "")
        struct In: Encodable { let violationId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "compliance.resolveViolation",
                input: In(violationId: bare, resolution: "Resolved from mobile compliance officer")
            )
            await MainActor.run { lastResolved = "Closed violation \(id)." }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { selected = "resolved" }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { resolvingId = nil }
    }
}

#Preview("902 · Violations · Night") { ComplianceViolationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("902 · Violations · Afternoon") { ComplianceViolationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
