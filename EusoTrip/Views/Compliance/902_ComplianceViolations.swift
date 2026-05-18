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

private struct ViolationsBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [Violation] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var resolvingId: String? = nil
    @State private var actionError: String? = nil
    @State private var lastResolved: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastResolved { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let e = actionError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · VIOLATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Recent violations").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Major (>2 defects) flag in red. Resolve closes the record.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal", title: "Clean record", subtitle: "No violations on file.")
        } else {
            ForEach(rows) { v in
                LifecycleCard(accentDanger: v.severity == "major") {
                    LifecycleSection(label: (v.type ?? "VIOLATION").uppercased(), icon: "exclamationmark.octagon")
                    LifecycleRow(label: "Driver",   value: dashIfEmpty(v.driver))
                    LifecycleRow(label: "Date",     value: dashIfEmpty(v.date))
                    LifecycleRow(label: "Severity", value: (v.severity ?? "—").uppercased())
                    LifecycleRow(label: "Status",   value: (v.status ?? "—").uppercased())
                    if v.status != "resolved" {
                        Button { Task { await resolve(v.id) } } label: {
                            HStack(spacing: 6) {
                                if resolvingId == v.id { ProgressView().tint(.white) }
                                Text(resolvingId == v.id ? "Resolving…" : "Mark resolved").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain).disabled(resolvingId != nil).padding(.top, 6)
                    }
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
        resolvingId = id; actionError = nil
        let bare = id.replacingOccurrences(of: "vio_", with: "")
        struct In: Encodable { let violationId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("compliance.resolveViolation", input: In(violationId: bare, resolution: "Resolved from mobile compliance officer"))
            lastResolved = "Closed violation \(id)."
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        resolvingId = nil
    }
}

#Preview("902 · Violations · Night") { ComplianceViolationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("902 · Violations · Afternoon") { ComplianceViolationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
