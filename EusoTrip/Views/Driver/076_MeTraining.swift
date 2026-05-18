//
//  076_MeTraining.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · training)
//
//  Screen 076 · Me · Training — the driver's personal training +
//  certification surface. Four stacked blocks:
//    (1) "Due now" strip — overdue + pending mandatory courses (only
//        renders when the pending store returns non-empty arrays).
//    (2) Summary tiles — total / completed / in-progress counts from
//        `training.getDriverAssignments().summary`.
//    (3) Assignments list — grouped by status (in-progress first, then
//        not-started, then completed, then expired) with per-row
//        progress bar + due-date + category chip.
//    (4) Certificates vault — issued certificates with expiry pill
//        (green for active, warning for expired/expiring).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Assignments + summary: `training.getDriverAssignments` — MCP-
//      verified at `frontend/server/routers/training.ts:113`. Server
//      scopes to ctx.user.id so no driverId param is needed.
//
//    • Pending + overdue: `training.getPendingMandatoryTraining`
//      (training.ts:808). The view only renders the red-accent "Due
//      now" strip when `overdue.count > 0`; zero overdue = clean
//      dashboard.
//
//    • Certificates: `trainingLMS.getMyCertificates` (trainingLMS.ts:549).
//      Expiry is server-computed; we just read `expiresAt` and render
//      a chip.
//
//    • Empty state is server-confirmed. A brand-new driver with no
//      assignments and no certificates lands on a single
//      `EusoEmptyState` hero, not four empty blocks.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on progress bar fills + active
//         certificate chips + summary numerics. Brand.warning on
//         overdue strip + expired certificate chips.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg), type
//         (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — stores land in `.error` via
//         `notConfigured` under the preview's no-baseURL runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeTraining: View {
    @Environment(\.palette) var palette
    @StateObject private var assignments = DriverTrainingStore()
    @StateObject private var pending = PendingMandatoryTrainingStore()
    @StateObject private var certs = DriverCertificatesStore()

    /// Course catalog (training.listCourses) — populated lazily when
    /// the driver expands the Catalog disclosure. Mirrors the web
    /// TrainingCompliance "Browse" tab.
    @State private var catalog: [TrainingAPI.CatalogCourse] = []
    @State private var catalogExpanded: Bool = false
    @State private var catalogLoading: Bool = false
    @State private var enrollingCourseId: String?
    @State private var enrollToast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                if isInitialLoading {
                    skeleton
                } else if isEverythingEmpty {
                    emptyHero
                } else {
                    dueNowStrip
                    summaryTiles
                    assignmentsSection
                    certificatesSection
                }
                catalogSection
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reloadAll() }
        .refreshable { await reloadAll() }
    }

    private func reloadAll() async {
        async let a: Void = assignments.refresh()
        async let b: Void = pending.refresh()
        async let c: Void = certs.refresh()
        _ = await (a, b, c)
    }

    private var isInitialLoading: Bool {
        if case .loading = assignments.state { return true }
        return false
    }

    /// True when every downstream store has settled and has nothing to
    /// show. Keeps the full-screen `emptyHero` out of early ticks
    /// where one store is still loading.
    private var isEverythingEmpty: Bool {
        guard assignments.state.isSettled,
              pending.state.isSettled,
              certs.state.isSettled else { return false }
        let assignmentsEmpty: Bool = {
            if case .empty = assignments.state { return true }
            if case .loaded(let resp) = assignments.state {
                return resp.assignments.isEmpty && resp.summary.total == 0
            }
            return false
        }()
        let pendingEmpty: Bool = {
            if case .empty = pending.state { return true }
            if case .loaded(let resp) = pending.state {
                return resp.pending.isEmpty && resp.overdue.isEmpty
            }
            return false
        }()
        let certsEmpty: Bool = {
            if case .empty = certs.state { return true }
            return false
        }()
        return assignmentsEmpty && pendingEmpty && certsEmpty
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Training")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Assignments · certificates · compliance")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(
                state: (assignments.isLoading || pending.isLoading || certs.isLoading) ? .thinking : .idle,
                diameter: 40
            )
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.4))
                .frame(height: 72)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.35))
                        .frame(height: 68)
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 64)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "graduationcap",
            title: "No training on file yet",
            subtitle: "New assignments show up here the moment dispatch or your safety manager pushes them. Your earned certificates land in the same place."
        )
    }

    // MARK: Due-now strip (overdue + pending mandatory)

    @ViewBuilder
    private var dueNowStrip: some View {
        if case .loaded(let resp) = pending.state,
           (resp.overdue.count + resp.pending.count) > 0 {
            let overdueCount = resp.overdue.count
            let pendingCount = resp.pending.count
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: overdueCount > 0 ? "exclamationmark.circle.fill" : "clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(overdueCount > 0 ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(palette.textSecondary))
                    Text(overdueCount > 0 ? "\(overdueCount) OVERDUE · \(pendingCount) DUE SOON"
                                          : "\(pendingCount) DUE SOON")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                let preview = (resp.overdue + resp.pending).prefix(3)
                VStack(spacing: Space.s2) {
                    ForEach(Array(preview), id: \.id) { c in
                        pendingRow(c, isOverdue: resp.overdue.contains(where: { $0.id == c.id }))
                    }
                }
            }
        }
    }

    private func pendingRow(_ c: TrainingAPI.PendingCourse, isOverdue: Bool) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.courseName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let due = c.dueDate, let pretty = prettyDate(due) {
                    Text(isOverdue ? "Overdue · was due \(pretty)" : "Due \(pretty)")
                        .font(EType.caption)
                        .foregroundStyle(isOverdue ? Brand.warning : palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            if c.progress > 0 {
                Text("\(c.progress)%")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isOverdue ? Brand.warning.opacity(0.55) : palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Summary tiles

    @ViewBuilder
    private var summaryTiles: some View {
        if case .loaded(let resp) = assignments.state, resp.summary.total > 0 {
            HStack(spacing: Space.s2) {
                summaryTile(label: "ASSIGNED",   value: resp.summary.total,       emphasis: true)
                summaryTile(label: "COMPLETED",  value: resp.summary.completed,   emphasis: false)
                summaryTile(label: "IN PROGRESS",value: resp.summary.inProgress,  emphasis: false)
            }
        }
    }

    private func summaryTile(label: String, value: Int, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(value)")
                .font(EType.numeric)
                .monospacedDigit()
                .foregroundStyle(
                    emphasis
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.textPrimary)
                )
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

    // MARK: Assignments list

    @ViewBuilder
    private var assignmentsSection: some View {
        if case .loaded(let resp) = assignments.state, !resp.assignments.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("ASSIGNMENTS")
                        .font(EType.micro)
                        .tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(resp.assignments.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(sortedAssignments(resp.assignments)) { a in
                        assignmentRow(a)
                    }
                }
            }
        }
    }

    private func sortedAssignments(_ rows: [TrainingAPI.Assignment]) -> [TrainingAPI.Assignment] {
        // Order: in_progress → not_started → completed → expired
        let order: [String: Int] = [
            "in_progress": 0, "not_started": 1, "completed": 2, "expired": 3,
        ]
        return rows.sorted { a, b in
            let ai = order[a.status.lowercased()] ?? 99
            let bi = order[b.status.lowercased()] ?? 99
            if ai != bi { return ai < bi }
            return a.courseName < b.courseName
        }
    }

    private func assignmentRow(_ a: TrainingAPI.Assignment) -> some View {
        let fraction = max(0.0, min(1.0, Double(a.progress) / 100.0))
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s2) {
                    Text(a.courseName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    if let cat = a.category, !cat.isEmpty {
                        Text(cat.uppercased())
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                            )
                    }
                }
                HStack(spacing: Space.s2) {
                    if let due = a.dueDate, let pretty = prettyDate(due) {
                        Text("Due \(pretty)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    } else if let done = a.completedAt, let pretty = prettyDate(done) {
                        Text("Completed \(pretty)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if let s = a.score {
                        Text("· Score \(s)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if a.progress > 0 && a.progress < 100 {
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
            }
            Spacer(minLength: Space.s2)
            statusChip(a.status)
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
        case "completed":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "expired":
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

    // MARK: Certificates

    @ViewBuilder
    private var certificatesSection: some View {
        if case .loaded(let rows) = certs.state, !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("CERTIFICATES")
                        .font(EType.micro)
                        .tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(rows) { c in
                        certificateRow(c)
                    }
                }
            }
        }
    }

    private func certificateRow(_ c: TrainingAPI.Certificate) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "rosette")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(c.courseName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(certificateSubtitle(c))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            certificateChip(c)
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

    private func certificateSubtitle(_ c: TrainingAPI.Certificate) -> String {
        let issued = c.issuedAt.flatMap(prettyDate).map { "Issued \($0)" }
        let cert = "#\(c.certificateNumber)"
        return [cert, issued].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func certificateChip(_ c: TrainingAPI.Certificate) -> some View {
        let normalizedStatus = c.status.lowercased()
        let isExpired = normalizedStatus == "expired" || normalizedStatus == "revoked"
        let label: String = {
            if isExpired { return normalizedStatus.uppercased() }
            if let exp = c.expiresAt, let pretty = prettyDate(exp) {
                return "EXP \(pretty)".uppercased()
            }
            return "ACTIVE"
        }()
        if isExpired {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
        } else {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        }
    }

    // MARK: Catalog (browse + enroll — web TrainingCompliance parity)

    @ViewBuilder
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    catalogExpanded.toggle()
                }
                if catalogExpanded && catalog.isEmpty {
                    Task { await loadCatalog() }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("BROWSE COURSES")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: catalogExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if catalogExpanded {
                if catalogLoading {
                    HStack {
                        ProgressView().progressViewStyle(.circular).controlSize(.small)
                        Text("Loading catalog…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(Space.s3)
                } else if catalog.isEmpty {
                    Text("No courses in the catalog right now.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(Space.s3)
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(catalog) { c in
                            catalogRow(c)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = enrollToast {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(toast)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .padding(.bottom, -Space.s5)
                .transition(.opacity)
            }
        }
    }

    private func catalogRow(_ c: TrainingAPI.CatalogCourse) -> some View {
        let isEnrolling = enrollingCourseId == c.id
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(c.category.uppercased())
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                    Text("\(c.duration) min · pass \(c.passingScore)%")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(c.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if !c.description.isEmpty {
                    Text(c.description)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s2)
            Button {
                Task { await enrollInCourse(c) }
            } label: {
                if isEnrolling {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                        .frame(minWidth: 64)
                } else {
                    Text("Enroll")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            .buttonStyle(.plain)
            .disabled(isEnrolling)
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

    private func loadCatalog() async {
        await MainActor.run { self.catalogLoading = true }
        defer { Task { @MainActor in self.catalogLoading = false } }
        do {
            let rows = try await EusoTripAPI.shared.training.listCourses()
            await MainActor.run { self.catalog = rows }
        } catch {
            await MainActor.run { self.catalog = [] }
        }
    }

    private func enrollInCourse(_ c: TrainingAPI.CatalogCourse) async {
        await MainActor.run { self.enrollingCourseId = c.id }
        defer { Task { @MainActor in self.enrollingCourseId = nil } }
        do {
            _ = try await EusoTripAPI.shared.training.startCourse(courseId: c.id)
            await MainActor.run {
                withAnimation { self.enrollToast = "Enrolled in \(c.title)" }
            }
            await assignments.refresh()
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run {
                withAnimation { self.enrollToast = nil }
            }
        } catch {
            await MainActor.run {
                withAnimation { self.enrollToast = "Enrollment failed" }
            }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { withAnimation { self.enrollToast = nil } }
        }
    }

    // MARK: Disclosure footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How training flows")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Dispatch, your safety manager, and the FMCSA-aligned CSA engine all push training here. Completions feed your safety score and the carrier scorecard in real time — this is the real record.")
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
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        // Tolerate plain YYYY-MM-DD from the assignments router.
        let ymd = DateFormatter()
        ymd.calendar = Calendar(identifier: .gregorian)
        ymd.locale = Locale(identifier: "en_US_POSIX")
        ymd.dateFormat = "yyyy-MM-dd"
        if let d = ymd.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        return iso
    }
}

// MARK: - Screen wrapper

struct MeTrainingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeTraining()
        } nav: {
            BottomNav(
                leading: driverNavLeading_076(),
                trailing: driverNavTrailing_076(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_076() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_076() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("076 · Me Training · Night") {
    MeTrainingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("076 · Me Training · Afternoon") {
    MeTrainingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
