//
//  DriverHomeGlances.swift
//  EusoTrip — Four glance widgets added to 010 Driver Home:
//
//    1) eSangMorningBriefCard     — esangCoach.forDriver top item
//    2) PreTripDVIRStatusPill     — inspections.getDVIRHistory (today's pre-trip)
//    3) TheHaulWeeklyTile         — gamification.getProfile + missions.listMine
//    4) ComplianceCountdownStrip  — driverQualification.getExpiringItems (≤60d)
//
//  Every widget is backed by a real store that hits a real tRPC proc.
//  Loading states render branded motion. Empty states either hide the
//  widget (compliance) or render a neutral card with a CTA (morning
//  brief). No fake numbers.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. ESANG Morning Brief Card

/// Premium AI-coach glance. Pulls the top coaching item from the
/// signed-in driver's role+vertical+hazmat-aware feed and renders it
/// as a breathing gradient card directly under the top bar. Tapping
/// opens the full 087 Safety Coach sheet.
struct eSangMorningBriefCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @StateObject private var coach: SafetyCoachStore
    @State private var pulse: Bool = false
    @State private var showFull: Bool = false

    init() {
        // Single-item fetch — the home glance shows the most critical
        // coaching card only. The full 087 screen refetches at 6.
        let s = SafetyCoachStore()
        s.limit = 1
        _coach = StateObject(wrappedValue: s)
    }

    var body: some View {
        Button { showFull = true } label: { cardBody }
            .buttonStyle(.plain)
            .task { await coach.refresh() }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
            .sheet(isPresented: $showFull) {
                MeSafetyCoach()
                    .environment(\.palette, palette)
                    .eusoSheetX()
            }
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            esangGlyph
            VStack(alignment: .leading, spacing: 4) {
                header
                title
                bodyText
                footer
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient.diagonal.opacity(pulse ? 1.0 : 0.55),
                    lineWidth: 1.25
                )
        )
        .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.18 : 0.08),
                radius: 6, x: -2, y: 2)
        .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.18 : 0.08),
                radius: 6, x: 2, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: topItem?.id)
    }

    // MARK: Pieces

    private var topItem: eSangCoachAPI.CoachingItem? {
        switch coach.state {
        case .loaded(let resp): return resp.items.first
        default: return nil
        }
    }

    private var esangGlyph: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.diagonal)
                .frame(width: 40, height: 40)
                .scaleEffect(pulse ? 1.05 : 1.0)
                .shadow(color: Brand.magenta.opacity(pulse ? 0.55 : 0.25),
                        radius: pulse ? 10 : 4)
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(pulse ? 8 : -6))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("MORNING BRIEF")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("·")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Text("ESANG AI")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            if let sev = topItem?.severity {
                severityChip(sev)
            }
        }
    }

    private var title: some View {
        Group {
            if let t = topItem?.title {
                Text(t)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } else if case .loading = coach.state {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.bgCardSoft)
                    .frame(height: 14)
                    .opacity(pulse ? 0.85 : 0.55)
            } else {
                Text("Safety brief syncing with ESANG — try again in a moment.")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var bodyText: some View {
        Group {
            if let b = topItem?.body {
                Text(b)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let cfr = topItem?.cfr {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                    Text(cfr)
                        .font(EType.micro).tracking(0.4)
                }
                .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text("Open Safety Coach")
                    .font(EType.micro).tracking(0.4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(.top, 2)
    }

    private func severityChip(_ s: String) -> some View {
        let (label, color): (String, Color) = {
            switch s.lowercased() {
            case "critical": return ("CRITICAL", Brand.danger)
            case "watch":    return ("WATCH", Brand.warning)
            default:         return ("INFO", Brand.success)
            }
        }()
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
        }
    }
}

// MARK: - 2. Pre-trip DVIR Status Pill

/// Single-line strip showing whether today's pre-trip DVIR has been
/// filed. Three states: filed (green), required (amber + pulse), or
/// syncing. Tapping opens the 011 Pre-trip surface.
@MainActor
final class PreTripDVIRGlanceStore: ObservableObject {
    @Published private(set) var lastPreTrip: DVIRHistoryEntry?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    /// true when the most recent pre-trip entry was filed today in
    /// the user's local calendar.
    var filedToday: Bool {
        guard let d = lastPreTrip?.reportDate else { return false }
        return Self.isToday(isoOrDate: d)
    }

    /// minutes since the filing timestamp (capped at 24h). nil when
    /// there's no pre-trip filing to measure against.
    var minutesAgo: Int? {
        guard let d = lastPreTrip?.reportDate,
              let ts = Self.parseTimestamp(d)
        else { return nil }
        let mins = max(0, Int(Date().timeIntervalSince(ts) / 60))
        return min(mins, 60 * 24)
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let rows = try await EusoTripAPI.shared.inspections
                .getDVIRHistory(limit: 10)
            lastPreTrip = rows.first { ($0.reportType ?? "").lowercased() == "pretrip"
                || ($0.reportType ?? "").lowercased() == "pre_trip"
                || ($0.reportType ?? "").lowercased() == "pre-trip" }
        } catch {
            if !DynamicStoreUtil.isTransientCancellation(error) {
                lastError = error
            }
        }
    }

    private static func isToday(isoOrDate: String) -> Bool {
        guard let ts = parseTimestamp(isoOrDate) else { return false }
        return Calendar.current.isDateInToday(ts)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseTimestamp(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        // Fallback for YYYY-MM-DD server shape.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df.date(from: s)
    }
}

struct PreTripDVIRStatusPill: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = PreTripDVIRGlanceStore()
    @State private var pulse: Bool = false
    @State private var showSheet: Bool = false

    var body: some View {
        Button { showSheet = true } label: { pillBody }
            .buttonStyle(.plain)
            .task { await store.refresh() }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
            .sheet(isPresented: $showSheet) {
                PretripDVIR()
                    .environment(\.palette, palette)
                    .eusoSheetX()
            }
    }

    private var pillBody: some View {
        HStack(spacing: Space.s3) {
            statusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryText)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)
                Text(secondaryText)
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("PRE-TRIP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(pulse && !store.filedToday ? 0.25 : 0.15))
                .frame(width: 22, height: 22)
                .scaleEffect(pulse && !store.filedToday ? 1.15 : 1.0)
            Image(systemName: dotIcon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(dotColor)
        }
    }

    private var dotColor: Color {
        store.filedToday ? Brand.success : Brand.warning
    }

    private var dotIcon: String {
        store.filedToday ? "checkmark" : "clock.fill"
    }

    private var borderColor: Color {
        store.filedToday ? palette.borderFaint : Brand.warning.opacity(0.4)
    }

    private var primaryColor: Color {
        store.filedToday ? palette.textPrimary : Brand.warning
    }

    private var primaryText: String {
        if store.filedToday { return "Pre-trip DVIR filed" }
        if store.isLoading && store.lastPreTrip == nil { return "Checking pre-trip…" }
        return "Pre-trip required"
    }

    private var secondaryText: String {
        if store.filedToday, let mins = store.minutesAgo {
            return mins < 60
                ? "Logged \(mins) min ago · 49 CFR 396.11"
                : "Logged \(mins / 60)h \(mins % 60)m ago · 49 CFR 396.11"
        }
        return "Required each duty day before wheels turn"
    }
}

// MARK: - 3. The Haul Weekly Tile

/// Gamification glance for Home. Radial XP ring + active mission
/// count + current rank, gradient-bordered, routes into 060 dashboard.
struct TheHaulWeeklyTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = HaulStore()
    @State private var ringAnim: Double = 0
    @State private var showFull: Bool = false

    var body: some View {
        Button { showFull = true } label: { tileBody }
            .buttonStyle(.plain)
            .task { await store.refresh() }
            // The ring is driven from the real XP fraction. When the
            // profile lands (or moves via realtime XP gains), spring the
            // arc to the new fraction. Reduce-motion lands it instantly
            // on the final value — no fill sweep.
            .onChange(of: xpFraction) { _, newValue in
                applyRing(to: newValue)
            }
            .onAppear {
                // Land directly on the real fraction. While the profile
                // is still loading xpFraction == 0, so this seeds an
                // empty ring; the .onChange above then sweeps it to the
                // true value once data arrives — no animation to a
                // stale 0.
                if reduceMotion {
                    ringAnim = xpFraction
                } else if xpFraction > 0 {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.12)) {
                        ringAnim = xpFraction
                    }
                }
            }
            .sheet(isPresented: $showFull) {
                TheHaulDashboard()
                    .environment(\.palette, palette)
                    .eusoSheetX()
            }
    }

    // MARK: Derived

    private var profile: HaulAPI.Profile? { store.profile }

    private var activeMissions: Int {
        store.missions.filter { $0.status.lowercased() == "in_progress" }.count
    }

    private var completedMissions: Int {
        store.missions.filter {
            let s = $0.status.lowercased()
            return s == "completed" || s == "claimed"
        }.count
    }

    private var totalMissions: Int { store.missions.count }

    /// Real progress toward the next level: currentXp / (currentXp +
    /// xpToNextLevel). When the server reports xpToNextLevel == 0 the
    /// driver is leveled out, so the ring reads full (not empty).
    private var xpFraction: Double {
        guard let p = profile else { return 0 }
        if p.xpToNextLevel <= 0 { return p.currentXp > 0 ? 1 : 0 }
        let total = Double(p.currentXp + p.xpToNextLevel)
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(p.currentXp) / total))
    }

    /// Settles the ring to a target fraction. Spring for the live fill,
    /// or an instant set when Reduce Motion is on (final state only).
    private func applyRing(to value: Double) {
        if reduceMotion {
            ringAnim = value
        } else {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                ringAnim = value
            }
        }
    }

    private var rankLabel: String {
        if let r = profile?.rank, let total = profile?.totalUsers, total > 0 {
            return "#\(r) of \(total)"
        }
        if let r = profile?.rank { return "#\(r)" }
        return "—"
    }

    // MARK: Body

    private var tileBody: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            xpRing
            VStack(alignment: .leading, spacing: 4) {
                header
                levelRow
                missionsRow
                ctaRow
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.7), lineWidth: 1.25)
        )
        .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.18 : 0.08),
                radius: 6, x: -2, y: 2)
        .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.18 : 0.08),
                radius: 6, x: 2, y: 2)
    }

    private var xpRing: some View {
        ZStack {
            // track
            Circle()
                .stroke(palette.bgCardSoft, lineWidth: 6)
                .frame(width: 76, height: 76)
            // progress
            Circle()
                .trim(from: 0, to: CGFloat(ringAnim))
                .stroke(
                    LinearGradient.diagonal,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 76, height: 76)
            VStack(spacing: 0) {
                Text("LVL")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(profile?.level ?? 0)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "hexagon.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("THE HAUL")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            if let t = profile?.title, !t.isEmpty {
                Text(t.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        Capsule().stroke(LinearGradient.diagonal.opacity(0.6), lineWidth: 1)
                    )
            }
        }
    }

    private var levelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\((profile?.currentXp ?? 0).formatted())")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text("/ \((profile?.currentXp ?? 0) + (profile?.xpToNextLevel ?? 0), format: .number) XP")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
            Spacer(minLength: 0)
            Text(rankLabel)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
    }

    private var missionsRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            if totalMissions == 0 {
                Text("No active missions — tap to browse")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("\(completedMissions) of \(totalMissions) missions")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if activeMissions > 0 {
                    Text("· \(activeMissions) active")
                        .font(EType.caption)
                        .foregroundStyle(Brand.success)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 3) {
            Text("Open The Haul")
                .font(EType.micro).tracking(0.4)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(LinearGradient.diagonal)
        .padding(.top, 2)
    }
}

// MARK: - 4. Compliance Countdown Strip

/// Driver-own DQ + permit expirations within 60 days. Silent when
/// nothing is expiring (returns EmptyView from body). When it fires
/// the strip surfaces 1–2 of the soonest items and a "see all" CTA
/// that opens DQ File.
@MainActor
final class ComplianceCountdownStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let daysRemaining: Int
        let cfr: String?
        let source: Source
        enum Source { case dq, permit }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    func refresh(driverId: String) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        async let dqItems: [DriverQualificationAPI.ExpiringItem] =
            (try? EusoTripAPI.shared.dq.getExpiringItems(daysAhead: 60)) ?? []
        async let permItems: [PermitsAPI.ExpiringPermit] =
            (try? EusoTripAPI.shared.permits.getExpiring(days: 60)) ?? []

        let (dq, perms) = await (dqItems, permItems)

        let selfIdInt = Int(driverId)
        let dqFiltered: [DriverQualificationAPI.ExpiringItem] = {
            guard let id = selfIdInt else { return dq }
            return dq.filter { $0.driverId == id }
        }()

        let dqMapped: [Item] = dqFiltered.map {
            Item(
                id: "dq-\($0.id)",
                label: Self.dqLabel(for: $0.type),
                daysRemaining: $0.daysRemaining,
                cfr: Self.dqCFR(for: $0.type),
                source: .dq
            )
        }

        let permsMapped: [Item] = perms.map { p in
            let label = (p.type.map(Self.permitLabel)) ?? "Permit"
            return Item(
                id: "permit-\(p.id)",
                label: label,
                daysRemaining: p.daysRemaining,
                cfr: nil,
                source: .permit
            )
        }

        items = (dqMapped + permsMapped)
            .sorted { $0.daysRemaining < $1.daysRemaining }
    }

    private static func dqLabel(for type: String) -> String {
        switch type.lowercased() {
        case "cdl", "license":     return "CDL"
        case "medical_card",
             "medicalcard",
             "medical":            return "Medical card"
        case "hazmat":              return "Hazmat endorsement"
        case "twic":                return "TWIC"
        case "drug_test":           return "Drug test"
        case "mvr":                 return "MVR"
        default:                    return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func dqCFR(for type: String) -> String? {
        switch type.lowercased() {
        case "cdl", "license":      return "49 CFR 391.11"
        case "medical_card",
             "medicalcard",
             "medical":             return "49 CFR 391.45"
        case "hazmat":              return "49 CFR 383.93"
        case "twic":                return "33 CFR 105"
        default:                    return nil
        }
    }

    private static func permitLabel(_ type: String) -> String {
        switch type.lowercased() {
        case "ifta":           return "IFTA"
        case "ucr":            return "UCR"
        case "ny_hut", "nyhut": return "NY HUT"
        case "ky_intrastate":  return "KY"
        case "oversize",
             "overweight":     return "Oversize/Overweight"
        default:               return type.uppercased().replacingOccurrences(of: "_", with: " ")
        }
    }
}

struct ComplianceCountdownStrip: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = ComplianceCountdownStore()
    @State private var pulse: Bool = false
    @State private var showDQ: Bool = false
    @State private var showPermits: Bool = false

    var body: some View {
        Group {
            if store.items.isEmpty {
                EmptyView()
            } else {
                stripBody
            }
        }
        .task {
            if let uid = session.user?.id {
                await store.refresh(driverId: uid)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
        .sheet(isPresented: $showDQ) {
            MeDQFile()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        .sheet(isPresented: $showPermits) {
            MePermits()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    private var stripBody: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                Text("COMPLIANCE WATCH")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(store.items.count) expiring")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(store.items.prefix(3)) { item in
                    row(item)
                    if item.id != store.items.prefix(3).last?.id {
                        Divider().overlay(palette.borderFaint).padding(.leading, 42)
                    }
                }
                if store.items.count > 3 {
                    moreRow(extras: store.items.count - 3)
                }
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(urgencyColor.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func row(_ item: ComplianceCountdownStore.Item) -> some View {
        Button {
            switch item.source {
            case .dq:     showDQ = true
            case .permit: showPermits = true
            }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(itemColor(item).opacity(0.14))
                    Image(systemName: itemGlyph(item))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(itemColor(item))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(daysCopy(item.daysRemaining))
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(itemColor(item))
                        if let cfr = item.cfr {
                            Text("· \(cfr)")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func moreRow(extras: Int) -> some View {
        Button { showDQ = true } label: {
            HStack {
                Text("+\(extras) more expiring in the next 60 days")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(palette.bgCardSoft.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func itemColor(_ item: ComplianceCountdownStore.Item) -> Color {
        if item.daysRemaining <= 7 { return Brand.danger }
        if item.daysRemaining <= 30 { return Brand.warning }
        return Brand.blue
    }

    private func itemGlyph(_ item: ComplianceCountdownStore.Item) -> String {
        switch item.source {
        case .dq:     return "person.text.rectangle"
        case .permit: return "doc.badge.clock"
        }
    }

    private func daysCopy(_ days: Int) -> String {
        if days <= 0 { return "EXPIRED" }
        if days == 1 { return "1 day left" }
        return "\(days) days left"
    }

    private var urgencyColor: Color {
        guard let soonest = store.items.first else { return Brand.success }
        if soonest.daysRemaining <= 7 { return Brand.danger }
        if soonest.daysRemaining <= 30 { return Brand.warning }
        return Brand.blue
    }
}
