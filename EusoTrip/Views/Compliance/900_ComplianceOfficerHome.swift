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

private struct DriverComplianceRow: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let expiringCount: Int?
    let violationCount: Int?
}

private struct ComplianceHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: ComplianceDash? = nil
    @State private var topExpiring: ExpiringDocPriority? = nil
    @State private var driverCompliance: [DriverComplianceRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "compliance.home.widgetOrder"
    private let complianceCanonicalOrder: [String] = ["expiringDocs", "violations_overview", "driver_compliance", "news"]

    private func complianceHomeRender(_ id: String) -> AnyView {
        switch id {
        case "expiringDocs":
            if let e = topExpiring { AnyView(expiringWidget(e)) } else { AnyView(EmptyView()) }
        case "violations_overview":
            AnyView(violationsOverviewWidget)
        case "driver_compliance":
            AnyView(driverComplianceWidget)
        case "news":
            AnyView(NewsCarouselWidget())
        default:
            AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                // Canonical lead: morning brief → weather. Driver 010 is the
                // baseline; every role home opens with these two cards.
                RoleHomeIntro()
                if loading { LifecycleCard { Text("Loading compliance score…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = dash {
                    hero(d)
                    statsGrid(d)
                    HomeWidgetGrid(
                        canonicalOrder: complianceCanonicalOrder,
                        role: "COMPLIANCE_OFFICER",
                        storageKey: widgetLayoutKey,
                        render: { id in complianceHomeRender(id) }
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Bespoke hero eyebrow — gradient role chip ("✦ COMPLIANCE · DASHBOARD")
    // on the left, a tertiary context-caps line on the right, then the
    // greeting title underneath as a brand-gradient hero. Matches the
    // DriverHome (010) idiom so every role home reads as one family: the
    // sparkle glyph is the SVG's defining header motif (§4.3, used once
    // per surface), the title rides LinearGradient.diagonal so it reads
    // EusoTrip-native in both Night and Afternoon.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("✦ COMPLIANCE · DASHBOARD")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: Space.s2)
                Text("FLEET · OVERSIGHT")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text("Fleet compliance")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // Hero overall-score card — full brand-gradient fill (the one surface
    // on the home that earns the saturated gradient, like the active-load
    // amount on DriverHome). Elevated with a paired blue/magenta glow lift
    // (matching ActiveCard) + Radius.lg so it reads as a floating hero
    // rather than a flat gradient block.
    private func hero(_ d: ComplianceDash) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OVERALL SCORE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text("\(d.overallScore ?? d.complianceScore ?? 0)").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("COMPLIANT \(d.compliant ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("EXPIRING \(d.expiring ?? d.expiringDocs ?? 0)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("TREND \((d.trend ?? "—").uppercased())").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: Brand.blue.opacity(0.28), radius: 14, x: -4, y: 4)
        .shadow(color: Brand.magenta.opacity(0.28), radius: 14, x: 4, y: 4)
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

    // MARK: - Violations overview widget

    @ViewBuilder
    private var violationsOverviewWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("VIOLATIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
            }
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let d = dash {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "VIOLATIONS", value: "\(d.violations ?? 0)",
                                      icon: "exclamationmark.triangle", danger: (d.violations ?? 0) > 0)
                    LifecycleStatTile(label: "OVERDUE",    value: "\(d.overdueItems ?? 0)",
                                      icon: "calendar.badge.exclamationmark", danger: (d.overdueItems ?? 0) > 0)
                    LifecycleStatTile(label: "TREND",      value: (d.trend ?? "—").uppercased(),
                                      icon: "arrow.up.right")
                }
            } else {
                EusoEmptyState(systemImage: "checkmark.shield", title: "No violations data",
                               subtitle: "Violations and overdue items will appear here.")
            }
        }
    }

    // MARK: - Driver compliance widget

    @ViewBuilder
    private var driverComplianceWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                if !driverCompliance.isEmpty {
                    Text("\(driverCompliance.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if loading {
                VStack(spacing: Space.s2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Color.clear
                            .frame(height: 52)
                            .eusoRow(radius: Radius.md)
                    }
                }
            } else if driverCompliance.isEmpty {
                EusoEmptyState(systemImage: "person.crop.circle.badge.checkmark",
                               title: "No driver records",
                               subtitle: "Driver compliance records will appear here once loaded.")
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(driverCompliance.prefix(5)) { row in
                        driverComplianceRow(row)
                    }
                }
            }
        }
    }

    private func driverComplianceRow(_ row: DriverComplianceRow) -> some View {
        let statusColor: Color = {
            switch (row.status ?? "").lowercased() {
            case "compliant":   return Brand.success
            case "expiring":    return Brand.warning
            case "violation":   return Brand.danger
            default:            return palette.textTertiary
            }
        }()
        return HStack(spacing: Space.s3) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name ?? "—")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let exp = row.expiringCount, exp > 0 {
                        Text("\(exp) expiring").font(EType.caption).foregroundStyle(Brand.warning)
                    }
                    if let viol = row.violationCount, viol > 0 {
                        Text("\(viol) violation\(viol == 1 ? "" : "s")").font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
            }
            Spacer()
            Text((row.status ?? "—").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(statusColor.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        // Bespoke nested row surface — iridescent blue→magenta hairline
        // (whisper intensity) instead of the flat palette.bgCard +
        // borderFaint box, so each driver row reads as a first-class
        // card on the home, matching the SVG card language.
        .eusoRow(radius: Radius.md)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            async let d: ComplianceDash = EusoTripAPI.shared.queryNoInput("compliance.getDashboardStats")
            async let exp: [ExpiringDocPriority] = EusoTripAPI.shared.query("compliance.getExpiringItems", input: In(limit: 10))
            async let drivers: [DriverComplianceRow] = EusoTripAPI.shared.queryNoInput("compliance.getDriverComplianceList")
            let (dash, items, driverList) = try await (d, exp, drivers)
            self.dash = dash
            self.topExpiring = items.sorted { ($0.daysRemaining ?? 999) < ($1.daysRemaining ?? 999) }.first
            self.driverCompliance = driverList
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("900 · Compliance home · Night") { ComplianceOfficerHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("900 · Compliance home · Afternoon") { ComplianceOfficerHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
