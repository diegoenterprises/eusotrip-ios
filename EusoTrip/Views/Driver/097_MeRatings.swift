//
//  097_MeRatings.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Ratings)
//
//  Screen 097 · Me · Ratings — the driver's reputation cockpit.
//  Hero shows overall rating + review count (as driver + catalyst)
//  with a trend arrow. Reviews list supports sort (recent /
//  highest / lowest), each row shows the reviewer + score stars +
//  comment + load reference. Respond + report actions per row.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Summary from `ratings.getMySummary` — MCP-verified at
//      `frontend/server/routers/ratings.ts`. Server aggregates
//      the driver's received `ratings` rows (category=overall)
//      and returns per-role rollups + given/received this month.
//    • Reviews from `ratings.getReviews` for `entityType=user` +
//      the signed-in user id. Paginated by the server; we pull
//      20 at a time and render newest-first by default.
//    • Respond (`ratings.respond`) + report (`ratings.report`)
//      both hit the real server mutations.
//    • No fabricated star counts, no placeholder reviewer names.
//      "Anonymous" in a row is because the reviewer marked their
//      submission anonymous server-side — not client-side.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero stars + respond CTA.
//         Brand.warning on <3-star rows. Brand.magenta on <2-star
//         rows that are still open (no response).
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeRatings: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = RatingsStore()

    @State private var responding: RatingsAPI.Review?
    @State private var reporting: RatingsAPI.Review?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                summaryHero
                monthStrip
                sortRow
                reviewsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await seedAndRefresh() }
        .refreshable { await seedAndRefresh() }
        .onChange(of: session.user?.id) { _, newId in
            store.userId = newId ?? ""
            Task { await store.refresh() }
        }
        .onChange(of: store.sort) { _, _ in
            Task { await store.refresh() }
        }
        .sheet(item: $responding) { review in
            RespondSheet(review: review, store: store)
                .eusoSheetX()
        }
        .sheet(item: $reporting) { review in
            ReportSheet(review: review, store: store)
                .eusoSheetX()
        }
    }

    private func seedAndRefresh() async {
        store.userId = session.user?.id ?? ""
        await store.refresh()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Ratings")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Your reputation · sorted by the real reviews")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Hero

    private var summaryHero: some View {
        let s = store.summary?.asDriver
        let rating = s?.overallRating ?? 0
        let count = s?.totalReviews ?? 0
        let trend = (s?.recentTrend ?? "stable").lowercased()
        return VStack(spacing: Space.s3) {
            Text("AS DRIVER")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(count > 0 ? String(format: "%.1f", rating) : "—")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            starRow(rating: rating)
            HStack(spacing: 6) {
                Text("\(count) review\(count == 1 ? "" : "s")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                if count > 0 {
                    trendChip(trend)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    private func starRow(rating: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { i in
                let threshold = Double(i) + 0.5
                let filled = rating >= Double(i + 1)
                let half = !filled && rating >= threshold
                Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(rating > 0
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textTertiary))
            }
        }
    }

    @ViewBuilder
    private func trendChip(_ trend: String) -> some View {
        let (icon, tint): (String, Color) = {
            switch trend {
            case "up":   return ("arrow.up.right", .green)
            case "down": return ("arrow.down.right", Brand.magenta)
            default:     return ("equal", palette.textSecondary)
            }
        }()
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(trend.uppercased())
                .font(EType.micro)
                .tracking(1.1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 2)
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
    }

    // MARK: Month strip

    private var monthStrip: some View {
        let given = store.summary?.givenThisMonth ?? 0
        let received = store.summary?.receivedThisMonth ?? 0
        let catalyst = store.summary?.asCatalyst
        return HStack(spacing: Space.s2) {
            monthTile(
                label: "RECEIVED",
                value: "\(received)",
                sub: "this month"
            )
            monthTile(
                label: "GIVEN",
                value: "\(given)",
                sub: "this month"
            )
            if (catalyst?.totalReviews ?? 0) > 0 {
                monthTile(
                    label: "AS CATALYST",
                    value: String(format: "%.1f", catalyst?.overallRating ?? 0),
                    sub: "\(catalyst?.totalReviews ?? 0) reviews"
                )
            }
        }
    }

    private func monthTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Sort row

    private var sortRow: some View {
        HStack(spacing: Space.s2) {
            ForEach(RatingsAPI.Sort.allCases) { s in
                Button {
                    store.sort = s
                } label: {
                    Text(s.label)
                        .font(EType.caption)
                        .foregroundStyle(store.sort == s
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textSecondary))
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(
                                store.sort == s ? Color.clear : palette.textTertiary.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                        .background(
                            Capsule().fill(store.sort == s
                                           ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                           : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Reviews

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REVIEWS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.reviews.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "star",
                    title: "No reviews yet",
                    subtitle: "Reviews from shippers / brokers / catalysts land here after delivered loads. Your rating surfaces on dispatch boards."
                )
            } else {
                ForEach(store.reviews) { r in
                    reviewCard(r)
                }
            }
        }
    }

    private func reviewCard(_ r: RatingsAPI.Review) -> some View {
        let low = r.score < 3
        let critical = r.score < 2
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.reviewerName ?? "User")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    HStack(spacing: 4) {
                        starRow(rating: r.score)
                        Text(String(format: "%.1f", r.score))
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let loadId = r.loadId {
                        Text("Load #\(loadId)")
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                            .monospacedDigit()
                    }
                    Text(relativeTime(r.createdAt))
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if !r.comment.isEmpty {
                Text(r.comment)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cat = r.category, !cat.isEmpty, cat != "overall" {
                Text(cat.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                Button {
                    responding = r
                } label: {
                    Label("Respond", systemImage: "arrowshape.turn.up.left")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Button {
                    reporting = r
                } label: {
                    Label("Report", systemImage: "flag")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(palette.textTertiary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(
                            critical ? Brand.magenta.opacity(0.6)
                                     : (low ? Brand.warning.opacity(0.6) : palette.borderFaint),
                            lineWidth: critical || low ? 1 : 0.5
                        )
                )
        )
    }

    // MARK: Footer

    private var footer: some View {
        Text("Ratings drive load matching. Drivers ≥4.5 surface first on dispatch boards. Responses post publicly alongside the review.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func relativeTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}

// MARK: - Respond sheet

private struct RespondSheet: View {
    @Environment(\.dismiss) private var dismiss
    let review: RatingsAPI.Review
    @ObservedObject var store: RatingsStore

    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    Text(review.reviewerName ?? "User")
                        .font(EType.bodyStrong)
                    Text(review.comment)
                        .foregroundStyle(.secondary)
                        .font(EType.caption)
                }
                Section("Your response") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                    Text("\(500 - text.count) characters left")
                        .font(EType.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Respond")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.respond(
                                to: review,
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            dismiss()
                        }
                    } label: {
                        if store.respondingId == review.id {
                            ProgressView()
                        } else {
                            Text("Post").fontWeight(.semibold)
                        }
                    }
                    .disabled(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || text.count > 500
                        || store.respondingId == review.id
                    )
                }
            }
        }
    }
}

// MARK: - Report sheet

private struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let review: RatingsAPI.Review
    @ObservedObject var store: RatingsStore

    @State private var reason: ReportReason = .inappropriate
    @State private var details: String = ""

    enum ReportReason: String, CaseIterable, Identifiable {
        case inappropriate, false_info, spam, harassment, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .inappropriate: return "Inappropriate"
            case .false_info:    return "False information"
            case .spam:          return "Spam"
            case .harassment:    return "Harassment"
            case .other:         return "Other"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review") {
                    Text(review.reviewerName ?? "User")
                        .font(EType.bodyStrong)
                    Text(review.comment)
                        .foregroundStyle(.secondary)
                        .font(EType.caption)
                }
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Details (optional)") {
                    TextEditor(text: $details)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Report review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.report(
                                review: review,
                                reason: reason.rawValue,
                                details: details.isEmpty ? nil : details
                            )
                            dismiss()
                        }
                    } label: {
                        Text("Report").fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Screen wrapper

struct MeRatingsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeRatings()
        } nav: {
            BottomNav(
                leading: driverNavLeading_097(),
                trailing: driverNavTrailing_097(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_097() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_097() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("097 · Ratings · Night") {
    MeRatingsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("097 · Ratings · Afternoon") {
    MeRatingsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
