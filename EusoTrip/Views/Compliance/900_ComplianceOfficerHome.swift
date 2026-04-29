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

private struct ComplianceHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: ComplianceDash? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading compliance score…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = dash { hero(d); statsGrid(d); cellLinks }
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

    private var cellLinks: some View {
        VStack(spacing: 8) {
            link(icon: "calendar.badge.exclamationmark", label: "Expiring documents", screen: "901")
            link(icon: "exclamationmark.triangle.fill", label: "Recent violations", screen: "902")
            link(icon: "shield.lefthalf.filled", label: "Hazmat certifications", screen: "903")
            link(icon: "clock.fill", label: "HOS audit queue", screen: "904")
            link(icon: "stethoscope", label: "Medical certifications", screen: "905")
        }
    }

    private func link(icon: String, label: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let d: ComplianceDash = try await EusoTripAPI.shared.api.queryNoInput("compliance.getDashboardStats")
            dash = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("900 · Compliance home · Night") { ComplianceOfficerHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("900 · Compliance home · Afternoon") { ComplianceOfficerHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
