//
//  709_DispatchBulkUploadKanban.swift
//  EusoTrip — Dispatch · Bulk-upload kanban (jobs by lifecycle).
//
//  Innovation over Dispatch Commodity's bulk-import pattern:
//   • Job state mirrored as a snap-paged kanban (UPLOADED · VALIDATING ·
//     VALIDATED · IMPORTING · COMPLETED · FAILED) — they ship a flat list,
//     we ship a stage-aware board so a dispatcher sees the funnel.
//   • Per-card actions tied to the existing bulkUpload router:
//       UPLOADED   → bulkUpload.validateJob
//       VALIDATED  → bulkUpload.executeJob
//       FAILED     → bulkUpload.retryFailedRows  (or cancelJob)
//   • Hooks the existing per-role registry — dispatcher uploads "loads",
//     compliance uploads "drivers/certifications", admin imports "tenants",
//     etc. The surface is one screen across all 24 roles per the bulk-upload
//     parity mandate.
//

import SwiftUI

struct DispatchBulkUploadKanbanScreen: View {
    let theme: Theme.Palette
    var entityType: String = "loads"
    var body: some View {
        Shell(theme: theme) { BulkBody(entityType: entityType) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .thinking
            )
        }
    }
}

private struct BulkJob: Decodable, Identifiable, Hashable {
    let id: Int
    let companyId: Int?
    let uploadedBy: Int?
    let fileName: String
    let totalRows: Int?
    let successCount: Int?
    let failCount: Int?
    let status: String?
    let createdAt: String?
    let completedAt: String?
    let entityType: String?
}

private struct BulkHistoryResponse: Decodable, Hashable { let jobs: [BulkJob] }

private struct BulkColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let action: String?  // procedure to run on tap
    let actionLabel: String?
}

private let bulkColumns: [BulkColumn] = [
    .init(id: "uploaded",   label: "UPLOADED",   icon: "tray.and.arrow.up",      action: "bulkUpload.validateJob",     actionLabel: "Validate"),
    .init(id: "validating", label: "VALIDATING", icon: "gearshape.2",            action: nil,                          actionLabel: nil),
    .init(id: "validated",  label: "VALIDATED",  icon: "checkmark.shield",       action: "bulkUpload.executeJob",      actionLabel: "Execute"),
    .init(id: "importing",  label: "IMPORTING",  icon: "arrow.down.to.line",     action: nil,                          actionLabel: nil),
    .init(id: "completed",  label: "COMPLETED",  icon: "checkmark.seal.fill",    action: nil,                          actionLabel: nil),
    .init(id: "failed",     label: "FAILED",     icon: "xmark.octagon.fill",     action: "bulkUpload.retryFailedRows", actionLabel: "Retry"),
]

private struct BulkBody: View {
    @Environment(\.palette) private var palette
    // Sheet→push (NAV remediation 2026-05-30): the job detail now pushes
    // in-stack via the surface's detail layer + BespokeBackBar instead of
    // presenting as a `.sheet`. Nil outside a role surface that installs
    // RoleDetailLayer.
    @Environment(\.rolePushDetail) private var pushDetail
    let entityType: String
    @State private var jobs: [BulkJob] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selected: String = "uploaded"
    @State private var sheetJob: BulkJob? = nil
    @State private var workingId: Int? = nil
    @State private var actionError: String? = nil
    @State private var lastAction: String? = nil
    /// Drop-zone hover state for the lane the dispatcher is dragging
    /// a job toward. Drives a gradient stroke on the target column.
    @State private var dragHoverColumn: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            funnelChips.padding(.bottom, 6)
            if loading { LifecycleCard { Text("Loading bulk jobs…").font(EType.caption).foregroundStyle(palette.textSecondary) }.padding(.horizontal, 14) }
            else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14) }
            else { columnPager }
            if let m = lastAction {
                LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) }.padding(.horizontal, 14).padding(.top, 6)
            }
            if let e = actionError {
                LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14).padding(.top, 6)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · BULK UPLOAD · \(entityType.uppercased())").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("\(jobs.count) JOBS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(palette.bgCard).clipShape(Capsule())
            }
            Text("Bulk import funnel").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var funnelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bulkColumns) { col in
                    let count = jobs.filter { ($0.status ?? "") == col.id }.count
                    Button { withAnimation(.easeOut(duration: 0.18)) { selected = col.id } } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(count)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(bulkColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: BulkColumn) -> some View {
        let cards = jobs.filter { ($0.status ?? "") == col.id }
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label).font(.system(size: 13, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if let label = col.actionLabel { Text("ACTION · \(label.uppercased())").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary) }
                }
                if cards.isEmpty {
                    EusoEmptyState(systemImage: col.icon, title: "Empty stage", subtitle: "No jobs in this stage right now.")
                } else {
                    ForEach(cards) { j in
                        Button {
                            sheetJob = j
                            pushDetail?(j.fileName) { AnyView(jobSheet(j)) }
                        } label: { cardView(j, col: col) }
                            .buttonStyle(.plain)
                            // 2026-05-23 — Drag the job card to fire
                            // the SOURCE column's action without
                            // opening the sheet. Drop target = any
                            // column body; the action that runs is
                            // the source-column's action (validateJob
                            // for UPLOADED, executeJob for VALIDATED,
                            // retryFailedRows for FAILED). Transient
                            // stages (VALIDATING / IMPORTING) have
                            // no source action; dragging from those
                            // is a no-op.
                            .draggable(String(j.id)) {
                                cardView(j, col: col)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let idStr = droppedIds.first, let jobId = Int(idStr) else { return false }
            guard let job = jobs.first(where: { $0.id == jobId }) else { return false }
            guard let sourceCol = bulkColumns.first(where: { $0.id == (job.status ?? "") }) else { return false }
            // Drop on the same column = no-op (the source action
            // already runs from the sheet; drag is the shortcut).
            if sourceCol.id == col.id { return false }
            // Source column must have an action wired — transient
            // VALIDATING / IMPORTING stages bail honestly.
            guard let proc = sourceCol.action else { return false }
            Task { await runAction(proc: proc, on: job) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ j: BulkJob, col: BulkColumn) -> some View {
        LifecycleCard(accentDanger: col.id == "failed", accentGradient: col.id == "completed") {
            LifecycleSection(label: j.fileName.uppercased(), icon: col.icon)
            LifecycleRow(label: "Entity", value: dashIfEmpty(j.entityType))
            LifecycleRow(label: "Rows",   value: "\(j.totalRows ?? 0)")
            LifecycleRow(label: "Pass",   value: "\(j.successCount ?? 0)")
            LifecycleRow(label: "Fail",   value: "\(j.failCount ?? 0)")
            LifecycleRow(label: "Created",value: humanISO(j.createdAt))
            if let c = j.completedAt { LifecycleRow(label: "Done", value: humanISO(c)) }
        }
    }

    private func jobSheet(_ j: BulkJob) -> some View {
        let col = bulkColumns.first { $0.id == (j.status ?? "") } ?? bulkColumns[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(j.fileName).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                LifecycleCard {
                    LifecycleSection(label: "JOB", icon: col.icon)
                    LifecycleRow(label: "Entity",  value: dashIfEmpty(j.entityType))
                    LifecycleRow(label: "Status",  value: (j.status ?? "—").uppercased())
                    LifecycleRow(label: "Rows",    value: "\(j.totalRows ?? 0)")
                    LifecycleRow(label: "Success", value: "\(j.successCount ?? 0)")
                    LifecycleRow(label: "Failed",  value: "\(j.failCount ?? 0)")
                    LifecycleRow(label: "Created", value: humanISO(j.createdAt))
                    if let c = j.completedAt { LifecycleRow(label: "Done", value: humanISO(c)) }
                }
                if let proc = col.action, let label = col.actionLabel {
                    Button { Task { await runAction(proc: proc, on: j) } } label: {
                        HStack(spacing: 6) {
                            if workingId == j.id { ProgressView().tint(.white) }
                            Image(systemName: "play.fill").foregroundStyle(.white)
                            Text(workingId == j.id ? "Running…" : label.uppercased()).font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain).disabled(workingId != nil)
                }
                Button { Task { await cancel(j) } } label: {
                    Text("Cancel job").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Brand.danger.opacity(0.6), lineWidth: 1))
                }.buttonStyle(.plain).disabled(workingId != nil)
                Spacer()
            }
            .padding(14)
        }.background(palette.bgPage)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int; let offset: Int; let entityType: String? }
        do {
            let r: BulkHistoryResponse = try await EusoTripAPI.shared.query("bulkUpload.getJobHistory", input: In(limit: 100, offset: 0, entityType: entityType))
            jobs = r.jobs
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func runAction(proc: String, on j: BulkJob) async {
        workingId = j.id; actionError = nil
        struct In: Encodable { let jobId: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(proc, input: In(jobId: j.id))
            lastAction = "\(proc.split(separator: ".").last ?? "") · job \(j.id) queued."
            // If the action came from the pushed job detail (sheetJob set),
            // pop the in-stack layer back to the funnel. The drag path
            // leaves sheetJob nil, so no spurious pop.
            if sheetJob != nil {
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            }
            sheetJob = nil
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        workingId = nil
    }

    private func cancel(_ j: BulkJob) async {
        workingId = j.id; actionError = nil
        struct In: Encodable { let jobId: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("bulkUpload.cancelJob", input: In(jobId: j.id))
            lastAction = "Cancelled job \(j.id)."
            // Cancel only fires from the pushed job detail — pop it back.
            if sheetJob != nil {
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            }
            sheetJob = nil
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        workingId = nil
    }
}

#Preview("709 · Bulk kanban · Night") { DispatchBulkUploadKanbanScreen(theme: Theme.dark, entityType: "loads").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("709 · Bulk kanban · Afternoon") { DispatchBulkUploadKanbanScreen(theme: Theme.light, entityType: "loads").environmentObject(EusoTripSession()).preferredColorScheme(.light) }

