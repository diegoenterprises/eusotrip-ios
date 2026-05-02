//
//  712_DispatchReportsHub.swift
//  EusoTrip — Dispatch · Reports hub (custom · scheduled · 600+ data points).
//
//  Mirrors Dispatch Commodity's "automated custom reports + delivery to
//  recipients" feature. Wired to reports.list (catalog), reports.generate
//  (run with date-range), reports.scheduleRecurring (cron-style delivery).
//  Per-role: dispatch sees operations/financial/compliance categories.
//

import SwiftUI

struct DispatchReportsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ReportsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct ReportTemplate: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let description: String?
}

private struct ReportsBody: View {
    @Environment(\.palette) private var palette
    @State private var templates: [ReportTemplate] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var category: String = "all"
    @State private var generating: String? = nil
    @State private var actionError: String? = nil
    @State private var lastRun: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                segmented
                if let m = lastRun { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
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
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · REPORTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reports hub").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Operations · financial · compliance · custom. PDF / CSV / XLSX delivery.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var segmented: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["all","operations","financial","compliance","custom"], id: \.self) { code in
                    Button { category = code; Task { await load() } } label: {
                        Text(code.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(category == code ? .white : palette.textSecondary)
                            .background(category == code ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading templates…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if templates.isEmpty {
            EusoEmptyState(systemImage: "doc.text", title: "No templates", subtitle: "No reports in this category.")
        } else {
            ForEach(templates) { t in
                LifecycleCard {
                    LifecycleSection(label: t.name.uppercased(), icon: iconFor(t.category))
                    Text(t.description ?? "").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { Task { await generate(t) } } label: {
                            HStack(spacing: 4) {
                                if generating == t.id { ProgressView().tint(.white) }
                                Image(systemName: "play.fill").foregroundStyle(.white)
                                Text(generating == t.id ? "Generating…" : "RUN").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }.buttonStyle(.plain).disabled(generating != nil)
                        Text(t.category.uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(palette.bgCard).clipShape(Capsule())
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func iconFor(_ category: String) -> String {
        switch category {
        case "operations": return "shippingbox.fill"
        case "financial":  return "dollarsign.circle.fill"
        case "compliance": return "checkmark.shield.fill"
        case "custom":     return "wand.and.stars"
        default:           return "doc.text"
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let category: String? }
        do {
            let r: [ReportTemplate] = try await EusoTripAPI.shared.query("reports.list", input: In(category: category == "all" ? nil : category))
            templates = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generate(_ t: ReportTemplate) async {
        generating = t.id; actionError = nil
        struct DateRange: Encodable { let start: String; let end: String }
        struct In: Encodable { let reportType: String; let format: String; let dateRange: DateRange }
        struct Out: Decodable { let reportId: String?; let status: String?; let rowCount: Int? }
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        do {
            let r: Out = try await EusoTripAPI.shared.mutation("reports.generate", input: In(reportType: t.id, format: "pdf", dateRange: DateRange(start: formatter.string(from: start), end: formatter.string(from: now))))
            lastRun = "\(t.name) queued · id \(r.reportId ?? "—") · rows \(r.rowCount ?? 0)."
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        generating = nil
    }
}

#Preview("712 · Reports hub · Night") { DispatchReportsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("712 · Reports hub · Afternoon") { DispatchReportsHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

