//
//  900_ComplianceOfficerHome.swift
//  EusoTrip — Compliance Officer · Home (overall score + drill-ins).
//

import SwiftUI

struct ComplianceOfficerHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ComplianceHomeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: true),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Audits", systemImage: "doc.text.magnifyingglass", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ComplianceDash: Decodable, Hashable {
    let complianceScore: Int?
    let overallScore: Int?
    let expiringDocs: Int?
    let overdueItems: Int?
    let pendingAudits: Int?
    let violations: Int?
    let trend: String?
    let expiring: Int?
    let compliant: Int?
    let nonCompliant: Int?
}

private struct ExpiringDocPriority: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let driver: String?
    let expiresAt: String?
    let daysRemaining: Int?
}

private struct ComplianceHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: ComplianceDash? = nil
    @State private var topExpiring: ExpiringDocPriority? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // ── Home-widget customization (2026-05-23 · DnD parity) ──
    enum ComplianceWidgetSlot: String, CaseIterable, Codable, Identifiable {
        case expiringDocs, news
        var id: String { rawValue }
        var label: String {
            switch self {
            case .expiringDocs: return "Expiring docs"
            case .news:         return "Compliance intel"
            }
        }
    }
    @State private var widgetOrder: [ComplianceWidgetSlot] = ComplianceWidgetSlot.allCases
    @State private var editingLayout: Bool = false
    @State private var dropHoverSlot: ComplianceWidgetSlot? = nil
    private let widgetLayoutKey = "compliance.home.widgetOrder"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                // Canonical lead: morning brief → weather. Driver 010 is the
                // baseline; every role home opens with these two cards.
                RoleHomeIntro()
                if loading { LifecycleCard { Text("Loading compliance score…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = dash {
                    hero(d)
                    statsGrid(d)
                    widgetZoneToolbar
                    ForEach(widgetOrder) { slot in
                        secondaryWidget(for: slot)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await load()
            await hydrateWidgetLayout()
        }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · HOME").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fleet compliance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ d: ComplianceDash) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OVERALL SCORE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text("\(d.overallScore ?? d.complianceScore ?? 0)").font(.system(size: 36, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("COMPLIANT \(d.compliant ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("EXPIRING \(d.expiring ?? d.expiringDocs ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("TREND \((d.trend ?? "—").uppercased())").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statsGrid(_ d: ComplianceDash) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "OVERDUE", value: "\(d.overdueItems ?? 0)", icon: "calendar.badge.exclamationmark", danger: (d.overdueItems ?? 0) > 0)
            LifecycleStatTile(label: "VIOLATIONS", value: "\(d.violations ?? 0)", icon: "exclamationmark.triangle", danger: (d.violations ?? 0) > 0)
            LifecycleStatTile(label: "AUDITS", value: "\(d.pendingAudits ?? 0)", icon: "doc.text.magnifyingglass")
        }
    }

    private func expiringWidget(_ e: ExpiringDocPriority) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoComplianceNavSwap, object: nil, userInfo: ["screenId": "901"])
        } label: {
            LifecycleCard(accentDanger: (e.daysRemaining ?? 99) < 7) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLOSEST EXPIRY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle((e.daysRemaining ?? 99) < 7 ? Brand.danger : palette.textSecondary)
                        Text(e.type ?? "Document").font(.system(size: 18, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text("\(e.driver ?? "—") · expires \(e.expiresAt ?? "—")").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Text(e.daysRemaining.map { "\($0)" } ?? "—").font(.system(size: 28, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                        Text("DAYS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            async let d: ComplianceDash = EusoTripAPI.shared.queryNoInput("compliance.getDashboardStats")
            async let exp: [ExpiringDocPriority] = EusoTripAPI.shared.query("compliance.getExpiringItems", input: In(limit: 10))
            let (dash, items) = try await (d, exp)
            self.dash = dash
            self.topExpiring = items.sorted { ($0.daysRemaining ?? 999) < ($1.daysRemaining ?? 999) }.first
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Reorderable secondary-widget zone (DnD parity)

    private var widgetZoneToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: editingLayout ? "checkmark.circle.fill" : "rectangle.3.group.bubble")
                .font(.system(size: 11, weight: .heavy))
            Text(editingLayout ? "DONE · Tap to save layout" : "CUSTOMIZE WIDGETS")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            Spacer(minLength: 0)
            if editingLayout {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { widgetOrder = ComplianceWidgetSlot.allCases }
                } label: {
                    Text("RESET")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(palette.bgCard, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(editingLayout ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
        .padding(.horizontal, Space.s3).padding(.vertical, 8)
        .background(
            Capsule().strokeBorder(
                editingLayout ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                if editingLayout { editingLayout = false; Task { await persistWidgetLayout() } }
                else { editingLayout = true }
            }
        }
    }

    @ViewBuilder
    private func secondaryWidget(for slot: ComplianceWidgetSlot) -> some View {
        let inner: AnyView = {
            switch slot {
            case .expiringDocs:
                if let e = topExpiring { return AnyView(expiringWidget(e)) }
                else { return AnyView(EmptyView()) }
            case .news:
                return AnyView(NewsCarouselWidget())
            }
        }()
        if editingLayout {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 10)
                inner
            }
            .overlay(alignment: .topTrailing) {
                Text(slot.label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        dropHoverSlot == slot ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: dropHoverSlot == slot ? 2 : 1
                    )
                    .animation(.easeOut(duration: 0.12), value: dropHoverSlot)
            )
            .draggable(slot.rawValue) {
                Text(slot.label)
                    .font(.system(size: 13, weight: .heavy))
                    .padding(10)
                    .background(palette.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let raw = droppedIds.first,
                      let dropped = ComplianceWidgetSlot(rawValue: raw),
                      dropped != slot,
                      let fromIdx = widgetOrder.firstIndex(of: dropped),
                      let toIdx = widgetOrder.firstIndex(of: slot)
                else { return false }
                withAnimation(.easeOut(duration: 0.18)) {
                    let item = widgetOrder.remove(at: fromIdx)
                    widgetOrder.insert(item, at: min(toIdx, widgetOrder.count))
                }
                return true
            } isTargeted: { hovering in
                dropHoverSlot = hovering ? slot : (dropHoverSlot == slot ? nil : dropHoverSlot)
            }
        } else {
            inner
        }
    }

    private func hydrateWidgetLayout() async {
        if let data = UserDefaults.standard.data(forKey: widgetLayoutKey),
           let cached = try? JSONDecoder().decode([ComplianceWidgetSlot].self, from: data),
           !cached.isEmpty {
            widgetOrder = reconcile(cached)
        }
        struct In: Encodable { let role: String }
        struct Slot: Decodable { let widgetId: String }
        struct Out: Decodable { let layout: [Slot]?; let updatedAt: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("users.getDashboardLayout", input: In(role: "COMPLIANCE_OFFICER"))
            if let server = r.layout, !server.isEmpty {
                let parsed = server.compactMap { ComplianceWidgetSlot(rawValue: $0.widgetId) }
                if !parsed.isEmpty {
                    let merged = reconcile(parsed)
                    await MainActor.run { widgetOrder = merged }
                    if let data = try? JSONEncoder().encode(merged) {
                        UserDefaults.standard.set(data, forKey: widgetLayoutKey)
                    }
                }
            }
        } catch { }
    }

    private func persistWidgetLayout() async {
        if let data = try? JSONEncoder().encode(widgetOrder) {
            UserDefaults.standard.set(data, forKey: widgetLayoutKey)
        }
        struct Slot: Encodable { let widgetId: String; let x: Int; let y: Int; let w: Int; let h: Int }
        struct In: Encodable { let role: String; let layout: [Slot] }
        struct Out: Decodable { let success: Bool? }
        let payload = widgetOrder.enumerated().map { idx, slot in
            Slot(widgetId: slot.rawValue, x: 0, y: idx, w: 12, h: 4)
        }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "users.saveDashboardLayout",
                input: In(role: "COMPLIANCE_OFFICER", layout: payload)
            )
        } catch { }
    }

    private func reconcile(_ saved: [ComplianceWidgetSlot]) -> [ComplianceWidgetSlot] {
        var seen = Set<ComplianceWidgetSlot>(); var out: [ComplianceWidgetSlot] = []
        for s in saved where !seen.contains(s) { out.append(s); seen.insert(s) }
        for s in ComplianceWidgetSlot.allCases where !seen.contains(s) { out.append(s) }
        return out
    }
}

#Preview("900 · Compliance home · Night") { ComplianceOfficerHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("900 · Compliance home · Afternoon") { ComplianceOfficerHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
