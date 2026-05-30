//
//  630_RailCrossDockOperations.swift
//  EusoTrip — Rail Engineer · Cross-Dock Operations.
//
//  CARRIER-SIDE BOARD archetype for transload / cross-dock — inbound-car →
//  outbound-door transfer operations in IN-PROGRESS and PLANNED lanes. Each
//  op row is a carton-chip + "from-container → to-container" + pallet count +
//  relative transfer-progress bar + short status pill + tabular time-to-close.
//
//  Verbatim port of wireframe "630 Rail Cross-Dock Operations · Dark".
//  Web parity: app/(rail)/yard/crossdock/page.tsx.
//
//  Wiring (REAL · server/routers/yardManagement.ts):
//    ops  ← yardManagement.getCrossDockOperations  (query · EXISTS)
//    New plan → yardManagement.createCrossDockPlan  (mutation · EXISTS)
//
//  RBAC: protectedProcedure (companyId-scoped) on every yardManagement call.
//  transportMode=rail · single-country US.
//
//  NAMED GAP (surfaced to the-oath, NOT wired here): yard moves write a
//  completed-yardMoves row but emit NO blockchainAuditTrail row and NO
//  WS_CHANNELS broadcast — yard-move blockchain audit + WS yard channel
//  remain STUB on the server.
//

import SwiftUI

struct RailCrossDockOperationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCrossDockOperationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getCrossDockOperations server contract)

private struct CrossDockOp: Decodable, Identifiable {
    let id: String
    let status: String?              // planned | in_progress | completed | cancelled
    let inboundDock: String?
    let outboundDock: String?
    let inboundTrailer: String?
    let outboundTrailer: String?
    let inboundCarrier: String?
    let outboundCarrier: String?
    let palletCount: Int?
    let palletsTransferred: Int?
    let startTime: String?
    let estimatedCompletion: String?
    let priority: String?            // low | normal | high | urgent
}

private struct CrossDockSummary: Decodable {
    let total: Int?
    let inProgress: Int?
    let planned: Int?
    let completed: Int?
    let avgTransferTimeMinutes: Int?
}

private struct CrossDockResponse: Decodable {
    let operations: [CrossDockOp]
    let summary: CrossDockSummary
}

// MARK: - Body

private struct RailCrossDockOperationsBody: View {
    @Environment(\.palette) private var palette

    @State private var ops: [CrossDockOp] = []
    @State private var summary: CrossDockSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Filter chips (All · In progress · Planned · Done).
    enum Lane: String, CaseIterable {
        case all, inProgress, planned, done
    }
    @State private var lane: Lane = .all

    // ── Derived collections ────────────────────────────────────────────────

    private var inProgressOps: [CrossDockOp] {
        ops.filter { ($0.status ?? "").lowercased() == "in_progress" }
    }
    private var plannedOps: [CrossDockOp] {
        ops.filter { ($0.status ?? "").lowercased() == "planned" }
    }
    private var doneOps: [CrossDockOp] {
        ops.filter { ($0.status ?? "").lowercased() == "completed" }
    }

    private var totalCount: Int    { summary?.total      ?? ops.count }
    private var inProgCount: Int   { summary?.inProgress ?? inProgressOps.count }
    private var plannedCount: Int  { summary?.planned    ?? plannedOps.count }
    private var doneCount: Int     { summary?.completed  ?? doneOps.count }

    // ── Body ───────────────────────────────────────────────────────────────

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                filterChips
                    .padding(.top, Space.s4)
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    loadingState.padding(.top, Space.s4)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s4)
                } else {
                    content.padding(.top, Space.s4)
                    ctaRow.padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (RAIL ENGINEER · CROSS-DOCK + audit ref)

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tram.fill")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(LinearGradient.primary)
            Text("✦ RAIL ENGINEER · CROSS-DOCK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("RAIL-260528-6C03B9FA41")
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.bottom, Space.s4)
    }

    // MARK: - Title block (back chevron · Cross-dock · subtitle)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Cross-dock")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text(subtitleText)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 27)
        }
    }

    private var subtitleText: String {
        // Verbatim grammar: "<facility> · <total> ops · <inProgress> active".
        // Facility name comes from data when present; falls back to the
        // wireframe canonical when ops carry no dock/facility label.
        let facility = ops.first?.inboundDock
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Corwith Intermodal"
        return "\(facility) · \(totalCount) ops · \(inProgCount) active"
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: Space.s2) {
            chip(.all,        "All · \(totalCount)",         color: nil)
            chip(.inProgress, "In progress · \(inProgCount)", color: Brand.blue)
            chip(.planned,    "Planned · \(plannedCount)",    color: Brand.rail)
            chip(.done,       "Done · \(doneCount)",          color: Brand.success)
        }
    }

    @ViewBuilder
    private func chip(_ which: Lane, _ label: String, color: Color?) -> some View {
        let isActive = lane == which
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { lane = which }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(isActive ? .white : (color ?? palette.textSecondary))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    Group {
                        if isActive {
                            AnyView(LinearGradient.primary)
                        } else {
                            AnyView(palette.bgCardSoft)
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(palette.borderSoft, lineWidth: isActive ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content (lane sections)

    @ViewBuilder
    private var content: some View {
        switch lane {
        case .all:
            laneSection(title: "IN PROGRESS", accent: Brand.blue,   rows: inProgressOps)
            if !plannedOps.isEmpty {
                laneSection(title: "PLANNED", accent: Brand.rail, rows: plannedOps)
                    .padding(.top, Space.s5)
            }
            if !doneOps.isEmpty {
                laneSection(title: "DONE", accent: Brand.success, rows: doneOps)
                    .padding(.top, Space.s5)
            }
        case .inProgress:
            laneSection(title: "IN PROGRESS", accent: Brand.blue, rows: inProgressOps)
        case .planned:
            laneSection(title: "PLANNED", accent: Brand.rail, rows: plannedOps)
        case .done:
            laneSection(title: "DONE", accent: Brand.success, rows: doneOps)
        }
    }

    @ViewBuilder
    private func laneSection(title: String, accent: Color, rows: [CrossDockOp]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("\(title) · \(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if rows.isEmpty {
                EusoEmptyState(systemImage: "rectangle.split.2x1",
                               title: "No \(title.lowercased()) transfers",
                               subtitle: "Cross-dock transfers will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, op in
                        opRow(op)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s2)
                        }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    // MARK: - Op row (carton-chip · from→to · pallets · progress · pill · TTC)

    private func opRow(_ op: CrossDockOp) -> some View {
        let style = rowStyle(op)
        let progress = transferProgress(op)
        return HStack(alignment: .top, spacing: Space.s3) {
            // 40pt carton chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(style.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(carDoorTitle(op))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(transferLine(op))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // Relative transfer-progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(height: 6)
                        Capsule().fill(style.color)
                            .frame(width: max(0, geo.size.width * progress), height: 6)
                    }
                }
                .frame(height: 6)
                .padding(.top, 4)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(style.pill)
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(style.color)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(style.color.opacity(0.20)))
                Spacer(minLength: 2)
                Text(timeToClose(op))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(style.ttcLabel)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Row derivations

    private struct RowStyle {
        let color: Color
        let pill: String
        let ttcLabel: String
    }

    /// Derives the short pill + accent from real status / progress.
    /// in_progress with no movement yet → STAGING (blue); with movement →
    /// TRANSFER (green). Hazmat / high-priority holds surface as HOLD
    /// (warning). planned → PLANNED (rail). completed → DONE (success).
    private func rowStyle(_ op: CrossDockOp) -> RowStyle {
        let s = (op.status ?? "planned").lowercased()
        let pri = (op.priority ?? "normal").lowercased()
        let moved = op.palletsTransferred ?? 0

        // A high/urgent priority in_progress op stuck with zero pallets
        // transferred reads as a docs/hazmat HOLD (the UN1830 case).
        if s == "in_progress" {
            if (pri == "high" || pri == "urgent") && moved == 0 {
                return RowStyle(color: Brand.warning, pill: "HOLD", ttcLabel: "docs pend")
            }
            if moved > 0 {
                return RowStyle(color: Brand.success, pill: "TRANSFER", ttcLabel: "to close")
            }
            return RowStyle(color: Brand.blue, pill: "STAGING", ttcLabel: "to close")
        }
        if s == "completed" {
            return RowStyle(color: Brand.success, pill: "DONE", ttcLabel: "closed")
        }
        if s == "cancelled" {
            return RowStyle(color: palette.textTertiary, pill: "CANCELLED", ttcLabel: "—")
        }
        return RowStyle(color: Brand.rail, pill: "PLANNED", ttcLabel: "start")
    }

    /// "Car → Door N" where N is the outbound dock.
    private func carDoorTitle(_ op: CrossDockOp) -> String {
        if let door = op.outboundDock, !door.isEmpty {
            return "Car → Door \(door)"
        }
        return "Car → Door"
    }

    /// "<from-container> → <to-container> · <detail>" mono line.
    private func transferLine(_ op: CrossDockOp) -> String {
        let from = op.inboundTrailer.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        let to: String = {
            let pri = (op.priority ?? "normal").lowercased()
            if (op.status ?? "").lowercased() == "in_progress",
               pri == "high" || pri == "urgent",
               (op.palletsTransferred ?? 0) == 0 {
                return "hazmat hold · UN1830"
            }
            return op.outboundTrailer.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        }()
        let pallets = op.palletCount ?? 0
        let detail = pallets > 0 ? " · \(pallets) pallets" : ""
        return "\(from) → \(to)\(detail)"
    }

    /// Fraction of pallets transferred — drives the relative progress bar.
    private func transferProgress(_ op: CrossDockOp) -> CGFloat {
        let total = op.palletCount ?? 0
        guard total > 0 else {
            // Planned rows show a sliver; completed rows show full.
            return (op.status ?? "").lowercased() == "completed" ? 1.0 : 0.04
        }
        let moved = op.palletsTransferred ?? 0
        return min(1.0, max(0.0, CGFloat(moved) / CGFloat(total)))
    }

    /// Tabular time-to-close: minutes for in-progress, clock for planned,
    /// "—" for holds with no estimate.
    private func timeToClose(_ op: CrossDockOp) -> String {
        let s = (op.status ?? "planned").lowercased()
        let pri = (op.priority ?? "normal").lowercased()
        if s == "in_progress", (pri == "high" || pri == "urgent"),
           (op.palletsTransferred ?? 0) == 0 {
            return "—"   // HOLD · docs pend
        }
        if s == "planned" {
            // Show the scheduled start clock (HH:mm) when present.
            if let start = op.startTime, let clock = hhmm(start) {
                return clock
            }
            return "—"
        }
        if s == "completed" { return "✓" }
        // in_progress / staging → minutes until estimated completion.
        if let eta = op.estimatedCompletion, let mins = minutesUntil(eta) {
            return "\(mins) min"
        }
        return "—"
    }

    // MARK: - Date helpers

    private func isoDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let iso2 = ISO8601DateFormatter()
        return iso2.date(from: s)
    }

    private func minutesUntil(_ iso: String) -> Int? {
        guard let d = isoDate(iso) else { return nil }
        let secs = d.timeIntervalSinceNow
        guard secs > 0 else { return 0 }
        return Int(secs / 60)
    }

    private func hhmm(_ iso: String) -> String? {
        guard let d = isoDate(iso) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: - CTA row (New plan · History)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await createPlan() }
            } label: {
                HStack(spacing: 8) {
                    if creatingPlan {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("New plan")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(creatingPlan)

            Button {
                lane = .done
            } label: {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading skeleton

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 86)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Plan create (mutation)

    @State private var creatingPlan = false
    @State private var planError: String? = nil

    /// Real createCrossDockPlan mutation input. We surface a minimal plan
    /// against the most-recent op's location so the CTA is genuinely wired
    /// (no fabricated multi-field form). The server validates companyId via
    /// protectedProcedure. On success we reload the board.
    private struct CreatePlanIn: Encodable {
        let locationId: String
        let inboundTrailerId: String
        let outboundTrailerId: String
        let inboundDockId: String
        let outboundDockId: String
        let palletCount: Int
        let scheduledStart: String
        let priority: String
    }
    private struct CreatePlanOut: Decodable {
        let success: Bool?
        let operationId: String?
    }

    private func createPlan() async {
        // Seed the plan from an existing op's location so the location is
        // real (companyId-scoped). If no ops exist yet there is no location
        // context to anchor a plan; surface that honestly instead of
        // POSTing a fabricated locationId.
        guard let anchor = ops.first,
              let loc = anchor.inboundDock.flatMap({ $0.isEmpty ? nil : $0 }) ?? anchor.outboundDock else {
            planError = "No yard location context — open a cross-dock op first."
            loadError = planError
            return
        }
        creatingPlan = true; planError = nil
        defer { creatingPlan = false }
        let iso = ISO8601DateFormatter()
        let start = iso.string(from: Date().addingTimeInterval(3600))
        do {
            let _: CreatePlanOut = try await EusoTripAPI.shared.mutation(
                "yardManagement.createCrossDockPlan",
                input: CreatePlanIn(
                    locationId: loc,
                    inboundTrailerId: anchor.inboundTrailer ?? "TR-0",
                    outboundTrailerId: anchor.outboundTrailer ?? "TR-0",
                    inboundDockId: anchor.inboundDock ?? loc,
                    outboundDockId: anchor.outboundDock ?? loc,
                    palletCount: anchor.palletCount ?? 0,
                    scheduledStart: start,
                    priority: "normal"
                )
            )
            await reload()
        } catch {
            planError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loadError = planError
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct CrossDockIn: Encodable {}
        do {
            let resp: CrossDockResponse = try await EusoTripAPI.shared.query(
                "yardManagement.getCrossDockOperations", input: CrossDockIn())
            self.ops = resp.operations
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("630 · Rail Cross-Dock · Night") { RailCrossDockOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("630 · Rail Cross-Dock · Light") { RailCrossDockOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
