//
//  325_CatalystDriverOnboarding.swift
//  EusoTrip — Catalyst · Driver Onboarding (brick 325).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/325 Catalyst Driver Onboarding.svg`.
//  Per-driver §391 DQ-file onboarding ledger — same-companyId
//  owner-op case + multi-driver carriers.
//
//  Wire bindings:
//    onboarding.getSteps(driverId:)    — §391 cleared / due / missing
//    onboarding.getProgress(driverId:) — header counts
//

import SwiftUI

private struct OnboardingStep: Decodable, Hashable, Identifiable {
    let id: String
    let title: String?
    let summary: String?
    let status: String?     // cleared / due / missing / pending
    let regCitation: String?
    let dueAt: String?
    let clearedAt: String?
}

private struct OnboardingProgress: Decodable, Hashable {
    let totalSteps: Int?
    let clearedSteps: Int?
    let onboardedDays: Int?
    let hiredAt: String?
    let dueWithin30d: Int?
    let missingCount: Int?
}

struct CatalystDriverOnboardingScreen: View {
    let theme: Theme.Palette
    let driverId: String
    let driverName: String?

    init(theme: Theme.Palette, driverId: String, driverName: String? = nil) {
        self.theme = theme
        self.driverId = driverId
        self.driverName = driverName
    }

    var body: some View {
        Shell(theme: theme) { OnboardingBody(driverId: driverId, driverName: driverName) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Drivers", systemImage: "person.3.fill",  isCurrent: true),
                           NavSlot(label: "Me",      systemImage: "person",         isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct OnboardingBody: View {
    let driverId: String
    let driverName: String?
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", cleared = "Cleared", due = "Due", missing = "Missing"
    }

    @State private var steps: [OnboardingStep] = []
    @State private var progress: OnboardingProgress?
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var clearedCount: Int { steps.filter { ($0.status ?? "") == "cleared" }.count }
    private var dueCount: Int     { steps.filter { ($0.status ?? "") == "due" }.count }
    private var missingCount: Int { steps.filter { ($0.status ?? "") == "missing" }.count }

    private var filtered: [OnboardingStep] {
        guard filter != .all else { return steps }
        return steps.filter { ($0.status ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                identityCard
                kpiGrid
                filterTabs
                if loading && steps.isEmpty {
                    LifecycleCard { Text("Loading onboarding…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.seal", title: "All clear in this lens", subtitle: "DQ file steps land here as the driver progresses.")
                } else {
                    Text("\(steps.count) STEPS · §391 · RANKED BY URGENCY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { s in stepCard(s) }
                }
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
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · ONBOARDING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Driver onboarding").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            let total = progress?.totalSteps ?? steps.count
            let cleared = progress?.clearedSteps ?? clearedCount
            Text("DR-\(driverId) · §391 · \(cleared)/\(total) STEPS")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · §391 CLEAN BOOKS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Catalyst onboards driver · same companyId both sides · clean §391 DQ file")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var identityCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                    Text(initialsFor(driverName)).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(driverName ?? "Driver").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    let hired = progress?.hiredAt ?? "—"
                    Text("DR-\(driverId) · hired \(shortDate(hired))")
                        .font(.caption.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                Text("A+").font(.system(size: 28, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let onboarded = progress?.onboardedDays ?? 0
        let cleared = progress?.clearedSteps ?? clearedCount
        let total = progress?.totalSteps ?? steps.count
        let pct = total > 0 ? Int(Double(cleared) / Double(total) * 100) : 0
        let due = progress?.dueWithin30d ?? dueCount
        let missing = progress?.missingCount ?? missingCount
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("ONBOARDED", "\(onboarded)d", progress?.hiredAt.map { "since \(shortDate($0))" } ?? "—", .blue)
            kpi("§391 STEPS", "\(cleared)/\(total)", "cleared · \(pct)%", .green)
            kpi("DUE",      "\(due)",       "≤ 30d · annual",       due > 0 ? .orange : .green)
            kpi("MISSING",  "\(missing)",   "action req",           missing > 0 ? .red : .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let count: Int = {
                    switch f {
                    case .all: return steps.count
                    case .cleared: return clearedCount
                    case .due: return dueCount
                    case .missing: return missingCount
                    }
                }()
                Button { filter = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        Text("· \(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(filter == f ? .white : palette.textSecondary)
                    .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func stepCard(_ s: OnboardingStep) -> some View {
        let statusUpper = (s.status ?? "").uppercased()
        let statusColor: Color = {
            switch statusUpper {
            case "CLEARED":  return .green
            case "DUE":      return .orange
            case "MISSING":  return .red
            case "PENDING":  return .blue
            default:         return palette.textSecondary
            }
        }()
        return LifecycleCard(accentDanger: statusUpper == "MISSING") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.id).font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(statusUpper)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                        .foregroundStyle(statusColor)
                }
                Text(s.title ?? "Step").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                if let summary = s.summary { Text(summary).font(.caption).foregroundStyle(palette.textSecondary) }
                let parts: [String] = [
                    s.regCitation.map { "§\($0)" },
                    s.clearedAt.map { "cleared \(shortDate($0))" },
                    s.dueAt.map { "due \(shortDate($0))" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        return iso
    }

    private func initialsFor(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let s: Void = loadSteps()
        async let p: Void = loadProgress()
        _ = await (s, p)
    }

    private func loadSteps() async {
        struct In: Encodable { let driverId: String }
        do { steps = try await EusoTripAPI.shared.query("onboarding.getSteps", input: In(driverId: driverId)) } catch { /* */ }
    }
    private func loadProgress() async {
        struct In: Encodable { let driverId: String }
        do { progress = try await EusoTripAPI.shared.query("onboarding.getProgress", input: In(driverId: driverId)) } catch { /* */ }
    }
}

#Preview("325 Onboarding · Dark")  { CatalystDriverOnboardingScreen(theme: Theme.dark, driverId: "001", driverName: "Owner-op").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325 Onboarding · Light") { CatalystDriverOnboardingScreen(theme: Theme.light, driverId: "001", driverName: "Owner-op").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
