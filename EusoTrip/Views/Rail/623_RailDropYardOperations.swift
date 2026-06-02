//
//  623_RailDropYardOperations.swift
//  EusoTrip — Rail Engineer · Drop Yard Operations.
//
//  CARRIER-SIDE BOARD for the drop lot — dropped trailers/containers awaiting
//  pickup, split into AWAITING-PICKUP and SEAL-ISSUE lanes. Each row carries a
//  trailer chip + slot/equipment + container ID + seal state + relative dwell
//  bar + tabular dwell-hours so the engineer dispatches a chassis to the aging
//  reefer before it tips into detention.
//
//  Web parity: app/(rail)/yard/drop/page.tsx
//  Wiring (yardManagement.ts, protectedProcedure · companyId-scoped):
//    • board   ← yardManagement.getDropYardOperations  (EXISTS · :1521)
//    • Chassis ← yardManagement.getChassisInventory    (EXISTS · :1133)
//    • Assign  → yardManagement.assignTrailer          (EXISTS · :1035, mutation)
//

import SwiftUI

struct RailDropYardOperationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDropYardOperationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror yardManagement.getDropYardOperations row + summary)

private struct DropYardTrailer: Decodable, Identifiable {
    let id: String
    let trailerNumber: String?
    let status: String?              // dropped | awaiting_pickup | loaded_waiting | empty_waiting
    let droppedBy: String?
    let droppedAt: String?
    let pickupScheduled: String?
    let pickupDriver: String?
    let loadId: String?
    let dwellTimeHours: Double?
    let spotId: String?
    let sealIntact: Bool?
    let notes: String?
}

private struct DropYardSummary: Decodable {
    let total: Int?
    let dropped: Int?
    let awaitingPickup: Int?
    let avgDwellHours: Double?
    let sealIssues: Int?
}

private struct DropYardResponse: Decodable {
    let trailers: [DropYardTrailer]
    let summary: DropYardSummary
}

// Chassis inventory — surfaced via the "Chassis" CTA sheet.
private struct ChassisUnit: Decodable, Identifiable {
    let id: String
    let chassisNumber: String?
    let type: String?
    let status: String?              // available | in_use | maintenance | out_of_service
    let owner: String?
    let containerId: String?
    let locationId: String?
    let condition: String?
}

private struct ChassisSummary: Decodable {
    let total: Int?
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
    let outOfService: Int?
}

private struct ChassisResponse: Decodable {
    let chassis: [ChassisUnit]
    let summary: ChassisSummary
}

private struct AssignResult: Decodable {
    let success: Bool?
    let trailerId: String?
    let assignedAt: String?
}

// MARK: - Body

private struct RailDropYardOperationsBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var trailers: [DropYardTrailer] = []
    @State private var summary: DropYardSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Filter chips (All / Awaiting / Dropped / Seal)
    enum Filter { case all, awaiting, dropped, seal }
    @State private var filter: Filter = .all

    // Chassis sheet
    @State private var showChassis = false
    @State private var chassis: [ChassisUnit] = []
    @State private var chassisSummary: ChassisSummary? = nil
    @State private var chassisLoading = false
    @State private var chassisError: String? = nil

    // Assign-pickup flow
    @State private var assigning = false
    @State private var assignBanner: String? = nil

    // Derived lanes ───────────────────────────────────────────────────────
    private func isSeal(_ t: DropYardTrailer) -> Bool { !(t.sealIntact ?? true) }

    private var awaitingLane: [DropYardTrailer] {
        trailers.filter { !isSeal($0) }
    }
    private var sealLane: [DropYardTrailer] {
        trailers.filter { isSeal($0) }
    }

    private var filteredTrailers: [DropYardTrailer] {
        switch filter {
        case .all:      return trailers
        case .awaiting: return trailers.filter { ($0.status ?? "") == "awaiting_pickup" && !isSeal($0) }
        case .dropped:  return trailers.filter { ($0.status ?? "") == "dropped" && !isSeal($0) }
        case .seal:     return sealLane
        }
    }

    // Counts for the chips — driven off the real summary where present.
    private var allCount: Int      { summary?.total ?? trailers.count }
    private var awaitingCount: Int { trailers.filter { ($0.status ?? "") == "awaiting_pickup" && !isSeal($0) }.count }
    private var droppedCount: Int  { summary?.dropped ?? trailers.filter { ($0.status ?? "") == "dropped" }.count }
    private var sealCount: Int     { summary?.sealIssues ?? sealLane.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if let banner = assignBanner {
                        assignBannerView(banner)
                    }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if trailers.isEmpty {
                        EusoEmptyState(systemImage: "tray.full",
                                       title: "No dropped units",
                                       subtitle: "Trailers and containers in the drop lot will appear here.")
                            .padding(.top, Space.s4)
                    } else {
                        // AWAITING-PICKUP lane
                        sectionHeader(title: "AWAITING PICKUP · \(awaitingLane.count)",
                                      color: Brand.info)
                        if awaitingLane.isEmpty {
                            emptyLane("No units awaiting pickup")
                        } else {
                            laneCard(awaitingLane)
                        }

                        // SEAL-ISSUE lane
                        sectionHeader(title: "SEAL ISSUE · \(sealLane.count)",
                                      color: Brand.danger)
                            .padding(.top, Space.s2)
                        if sealLane.isEmpty {
                            emptyLane("No seal exceptions")
                        } else {
                            laneCard(sealLane)
                        }

                        actionRow
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showChassis) {
            ChassisSheet(chassis: chassis,
                         summary: chassisSummary,
                         loading: chassisLoading,
                         error: chassisError)
                .environment(\.palette, palette)
        }
    }

    // MARK: - Top bar (eyebrow + back + title + subtitle + filter chips)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row
            HStack {
                Text("✦  RAIL ENGINEER · DROP YARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(boardRef)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            // Back chevron + title + overflow
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                Text("Drop yard")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s3)

            // Subtitle
            Text(subtitleText)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
                .padding(.leading, 24)

            // Filter chips
            filterChips
                .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var boardRef: String {
        let f = DateFormatter(); f.dateFormat = "yyMMdd"
        return "RAIL-\(f.string(from: Date()))-DROP"
    }

    private var subtitleText: String {
        if let s = summary {
            return "Corwith Intermodal · \(s.dropped ?? 0) dropped · \(s.awaitingPickup ?? awaitingCount) awaiting"
        }
        return "Corwith Intermodal · drop lot operations"
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip("All · \(allCount)",      f: .all,      tint: nil)
                chip("Awaiting · \(awaitingCount)", f: .awaiting, tint: Color(hex: 0x4DA3FF))
                chip("Dropped · \(droppedCount)",   f: .dropped,  tint: Color(hex: 0x90A4AE))
                chip("Seal · \(sealCount)",         f: .seal,     tint: Color(hex: 0xFF6B5E))
            }
        }
    }

    @ViewBuilder
    private func chip(_ label: String, f: Filter, tint: Color?) -> some View {
        let active = (filter == f)
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { filter = f }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(active ? Color.white : (tint ?? palette.textSecondary))
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(
                    Group {
                        if active {
                            AnyView(LinearGradient.primary)
                        } else {
                            AnyView(Color(hex: 0x232932))
                        }
                    }
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(active ? Color.clear : Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header ("AWAITING PICKUP · N" + "see all ›")

    private func sectionHeader(title: String, color: Color) -> some View {
        VStack(spacing: Space.s2) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Lane card (rows wrapped in one bordered surface)

    private func laneCard(_ rows: [DropYardTrailer]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, t in
                trailerRow(t)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, Space.s4)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .background(Color(hex: 0x1C2128))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Trailer row

    private func trailerRow(_ t: DropYardTrailer) -> some View {
        let dwell = t.dwellTimeHours ?? 0
        let seal = isSeal(t)
        let accent = rowAccent(t)
        let badge = rowBadge(t)

        return HStack(alignment: .top, spacing: Space.s3) {
            // Trailer chip (40×40, colored tint + outline glyph)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                Image(systemName: "box.truck")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(slotTitle(t))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(metaLine(t))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                // Relative dwell bar
                dwellBar(hours: dwell, color: accent)
                    .padding(.top, 2)
            }

            Spacer(minLength: 4)

            // Badge + dwell hours (tabular) + "dwell"
            VStack(alignment: .trailing, spacing: 6) {
                Text(badge)
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(Capsule().fill(accent.opacity(0.20)))
                Spacer(minLength: 0)
                Text(dwellLabel(dwell))
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("dwell")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 56)
            // Tag the seal-broken rows so VoiceOver reads the exception.
            .accessibilityLabel(seal ? "seal exception, \(dwellLabel(dwell)) dwell" : "\(dwellLabel(dwell)) dwell")
        }
        .padding(Space.s4)
    }

    // Relative dwell bar — fraction of a 48h reference window, clamped.
    private func dwellBar(hours: Double, color: Color) -> some View {
        let frac = max(0.06, min(hours / 48.0, 1.0))
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(6, w * frac))
            }
        }
        .frame(width: 180, height: 6)
    }

    // MARK: - Row classification helpers

    private func slotTitle(_ t: DropYardTrailer) -> String {
        let slot = t.spotId ?? "—"
        let equip = equipmentLabel(t)
        return "Slot \(slot) · \(equip)"
    }

    private func equipmentLabel(_ t: DropYardTrailer) -> String {
        // The server marks reefers by the trailer number suffix only loosely;
        // surface the real status descriptor when available, else "dry van".
        if let notes = t.notes, notes.lowercased().contains("reefer") { return "reefer" }
        return "dry van"
    }

    private func metaLine(_ t: DropYardTrailer) -> String {
        let id = t.trailerNumber ?? t.id
        if isSeal(t) {
            let reason = t.notes ?? "seal broken · hold"
            return "\(id) · \(reason)"
        }
        let by = t.droppedBy.flatMap { $0 == "Unknown" ? nil : "\($0) dray" } ?? "dropped"
        return "\(id) · \(by) · sealed"
    }

    private func rowAccent(_ t: DropYardTrailer) -> Color {
        if isSeal(t) { return Color(hex: 0xFF6B5E) }            // seal exception → red
        let dwell = t.dwellTimeHours ?? 0
        if dwell >= 36 { return Brand.warning }                 // aging
        if dwell >= 24 { return Brand.blue }                    // ready, longer dwell
        return Brand.success                                    // fresh / ready
    }

    private func rowBadge(_ t: DropYardTrailer) -> String {
        if isSeal(t) { return "SEAL" }
        let dwell = t.dwellTimeHours ?? 0
        if dwell >= 36 { return "AGING" }
        return "READY"
    }

    private func dwellLabel(_ hours: Double) -> String {
        "\(Int(hours.rounded()))h"
    }

    // MARK: - Action row (Assign pickup · Chassis)

    private var actionRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await assignPickup() }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Assign pickup")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(assigning ? 0.6 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(assigning || awaitingLane.isEmpty)

            Button {
                showChassis = true
                Task { await loadChassis() }
            } label: {
                Text("Chassis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s5)
                    .frame(height: 48)
                    .background(Color(hex: 0x232932))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s4)
    }

    private func assignBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            Text(text)
                .font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color(hex: 0x1C2128))
                    .frame(height: 86)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .padding(.top, Space.s4)
    }

    private func emptyLane(_ msg: String) -> some View {
        Text(msg)
            .font(EType.caption).foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Space.s4)
            .background(Color(hex: 0x1C2128))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Loaders

    private func reload() async {
        loading = true; loadError = nil
        struct In: Encodable {}
        do {
            let resp: DropYardResponse = try await EusoTripAPI.shared.query(
                "yardManagement.getDropYardOperations", input: In())
            self.trailers = resp.trailers
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadChassis() async {
        chassisLoading = true; chassisError = nil
        struct In: Encodable {}
        do {
            let resp: ChassisResponse = try await EusoTripAPI.shared.query(
                "yardManagement.getChassisInventory", input: In())
            self.chassis = resp.chassis
            self.chassisSummary = resp.summary
        } catch {
            chassisError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        chassisLoading = false
    }

    private func assignPickup() async {
        // Assign the highest-dwell awaiting unit to a chassis pickup —
        // the row most at risk of tipping into detention.
        guard let target = awaitingLane.max(by: { ($0.dwellTimeHours ?? 0) < ($1.dwellTimeHours ?? 0) })
        else { return }
        assigning = true; assignBanner = nil
        struct In: Encodable {
            let trailerId: String
            let notes: String
        }
        do {
            let res: AssignResult = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignTrailer",
                input: In(trailerId: target.id, notes: "Drop-yard pickup assigned from board"))
            if res.success == true {
                assignBanner = "Pickup assigned · \(target.trailerNumber ?? target.id) → chassis dispatch"
                await reload()
            } else {
                assignBanner = "Assign returned no confirmation."
            }
        } catch {
            assignBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = false
    }
}

// MARK: - Chassis sheet (getChassisInventory)

private struct ChassisSheet: View {
    let chassis: [ChassisUnit]
    let summary: ChassisSummary?
    let loading: Bool
    let error: String?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Chassis inventory")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if let s = summary {
                    HStack(spacing: Space.s2) {
                        MetricTile(label: "TOTAL",     value: "\(s.total ?? 0)", gradientNumeral: true)
                        MetricTile(label: "AVAILABLE", value: "\(s.available ?? 0)", accent: Brand.success)
                        MetricTile(label: "IN USE",    value: "\(s.inUse ?? 0)")
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.s5)
                } else if let err = error {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if chassis.isEmpty {
                    EusoEmptyState(systemImage: "trailer",
                                   title: "No chassis on lot",
                                   subtitle: "Available chassis for pickup will appear here.")
                        .padding(.top, Space.s4)
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(chassis) { c in chassisRow(c) }
                    }
                }
                Color.clear.frame(height: 24)
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
    }

    private func chassisRow(_ c: ChassisUnit) -> some View {
        let avail = (c.status ?? "") == "available"
        let color: Color = avail ? Brand.success : palette.textSecondary
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "trailer.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.chassisNumber ?? c.id)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let type = c.type {
                        Text(type).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    if let cond = c.condition {
                        Text("· \(cond)").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text((c.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

#Preview("623 · Rail Drop Yard · Night") { RailDropYardOperationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("623 · Rail Drop Yard · Light") { RailDropYardOperationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
