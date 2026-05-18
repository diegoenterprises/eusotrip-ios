//
//  901_ComplianceExpiringDocs.swift
//  EusoTrip — Compliance Officer · Expiring documents (30-day window).
//
//  RESURRECTED 2026-05-01 — was previously shelved behind `#if false`
//  due to a reference to `OrbeSang.State.alert`, which doesn't exist
//  in the canonical 3-case `OrbeSang.State` enum (`.idle`,
//  `.listening`, `.thinking`) at `Theme/DesignSystem.swift:273`. Mapped
//  the alerting cue to `.idle` since the orb's role here is decorative
//  (the screen's own gradient warning chips carry the visual urgency).
//

import SwiftUI

struct ComplianceExpiringDocsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ExpiringBody() } nav: {
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

private struct ExpiringDoc: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let driver: String?
    let expiresAt: String?
    let daysRemaining: Int?
}

private struct ExpiringBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ExpiringDoc] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
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
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · EXPIRING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Expiring documents").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Documents expiring in the next 30 days. Sort: closest first.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal.fill", title: "No expirations", subtitle: "All certifications are current for the next 30 days.")
        } else {
            ForEach(rows) { d in
                LifecycleCard(accentDanger: (d.daysRemaining ?? 999) < 7) {
                    LifecycleSection(label: (d.type ?? "DOCUMENT").uppercased(), icon: "doc.text.fill")
                    LifecycleRow(label: "Driver",      value: dashIfEmpty(d.driver))
                    LifecycleRow(label: "Expires",     value: dashIfEmpty(d.expiresAt))
                    LifecycleRow(label: "Days left",   value: d.daysRemaining.map { "\($0)" } ?? "—")
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let r: [ExpiringDoc] = try await EusoTripAPI.shared.query("compliance.getExpiringItems", input: In(limit: 200))
            rows = r.sorted { ($0.daysRemaining ?? 999) < ($1.daysRemaining ?? 999) }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("901 · Expiring docs · Night") { ComplianceExpiringDocsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("901 · Expiring docs · Afternoon") { ComplianceExpiringDocsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
