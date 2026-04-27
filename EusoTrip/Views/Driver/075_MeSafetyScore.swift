//
//  075_MeSafetyScore.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · safety score)
//
//  Screen 075 · Me · Safety Score — the driver's composite safety
//  reputation. Hero dial with the aggregate 0-100 score + band label
//  (Excellent / Good / Needs Improvement), a three-row category strip
//  (Driving / Compliance / Vehicle Care), and a recent-events log
//  sourced from the driver's inspection history.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Every score + event comes from the live `safety.getDriverScoreDetail`
//      tRPC procedure — MCP-verified at
//      `frontend/server/routers/safety.ts:820`. The server computes
//      compliance + vehicle-care scores in-line from inspection rows
//      joined on `drivers.userId`, so the numbers match what dispatch
//      and carrier scorecards see. No client-side recomputation.
//
//    • Band labels keyed off server thresholds (≥90 excellent, ≥70
//      good, <70 needs improvement) for parity with 019 HOS + dispatch.
//
//    • Recent events are the last 5 inspection outcomes, ordered
//      newest-first. Status chip coloring mirrors the global rule:
//      gradient for "passed", warning-border for "failed", neutral
//      for everything else.
//
//    • Empty state is server-confirmed. A brand-new driver with no
//      inspection history + a null safety score lands on the
//      "No activity yet" hero rather than a "0 · Critical" hero —
//      because zero is meaningful (a real score), while "no data"
//      should not be painted as a failing grade.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero dial numerals + category
//         score chips. Brand.warning used only for below-70 bands
//         and failed events. Zero Brand.info/blue flat fills.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg), type
//         (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — store lands in `.error` via
//         `notConfigured` under the preview's no-baseURL runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Score band

private enum SafetyBand {
    case excellent, good, needsImprovement, noData

    init(score: Int, hasAnyActivity: Bool) {
        if !hasAnyActivity { self = .noData; return }
        if score >= 90 { self = .excellent; return }
        if score >= 70 { self = .good; return }
        self = .needsImprovement
    }

    var label: String {
        switch self {
        case .excellent:        return "Excellent"
        case .good:             return "Good"
        case .needsImprovement: return "Needs Improvement"
        case .noData:           return "No activity yet"
        }
    }
}

// MARK: - Screen root

struct MeSafetyScore: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = DriverSafetyScoreStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let detail):
                    heroDial(detail)
                    categoryStrip(detail)
                    recentEventsSection(detail)
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await seedAndRefresh() }
        .refreshable { await seedAndRefresh() }
        .onChange(of: session.user?.id) { _, newId in
            store.driverId = newId ?? ""
            Task { await store.refresh() }
        }
    }

    private func seedAndRefresh() async {
        store.driverId = session.user?.id ?? ""
        await store.refresh()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Safety Score")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Driving · Compliance · Vehicle Care")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 180)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.35))
                        .frame(height: 80)
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 56)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "shield",
            title: "No safety activity yet",
            subtitle: "Your score will appear after your first roadside inspection, completed run, or training module. Pull to refresh anytime."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load safety score")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await seedAndRefresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Hero dial

    private func heroDial(_ d: SafetyAPI.DriverScoreDetail) -> some View {
        let score = d.canonicalScore
        let band = SafetyBand(
            score: score,
            hasAnyActivity: score > 0 || !d.recentEvents.isEmpty
        )
        if band == .noData {
            return AnyView(emptyHero)
        }
        let fraction = max(0.0, min(1.0, Double(score) / 100.0))
        return AnyView(
            VStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .stroke(palette.tintNeutral.opacity(0.4), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            LinearGradient.diagonal,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(EType.numeric)
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        Text("/ 100")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .frame(width: 160, height: 160)

                bandChip(band)

                if !d.licenseNumber.isEmpty {
                    Text("CDL · \(d.licenseNumber)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        )
    }

    @ViewBuilder
    private func bandChip(_ band: SafetyBand) -> some View {
        switch band {
        case .excellent, .good:
            Text(band.label.uppercased())
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 4)
                .background(Capsule().fill(LinearGradient.diagonal))
        case .needsImprovement:
            Text(band.label.uppercased())
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 4)
                .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
        case .noData:
            Text(band.label.uppercased())
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 4)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Category strip

    @ViewBuilder
    private func categoryStrip(_ d: SafetyAPI.DriverScoreDetail) -> some View {
        if !d.categories.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CATEGORIES")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.s2) {
                    ForEach(d.categories) { cat in
                        categoryTile(cat)
                    }
                }
            }
        }
    }

    private func categoryTile(_ cat: SafetyAPI.ScoreCategory) -> some View {
        let fraction = max(0.0, min(1.0, Double(cat.score) / 100.0))
        return VStack(alignment: .leading, spacing: Space.s1) {
            Text(cat.name.uppercased())
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(cat.score)")
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Recent events

    @ViewBuilder
    private func recentEventsSection(_ d: SafetyAPI.DriverScoreDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !d.recentEvents.isEmpty {
                    Text("\(d.recentEvents.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if d.recentEvents.isEmpty {
                HStack(spacing: Space.s3) {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text("No roadside inspections or safety events in your history.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(d.recentEvents) { evt in
                        eventRow(evt)
                    }
                }
            }
        }
    }

    private func eventRow(_ e: SafetyAPI.ScoreEvent) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: iconFor(type: e.type))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(labelFor(type: e.type))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let pretty = prettyDate(e.date) {
                    Text(pretty)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            statusChip(e.status)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let label = status.replacingOccurrences(of: "_", with: " ").uppercased()
        switch status.lowercased() {
        case "passed", "pass":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "failed", "fail":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
        default:
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func iconFor(type: String) -> String {
        switch type.lowercased() {
        case "inspection":  return "magnifyingglass"
        case "incident":    return "exclamationmark.octagon"
        case "near_miss":   return "exclamationmark.triangle"
        case "training":    return "graduationcap"
        default:            return "dot.circle"
        }
    }

    private func labelFor(type: String) -> String {
        switch type.lowercased() {
        case "inspection":  return "Roadside inspection"
        case "incident":    return "Incident"
        case "near_miss":   return "Near miss"
        case "training":    return "Training module"
        default:            return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Disclosure footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How the score is computed")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Scores update from roadside inspections, incidents, vehicle care checks, and training completions. Dispatch, catalysts, and FMCSA-reporting tools see the same number — this is the real value, not a preview.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func prettyDate(_ iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: d)
    }
}

// MARK: - Screen wrapper

struct MeSafetyScoreScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeSafetyScore()
        } nav: {
            BottomNav(
                leading: driverNavLeading_075(),
                trailing: driverNavTrailing_075(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_075() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_075() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("075 · Me Safety Score · Night") {
    MeSafetyScoreScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("075 · Me Safety Score · Afternoon") {
    MeSafetyScoreScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
