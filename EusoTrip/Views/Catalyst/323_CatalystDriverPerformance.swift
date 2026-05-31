//
//  323_CatalystDriverPerformance.swift
//  EusoTrip — Catalyst · Driver Performance (brick 323).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/323 Catalyst Driver Performance.svg`.
//  Per-driver analytics drill-down — miles, MPG, util, rev/mi, period
//  toggle 30D/90D.
//
//  Wire bindings:
//    hrWorkforce.getDriverScorecard   — real per-driver scorecard
//

import SwiftUI

private struct DriverPerf: Decodable, Hashable {
    let driverId: String?
    let name: String?
    let companyName: String?
    let grade: String?              // "A+" / "A" / "B" / ...
    let milesPeriod: Double?        // total miles in period
    let mpg: Double?
    let mpgDelta: Double?           // change vs prior period
    let utilizationPct: Double?
    let revenuePerMile: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.driverId = try c.decodeIfPresent(String.self, forKey: .driverId)
        // Server returns driverName; iOS struct expects name
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? (try c.decodeIfPresent(String.self, forKey: .driverName))
        self.companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        // Server returns overallScore (number); iOS struct expects grade (letter).
        // Convert overallScore to letter grade: 90+ => A+, 80+ => A, 70+ => B, 60+ => C, <60 => F
        if let score = try c.decodeIfPresent(Double.self, forKey: .overallScore) {
            switch score {
            case 90...: self.grade = "A+"
            case 85..<90: self.grade = "A"
            case 80..<85: self.grade = "B+"
            case 75..<80: self.grade = "B"
            case 70..<75: self.grade = "C+"
            case 65..<70: self.grade = "C"
            default: self.grade = "F"
            }
        } else {
            self.grade = try c.decodeIfPresent(String.self, forKey: .grade)
        }
        self.milesPeriod = try c.decodeIfPresent(Double.self, forKey: .milesPeriod)
        self.mpg = try c.decodeIfPresent(Double.self, forKey: .mpg)
        self.mpgDelta = try c.decodeIfPresent(Double.self, forKey: .mpgDelta)
        self.utilizationPct = try c.decodeIfPresent(Double.self, forKey: .utilizationPct)
        self.revenuePerMile = try c.decodeIfPresent(Double.self, forKey: .revenuePerMile)
    }

    enum CodingKeys: String, CodingKey {
        case driverId
        case name
        case driverName
        case companyName
        case grade
        case overallScore
        case milesPeriod
        case mpg
        case mpgDelta
        case utilizationPct
        case revenuePerMile
    }
}

struct CatalystDriverPerformanceScreen: View {
    let theme: Theme.Palette
    let driverId: String

    var body: some View {
        Shell(theme: theme) { PerfBody(driverId: driverId) } nav: {
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

private struct PerfBody: View {
    let driverId: String
    @Environment(\.palette) private var palette
    @State private var perf: DriverPerf?
    @State private var period: Period = .ninetyD
    @State private var loading: Bool = true

    enum Period: String, CaseIterable { case thirtyD = "30D", ninetyD = "90D" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                identityCard
                kpiGrid
                periodToggle
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: period) { _, _ in Task { await load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · ANALYTICS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Driver performance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("DR-\(driverId) · \(period.rawValue) · ME").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Catalyst measures driver · same companyId both sides · clean Schedule C books")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var identityCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                    Text(initialsFor(perf?.name)).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(perf?.name ?? "—").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("\(perf?.companyName ?? "—") · DR-\(driverId)")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(perf?.grade ?? "—")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let miles = perf?.milesPeriod ?? 0
        let mpg = perf?.mpg ?? 0
        let mpgDelta = perf?.mpgDelta ?? 0
        let util = perf?.utilizationPct ?? 0
        let revPerMi = perf?.revenuePerMile ?? 0
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("MILES", "\(Int(miles).formatted(.number))", "\(period.rawValue) total", .blue)
            kpi("MPG", String(format: "%.1f", mpg),
                (mpgDelta >= 0 ? "+" : "") + String(format: "%.1f", mpgDelta) + " vs prior",
                mpgDelta >= 0 ? .green : .red)
            kpi("UTIL", "\(Int(util))%", util >= 85 ? "loaded · ≥85" : "below target", util >= 85 ? .green : .orange)
            kpi("REV/MI", String(format: "$%.2f", revPerMi), "gross · per mile", .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var periodToggle: some View {
        HStack(spacing: 6) {
            ForEach(Period.allCases, id: \.self) { p in
                Button { period = p } label: {
                    Text(p.rawValue)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(period == p ? .white : palette.textSecondary)
                        .background(period == p ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
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
        struct In: Encodable { let driverId: String; let period: String }
        do {
            perf = try await EusoTripAPI.shared.query(
                "hrWorkforce.getDriverScorecard",
                input: In(driverId: driverId, period: period.rawValue.lowercased())
            )
        } catch { /* */ }
    }
}

#Preview("323 Perf · Dark")  { CatalystDriverPerformanceScreen(theme: Theme.dark, driverId: "001").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("323 Perf · Light") { CatalystDriverPerformanceScreen(theme: Theme.light, driverId: "001").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
