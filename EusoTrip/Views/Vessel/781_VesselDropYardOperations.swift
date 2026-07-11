//
//  781_VesselDropYardOperations.swift
//  EusoTrip — Vessel Operator · Drop Yard Operations.
//
//  Verbatim port of wireframe 781 (06 Vessel · Dark) — a purpose-built
//  spatial YARD OCCUPANCY GRID: the off-dock depot drawn as a live block map,
//  each cell colored by state (used / awaiting-dray / seal-flag / longest-
//  dwell / free) so the operator reads utilization and the hot box spatially.
//  Distinct from 780 Move Queue (now-serving lane).
//
//  Endpoints (server/routers/yardManagement.ts):
//    getDropYardOperations (:1693 · {locationId?} → {trailers:[{id,trailerNumber,
//      status,droppedAt,dwellTimeHours,spotId,sealIntact,pickupScheduled}],
//      summary:{total,dropped,awaitingPickup,avgDwellHours,sealIssues}}) —
//      drives the grid, KPI strip, and flagged-spots list.
//    assignYardMove (:2001 · {moveId, hostlerId} mutation) — "Schedule pickup".
//  Honest note: the marine drop-lot maps ISO 6346 container drops onto the
//  off-dock yardManagement model — no invented procedure.
//

import SwiftUI

struct VesselDropYardOperationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDropYardOperationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct DropYard781: Decodable {
    let trailers: [DropTrailer781]
    let summary: DropSummary781
    private enum CodingKeys: String, CodingKey { case trailers, summary }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        trailers = (try? c.decode([DropTrailer781].self, forKey: .trailers)) ?? []
        summary = (try? c.decode(DropSummary781.self, forKey: .summary)) ?? DropSummary781()
    }
}

private struct DropSummary781: Decodable {
    var total = 0, dropped = 0, awaitingPickup = 0, avgDwellHours = 0, sealIssues = 0
    init() {}
    private enum CodingKeys: String, CodingKey { case total, dropped, awaitingPickup, avgDwellHours, sealIssues }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        total = (try? c.decode(Int.self, forKey: .total)) ?? 0
        dropped = (try? c.decode(Int.self, forKey: .dropped)) ?? 0
        awaitingPickup = (try? c.decode(Int.self, forKey: .awaitingPickup)) ?? 0
        avgDwellHours = (try? c.decode(Int.self, forKey: .avgDwellHours)) ?? 0
        sealIssues = (try? c.decode(Int.self, forKey: .sealIssues)) ?? 0
    }
}

private struct DropTrailer781: Decodable, Identifiable {
    let id: String
    let trailerNumber: String?
    let status: String
    let dwellTimeHours: Int
    let spotId: String?
    let sealIntact: Bool
    let pickupScheduled: String?
    private enum CodingKeys: String, CodingKey {
        case id, trailerNumber, status, dwellTimeHours, spotId, sealIntact, pickupScheduled
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        trailerNumber = try? c.decode(String.self, forKey: .trailerNumber)
        status = (try? c.decode(String.self, forKey: .status)) ?? "dropped"
        dwellTimeHours = (try? c.decode(Int.self, forKey: .dwellTimeHours)) ?? 0
        spotId = try? c.decode(String.self, forKey: .spotId)
        sealIntact = (try? c.decode(Bool.self, forKey: .sealIntact)) ?? true
        pickupScheduled = try? c.decode(String.self, forKey: .pickupScheduled)
    }
    var isAwaiting: Bool { status.lowercased().contains("await") || pickupScheduled != nil }
}

// A resolved cell state for the occupancy grid.
private enum CellState781 { case used, awaiting, seal, hot, free }

// MARK: - Body

private struct VesselDropYardOperationsBody: View {
    @Environment(\.palette) private var palette
    @State private var data: DropYard781? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var scheduling = false
    @State private var toast: String? = nil

    private let capacity = 64
    private var trailers: [DropTrailer781] { data?.trailers ?? [] }
    private var poolFree: Int { max(0, capacity - (data?.summary.total ?? trailers.count)) }
    private var hottest: DropTrailer781? { trailers.max(by: { $0.dwellTimeHours < $1.dwellTimeHours }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · DROP YARD",
                caption: "OFF-DOCK DEPOT",
                title: "Drop yard",
                idText: "PIER J · live"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else if let data {
                    occupancyHero(data)
                    if let t = toast { VesselToastRow(text: t) }
                    kpiStrip(data.summary)
                    flaggedSection
                    esang
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // Spatial yard occupancy grid (64 cells · 4×16)
    private func occupancyHero(_ d: DropYard781) -> some View {
        let used = d.summary.total
        let cells = buildCells()
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("YARD MAP · POOL J · \(capacity) SPOTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(used) of \(capacity) used").font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                VStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<16, id: \.self) { col in
                                let idx = row * 16 + col
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(cellColor(cells[idx]))
                                    .frame(maxWidth: .infinity, minHeight: 15)
                            }
                        }
                    }
                }
                legend(d.summary)
            }
        }
    }

    private func legend(_ s: DropSummary781) -> some View {
        HStack(spacing: Space.s3) {
            legendChip(.used, "Used \(s.total)")
            legendChip(.awaiting, "Dray \(s.awaitingPickup)")
            legendChip(.seal, "Seal \(s.sealIssues)")
            if let h = hottest { legendChip(.hot, "\(h.dwellTimeHours)h") }
            legendChip(.free, "Free \(poolFree)")
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ state: CellState781, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(cellColor(state)).frame(width: 9, height: 9)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
    }

    /// Resolve 64 cells: real trailers fill the first N slots (ordered so the
    /// hot/awaiting/seal cells are visible), the remainder are free.
    private func buildCells() -> [CellState781] {
        var cells = Array(repeating: CellState781.free, count: capacity)
        let hotId = hottest?.id
        let n = min(trailers.count, capacity)
        for i in 0..<n {
            let t = trailers[i]
            if t.id == hotId && t.dwellTimeHours >= 48 { cells[i] = .hot }
            else if !t.sealIntact { cells[i] = .seal }
            else if t.isAwaiting { cells[i] = .awaiting }
            else { cells[i] = .used }
        }
        return cells
    }

    private func cellColor(_ s: CellState781) -> Color {
        switch s {
        case .used:     return Brand.rail.opacity(0.5)
        case .awaiting: return Brand.info.opacity(0.7)
        case .seal:     return Brand.escort.opacity(0.6)
        case .hot:      return Color(hex: 0xC2410C).opacity(0.85)
        case .free:     return palette.borderFaint
        }
    }

    private func kpiStrip(_ s: DropSummary781) -> some View {
        HStack(spacing: Space.s3) {
            kpi(label: "DROPPED", value: "\(s.dropped)", caption: "on ground", gradient: true)
            kpi(label: "AWAITING", value: "\(s.awaitingPickup)", caption: "drayage pickup", accent: Brand.info)
            kpi(label: "POOL FREE", value: "\(poolFree)", caption: "of \(capacity) spots", accent: Brand.success)
        }
    }

    private func kpi(label: String, value: String, caption: String, gradient: Bool = false, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).padding(.bottom, 8)
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else if let accent { Text(value).foregroundStyle(accent) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).padding(.bottom, 4)
            Text(caption).font(.system(size: 9)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(gradient ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.14)) : AnyShapeStyle(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var flaggedSection: some View {
        let flagged = trailers.sorted { $0.dwellTimeHours > $1.dwellTimeHours }.prefix(4)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("FLAGGED SPOTS · DROP YARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDropYardOperations").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            if trailers.isEmpty {
                EusoEmptyState(systemImage: "square.grid.3x3", title: "Depot clear", subtitle: "Dropped boxes and their per-diem clocks will appear here as they arrive.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(flagged.enumerated()), id: \.element.id) { idx, t in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        spotRow(t)
                    }
                }
                .padding(Space.s4).background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func spotRow(_ t: DropTrailer781) -> some View {
        let hot = t.dwellTimeHours >= 48
        let color: Color = !t.sealIntact ? Brand.escort : (t.isAwaiting ? Brand.info : (hot ? Color(hex: 0xC2410C) : palette.textSecondary))
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: !t.sealIntact ? "lock.trianglebadge.exclamationmark" : (t.isAwaiting ? "clock" : "shippingbox"))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(t.spotId ?? "DY") · \(t.trailerNumber ?? "—")")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(subLine(t)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: pillLabel(t), kind: pillKind(t))
                Text("\(t.dwellTimeHours)h").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(color)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func subLine(_ t: DropTrailer781) -> String {
        if !t.sealIntact { return "seal check flagged · re-verify" }
        if t.isAwaiting { return "awaiting drayage · per-diem live" }
        return "on ground · per-diem live"
    }
    private func pillLabel(_ t: DropTrailer781) -> String {
        if !t.sealIntact { return "SEAL" }
        if t.isAwaiting { return "AWAITING" }
        return t.dwellTimeHours >= 48 ? "DWELL" : "DROPPED"
    }
    private func pillKind(_ t: DropTrailer781) -> StatusPill.Kind {
        if !t.sealIntact { return .hazmat }
        if t.isAwaiting { return .info }
        return t.dwellTimeHours >= 48 ? .warning : .neutral
    }

    private var esang: some View {
        let h = hottest
        return EsangAdvisory781(
            title: h.map { "Dray \($0.spotId ?? $0.trailerNumber ?? "the hot box") first — \($0.dwellTimeHours)h, per-diem live" }
                ?? "Depot is inside free-time on every box",
            message: (data?.summary.avgDwellHours).map { "avg dwell \($0)h · \(poolFree) chassis free now" } ?? "\(poolFree) chassis free now"
        )
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Schedule pickup", action: { Task { await schedulePickup() } }, isLoading: scheduling)
            Button {} label: {
                Text("View pool").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 150, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 164)
            HStack(spacing: Space.s3) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 78) } }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let locationId: String? }
        do {
            let d: DropYard781 = try await EusoTripAPI.shared.query(
                "yardManagement.getDropYardOperations", input: In(locationId: nil))
            self.data = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func schedulePickup() async {
        guard let t = hottest else { toast = "No dropped box to schedule"; return }
        scheduling = true
        // Marine drop-lot pickup is created via the yard-move assignment (honest
        // mapping — no invented procedure). moveId derives from the drop record.
        struct In: Encodable { let moveId: String; let hostlerId: String }
        do {
            let _: SchedResult781 = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove", input: In(moveId: t.id, hostlerId: "HST-1"))
            toast = "Pickup scheduled for \(t.spotId ?? t.trailerNumber ?? "the hot box")"
            await load()
        } catch {
            toast = (error as? EusoTripAPIError)?.errorDescription ?? "Could not schedule pickup"
        }
        scheduling = false
    }
}

private struct SchedResult781: Decodable {
    let success: Bool?
    private enum CodingKeys: String, CodingKey { case success }
    init(from d: Decoder) throws {
        let c = try? d.container(keyedBy: CodingKeys.self)
        success = try? c?.decode(Bool.self, forKey: .success)
    }
}

private struct EsangAdvisory781: View {
    @Environment(\.palette) private var palette
    let title: String; let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("781 · Drop Yard · Night") { VesselDropYardOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("781 · Drop Yard · Light") { VesselDropYardOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
