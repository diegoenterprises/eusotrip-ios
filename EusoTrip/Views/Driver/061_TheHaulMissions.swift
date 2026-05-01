//
//  061_TheHaulMissions.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · missions)
//
//  Screen 061 · The Haul · Missions — the dedicated mission dashboard
//  that deepens the 060 "Active missions" preview card. Promotes the
//  Me → Haul → Missions sub-route from the sheet-only `MeMissionsView`
//  into a full-screen workspace where the driver can:
//
//    • Filter the full roster via chips (All / Active / Claimable /
//      Available) backed by the server's three-bucket response.
//    • Start an untouched "Available" mission inline.
//    • Open a mission and claim its reward the moment progress hits 100%.
//    • Pull-to-refresh to reconcile progress after a trip clears a mission.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every row on this surface originates from `gamification.getMissions`
//      via the new `TheHaulMissionsStore` — zero seeded mission titles,
//      codes, targets, rewards, or progress values anywhere in the file.
//    • The sheet's claim / start CTAs call `gamification.claimMissionReward`
//      and `gamification.startMission` respectively. When the backend
//      rejects with `success: false`, the server's `message` string is
//      surfaced verbatim in a toast.
//    • When the server returns three empty buckets, the screen renders
//      the canonical `EusoEmptyState` primitive. There are no placeholder
//      mission cards or "coming soon" copy baked into the view.
//    • Per §16 SKILL.md gamification slice: `rewardType == "cash"` /
//      `"miles"` is shown in the reward chip for transparency but NEVER
//      accompanied by a "cash added" confirmation — the loot_crates /
//      miles_transactions writers do not yet exist on the backend.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal everywhere brand accent is needed —
//         filter chip selection, progress bar, claim CTA. Zero
//         `Brand.info` / `Brand.blue` fills.
//    §3   Numbers-first — reward amounts and progress % are the primary
//         visual anchors of each row. ETA strings are demoted to uppercase
//         micro-caps next to the progress count.
//    §4   Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg`),
//         type (`EType.*`).
//    §5   Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//         `palette.bgCard/bgPage`, `palette.borderFaint`. Never hardcoded
//         `Color.gray` / `Color.black` / `Color.white` (except shadow
//         opacity + CTA fg, which remain `.white` by doctrine).
//    §7   Ternary ShapeStyle expressions wrap in `AnyShapeStyle`.
//    §10  Previews compile in isolation — unauthenticated session hydrates
//         the live store to `.error` (unauthenticated) or `.empty` so the
//         preview renders the branded empty path without the network.
//

import SwiftUI

// MARK: - Screen

struct TheHaulMissions: View {
    @Environment(\.palette) var palette

    @StateObject private var store = TheHaulMissionsStore()

    /// Active filter chip. `nil` = "All" (no bucket filter).
    @State private var filter: TheHaulMissionsStore.Bucket? = nil

    /// The currently-opened mission's row id. Drives the mission detail
    /// sheet. Int? because we key off the server's numeric id.
    @State private var openMissionId: Int? = nil

    /// Toast message shown after a start/claim call. Auto-hides in 3s.
    @State private var toast: String? = nil
    @State private var toastIsError: Bool = false
    @State private var toastTask: Task<Void, Never>? = nil

    /// True while a start/claim call is in flight — disables the row CTAs
    /// so the driver can't double-tap during the round-trip.
    @State private var inFlightMissionId: Int? = nil

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    header
                    filterChipsRow
                    bodyContent
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s8)
            }
            .refreshable { await store.refresh() }

            if let toast {
                toastBanner(toast)
                    .padding(.top, Space.s3)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task { await store.refresh() }
        .sheet(item: bindingForDetailSheet()) { row in
            MissionDetailSheet(
                row: row,
                isInFlight: inFlightMissionId == row.id,
                onStart: { Task { await start(row) } },
                onClaim: { Task { await claim(row) } }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .eusoCloseX()
        }
    }

    // MARK: Detail-sheet binding
    //
    // `sheet(item:)` needs a Binding<Row?>. Because `Row` isn't Identifiable
    // off its id alone at the struct level (we keep the underlying id as
    // an Int), we wrap the lookup in a tiny Binding that resolves the
    // current snapshot at read-time.
    private func bindingForDetailSheet() -> Binding<TheHaulMissionsStore.Row?> {
        Binding(
            get: {
                guard let id = openMissionId,
                      case .loaded(let snap) = store.state else { return nil }
                return snap.rows(for: nil).first(where: { $0.id == id })
            },
            set: { newValue in
                openMissionId = newValue?.id
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THE HAUL · MISSIONS")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)
            Text("Your roster")
                .font(EType.h2)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            // Secondary caption — "N active · M ready to claim · K available"
            // assembled from the server's three buckets. Collapses gracefully
            // when any bucket is empty.
            if case .loaded(let snap) = store.state {
                Text(summaryLine(for: snap))
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    private func summaryLine(for snap: TheHaulMissionsStore.Snapshot) -> String {
        var parts: [String] = []
        if !snap.active.isEmpty    { parts.append("\(snap.active.count) active") }
        if !snap.completed.isEmpty { parts.append("\(snap.completed.count) ready to claim") }
        if !snap.available.isEmpty { parts.append("\(snap.available.count) available") }
        return parts.isEmpty ? "No missions on your board right now." : parts.joined(separator: " · ")
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                filterChip(label: "All", isOn: filter == nil) { filter = nil }
                ForEach(TheHaulMissionsStore.Bucket.allCases) { b in
                    filterChip(
                        label: b.label,
                        isOn: filter == b,
                        badge: bucketBadge(b)
                    ) { filter = b }
                }
            }
        }
    }

    private func bucketBadge(_ b: TheHaulMissionsStore.Bucket) -> Int? {
        guard case .loaded(let snap) = store.state else { return nil }
        let count = snap.rows(for: b).count
        return count > 0 ? count : nil
    }

    @ViewBuilder
    private func filterChip(
        label: String,
        isOn: Bool,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(EType.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isOn ? palette.textPrimary : palette.textSecondary)
                if let badge {
                    Text("\(badge)")
                        .font(EType.micro.monospacedDigit())
                        .tracking(0.4)
                        .foregroundColor(isOn ? palette.textPrimary : palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(palette.tintNeutral.opacity(isOn ? 0.35 : 0.2))
                        )
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        isOn
                        ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                        : AnyShapeStyle(palette.bgCard)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isOn
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Body content — list / empty / error / loading

    @ViewBuilder
    private var bodyContent: some View {
        switch store.state {
        case .loading:
            inlineLoading
        case .error(let err):
            inlineError(err: err) {
                Task { await store.refresh() }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "flag.checkered",
                title: "No missions on your board",
                subtitle: "New missions rotate in weekly. Check back after your next haul.",
                comingSoon: false
            )
            .padding(.top, Space.s4)
        case .loaded(let snap):
            let rows = snap.rows(for: filter)
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "Nothing in this filter",
                    subtitle: "Switch to All or another tab to see more missions.",
                    comingSoon: false
                )
                .padding(.top, Space.s4)
            } else {
                LazyVStack(spacing: Space.s3) {
                    ForEach(rows) { row in
                        missionCard(row)
                    }
                }
            }
        }
    }

    // MARK: - Mission card

    @ViewBuilder
    private func missionCard(_ row: TheHaulMissionsStore.Row) -> some View {
        let m = row.projection
        let raw = row.raw
        let inFlight = inFlightMissionId == row.id

        Button {
            openMissionId = row.id
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                // Line 1 — type chip + expiry
                HStack {
                    typeChip(for: raw.type, bucket: row.bucket)
                    Spacer(minLength: Space.s2)
                    if let expiresAt = m.expiresAt, !expiresAt.isEmpty {
                        Text("ENDS \(shortDay(expiresAt))")
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundColor(palette.textTertiary)
                    }
                }

                // Line 2 — mission title + reward chip
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(m.title)
                        .font(EType.bodyStrong)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: Space.s2)
                    if let r = m.rewardLabel, !r.isEmpty {
                        Text(r)
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1)
                    }
                }

                // Line 3 — description
                if let subtitle = m.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(2)
                }

                // Line 4 — progress bar + numeric current/target + bucket CTA
                progressRow(row: row, inFlight: inFlight)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func progressRow(
        row: TheHaulMissionsStore.Row,
        inFlight: Bool
    ) -> some View {
        let m = row.projection
        let raw = row.raw
        let target = raw.targetValue ?? 0
        let current = raw.currentProgress ?? 0

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.tintNeutral.opacity(0.6))
                        .frame(height: 6)
                    Capsule()
                        .fill(AnyShapeStyle(LinearGradient.diagonal))
                        .frame(
                            width: max(6, geo.size.width * CGFloat(m.progress)),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            HStack {
                Text(progressCaption(current: current, target: target, unit: raw.targetUnit))
                    .font(EType.micro.monospacedDigit())
                    .foregroundColor(palette.textTertiary)

                Spacer()

                // Row-bucket CTA — only the action that's valid for this
                // bucket is surfaced; the rest collapse.
                switch row.bucket {
                case .completed:
                    claimInlineCTA(row: row, inFlight: inFlight)
                case .available:
                    startInlineCTA(row: row, inFlight: inFlight)
                case .active:
                    Text("\(Int(m.progress * 100))%")
                        .font(EType.micro.monospacedDigit())
                        .foregroundColor(palette.textSecondary)
                }
            }
        }
    }

    private func progressCaption(current: Double, target: Double, unit: String?) -> String {
        guard target > 0 else { return unit?.isEmpty == false ? unit! : "—" }
        let u = unit?.isEmpty == false ? " \(unit!)" : ""
        // Print as integer when both sides are clean integers.
        if current.rounded() == current && target.rounded() == target {
            return "\(Int(current))/\(Int(target))\(u)"
        }
        return String(format: "%.1f/%.1f%@", current, target, u)
    }

    private func claimInlineCTA(row: TheHaulMissionsStore.Row, inFlight: Bool) -> some View {
        Button {
            Task { await claim(row) }
        } label: {
            HStack(spacing: 4) {
                if inFlight {
                    ProgressView().controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: "gift")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(inFlight ? "Claiming…" : "Claim")
                    .font(EType.micro)
                    .fontWeight(.semibold)
                    .tracking(1.0)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AnyShapeStyle(LinearGradient.diagonal))
            )
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .accessibilityLabel("Claim mission reward")
    }

    private func startInlineCTA(row: TheHaulMissionsStore.Row, inFlight: Bool) -> some View {
        Button {
            Task { await start(row) }
        } label: {
            HStack(spacing: 4) {
                if inFlight {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(inFlight ? "Starting…" : "Start")
                    .font(EType.micro)
                    .fontWeight(.semibold)
                    .tracking(1.0)
            }
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .overlay(
                Capsule()
                    .strokeBorder(
                        AnyShapeStyle(LinearGradient.diagonal),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .accessibilityLabel("Start this mission")
    }

    // MARK: - Type chip

    @ViewBuilder
    private func typeChip(for type: String?, bucket: TheHaulMissionsStore.Bucket) -> some View {
        let label = (type?.uppercased() ?? "MISSION")
        HStack(spacing: 6) {
            Image(systemName: iconForBucket(bucket))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    bucket == .active
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textTertiary)
                )
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundColor(palette.textSecondary)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 3)
        .overlay(
            Capsule()
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func iconForBucket(_ b: TheHaulMissionsStore.Bucket) -> String {
        switch b {
        case .active:    return "bolt.fill"
        case .completed: return "checkmark.seal"
        case .available: return "target"
        }
    }

    // MARK: - Loading / error chrome

    private var inlineLoading: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading your missions…")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func inlineError(err: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(palette.danger)
                Text("Couldn't load — \(err.localizedDescription)")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro)
                    .tracking(1.2)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Toast

    private func toastBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: toastIsError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(
                    toastIsError
                    ? AnyShapeStyle(palette.danger)
                    : AnyShapeStyle(LinearGradient.diagonal)
                )
            Text(msg)
                .font(EType.caption)
                .foregroundColor(palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
        .padding(.horizontal, Space.s5)
    }

    private func showToast(_ msg: String, isError: Bool) {
        toastTask?.cancel()
        withAnimation { toast = msg; toastIsError = isError }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation { toast = nil }
                }
            }
        }
    }

    // MARK: - Mutations

    private func start(_ row: TheHaulMissionsStore.Row) async {
        guard inFlightMissionId == nil else { return }
        inFlightMissionId = row.id
        let err = await store.startMission(missionId: row.id)
        inFlightMissionId = nil
        if let err {
            showToast(err, isError: true)
        } else {
            showToast("Mission started", isError: false)
            openMissionId = nil
        }
    }

    private func claim(_ row: TheHaulMissionsStore.Row) async {
        guard inFlightMissionId == nil else { return }
        inFlightMissionId = row.id
        let err = await store.claimMissionReward(missionId: row.id)
        inFlightMissionId = nil
        if let err {
            showToast(err, isError: true)
        } else {
            let reward = row.projection.rewardLabel ?? "Reward credited"
            showToast("Claimed — \(reward)", isError: false)
            openMissionId = nil
        }
    }

    // MARK: - Format helpers

    private func shortDay(_ iso: String) -> String {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime]
        if let d = iso1.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso2.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        return iso
    }
}

// MARK: - Detail sheet

/// Per-mission detail sheet. Opened by tapping a row on the list.
private struct MissionDetailSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    let row: TheHaulMissionsStore.Row
    let isInFlight: Bool
    let onStart: () -> Void
    let onClaim: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                descriptionBlock
                progressBlock
                rewardBlock
                windowBlock
                bottomCTA
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text((row.raw.type ?? "MISSION").uppercased())
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                if let code = row.raw.code, !code.isEmpty {
                    Text(code)
                        .font(EType.micro.monospacedDigit())
                        .foregroundColor(palette.textTertiary)
                }
            }
            Text(row.raw.name)
                .font(EType.h2)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if let d = row.raw.description, !d.isEmpty {
            Text(d)
                .font(EType.body)
                .foregroundColor(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var progressBlock: some View {
        let target = row.raw.targetValue ?? 0
        let current = row.raw.currentProgress ?? 0
        let pct = row.projection.progress

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PROGRESS")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.tintNeutral.opacity(0.6))
                        .frame(height: 8)
                    Capsule()
                        .fill(AnyShapeStyle(LinearGradient.diagonal))
                        .frame(
                            width: max(8, geo.size.width * CGFloat(pct)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)

            HStack {
                Text(progressCaption(current: current, target: target, unit: row.raw.targetUnit))
                    .font(EType.body.monospacedDigit())
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(EType.body.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private var rewardBlock: some View {
        if let rewardLabel = row.projection.rewardLabel, !rewardLabel.isEmpty {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)))
                        .frame(width: 44, height: 44)
                    Image(systemName: "gift")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("REWARD")
                        .font(EType.micro)
                        .tracking(1.4)
                        .foregroundColor(palette.textSecondary)
                    Text(rewardLabel)
                        .font(EType.bodyStrong)
                        .foregroundColor(palette.textPrimary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    @ViewBuilder
    private var windowBlock: some View {
        let starts = row.raw.startsAt
        let ends = row.raw.endsAt
        if (starts != nil && !(starts?.isEmpty ?? true)) ||
           (ends != nil && !(ends?.isEmpty ?? true)) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("WINDOW")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                if let s = starts, !s.isEmpty {
                    row(label: "Starts", value: formatISO(s))
                }
                if let e = ends, !e.isEmpty {
                    row(label: "Ends", value: formatISO(e))
                }
            }
            .padding(Space.s4)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.caption.monospacedDigit())
                .foregroundColor(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var bottomCTA: some View {
        switch row.bucket {
        case .completed:
            Button {
                onClaim()
            } label: {
                HStack(spacing: 8) {
                    if isInFlight {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "gift")
                    }
                    Text(isInFlight ? "Claiming…" : "Claim reward")
                    if !isInFlight {
                        Text("→").font(.system(size: 16, weight: .semibold))
                    }
                }
                .font(EType.body).fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(isInFlight)
            .accessibilityLabel("Claim mission reward")
        case .available:
            Button {
                onStart()
            } label: {
                HStack(spacing: 8) {
                    if isInFlight {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(isInFlight ? "Starting…" : "Start this mission")
                    if !isInFlight {
                        Text("→").font(.system(size: 16, weight: .semibold))
                    }
                }
                .font(EType.body).fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(isInFlight)
            .accessibilityLabel("Start this mission")
        case .active:
            // Active missions have no inline action — progress is driven
            // by real-world events (load delivered, safety check cleared).
            VStack(spacing: Space.s2) {
                Text("Keep going")
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                Text("Progress updates as you complete qualifying loads, safety checks, or streaks.")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .eusoCard(radius: Radius.md)
        }
    }

    private func progressCaption(current: Double, target: Double, unit: String?) -> String {
        guard target > 0 else { return unit?.isEmpty == false ? unit! : "—" }
        let u = unit?.isEmpty == false ? " \(unit!)" : ""
        if current.rounded() == current && target.rounded() == target {
            return "\(Int(current)) of \(Int(target))\(u)"
        }
        return String(format: "%.1f of %.1f%@", current, target, u)
    }

    private func formatISO(_ iso: String) -> String {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime]
        if let d = iso1.date(from: iso) {
            let f = DateFormatter()
            f.dateFormat = "MMM d · HH:mm"
            return f.string(from: d)
        }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso2.date(from: iso) {
            let f = DateFormatter()
            f.dateFormat = "MMM d · HH:mm"
            return f.string(from: d)
        }
        return iso
    }
}

// MARK: - Screen wrapper

struct TheHaulMissionsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulMissions()
        } nav: {
            BottomNav(
                leading: driverNavLeading_061(),
                trailing: driverNavTrailing_061(),
                orbState: .idle
            )
        }
    }
}

// 061 ships the Haul-tab custom variant (Haul current, frozen per
// [feedback_bottom_nav_frozen]). iOS file is `061_TheHaulMissions.swift`
// but PNG slot was rebranded to "Earnings and Pay" — same iOS-vs-PNG
// mismatch as 057-060, out of safe-mode scope. Only SF Symbol
// naming polish for cross-screen consistency with 010-060.
private func driverNavLeading_061() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy",     isCurrent: true)]
}
private func driverNavTrailing_061() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - Previews
//
// Both previews render the production path — live store, no fixtures.
// An unauthenticated `EusoTripSession()` resolves the store to `.error`
// or `.empty` deterministically without hitting the network, so the
// preview renders the branded empty path. A real signed-in driver with
// active mission data will see the live roster on device.

#Preview("061 · The Haul Missions · Night · Empty / Live store") {
    TheHaulMissionsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("061 · The Haul Missions · Light · Empty / Live store") {
    TheHaulMissionsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
