//
//  402_CatalystCapacityPlanner.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: a carrier sells the empty truck-days it can SEE. This is a BOARD/grid
//          archetype — NOT the home/detail skeleton: a utilization hero with a
//          committed/open/maintenance stacked bar, a 7-day availability HEAT-GRID
//          (every unit × every day, committed=gradient / open=faint / maint=amber),
//          and an open-window list that turns each gap into a post or auto-match.
//          The grid is the bespoke element — it maps idle capacity at a glance so a
//          truck never sits unsold.
//
//  SwiftUI twin of 03 Catalyst/Dark-SVG/402 Catalyst Capacity Planner.svg.
//  Web peer: /catalyst/dispatch/capacity. transportMode=truck; country=US.
//  Persona: Eusotrans LLC · Michael Eusorone owner-op · 6 trucks.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13):
//    • utilization hero + stacked bar → capacityPlanning.getCapacityDashboard (capacityPlanning.ts:65)
//    • 7-day grid + open windows      → carrierCapacity.getCapacityCalendar   (carrierCapacity.ts:22)
//      (real per-day availableTrucks; grid cells fill proportionally, count
//       labels show the true available/fleet numbers)
//  Both decoded in-file against the exact server projections. Anything with
//  no live source (open miles) renders an honest em-dash; honest
//  EusoEmptyState when no calendar/fleet exists. The seeded 6-truck week
//  and invented best-match RPM rows are GONE.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (DISPATCH current).
//

import SwiftUI

// MARK: - Shell wrapper

struct CatalystCapacityPlannerScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CapacityBody_402()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_402(),
                trailing: catalystNavTrailing_402(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Catalyst BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — DISPATCH current)

private func catalystNavLeading_402() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_402() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - View model

private enum CapacityCell_402 { case committed, open, maintenance }

private struct CapacityDay_402: Identifiable {
    let id: String          // "Thu 30"
    let dow: String         // "Thu"
    let date: String        // "30"
    let cells: [CapacityCell_402]   // one per unit, top→bottom
    let countLabel: String  // "4/6"
    let countHot: Bool      // ink the count blue when there's open capacity
}

private struct OpenWindow_402: Identifiable {
    let id: String          // unit
    let unit: String        // "261"
    let title: String       // "Unit 261 · Dallas TX"
    let window: String      // mono "open Thu–Fri · dry van · 1,040 open mi"
    let match: String       // "best match: DFW → Memphis $2.18/mi"
}

private struct CapacityVM_402 {
    let utilization: String         // "78%"
    let openSlots: String           // "5 truck-days"
    let openMiles: String           // "2,140 mi"
    let committedFrac: Double       // 33/42
    let openFrac: Double            // 5/42
    let maintFrac: Double           // 1/42
    let barCaption: String
    let unitCount: String           // "6 units"
    let openWindowHeader: String    // "2 of 5"
    let days: [CapacityDay_402]
    let openWindows: [OpenWindow_402]
    let insightTitle: String
    let insightSub: String
}

// MARK: - Body

private struct CapacityBody_402: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var vm: CapacityVM_402 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var actionLoading: Bool = false
    @State private var actionError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var showInsightSheet: Bool = false
    @State private var showPostTruckSheet: Bool = false
    @State private var showMatchSheet: Bool = false
    @State private var fleetRows: [TruckFleetVehicle] = []
    @State private var inboundOffers: [CarrierTruckInboundOffer] = []
    @State private var postingResults: [TruckPostResult] = []
    @State private var postingBusyIds: Set<Int> = []
    @State private var offerBusyIds: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                gridSection
                openWindowSection
                insightRow
                ctaPair
                actionFeedback
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await loadAll_402() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll_402() }
        }
        .eusoRefreshHandler { await loadAll_402() }
        .sheet(isPresented: $showInsightSheet) { insightSheet }
        .sheet(isPresented: $showPostTruckSheet) { postTruckSheet }
        .sheet(isPresented: $showMatchSheet) { matchSheet }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "CATALYST · CAPACITY")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("NEXT 7 DAYS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Dispatch")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacity")
                        .font(EType.display)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(vm.unitCount) · committed vs open")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero · fleet utilization

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FLEET UTILIZATION · 7-DAY")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.utilization)
                            .font(.system(size: 38, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("OPEN SLOTS")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.openSlots)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Brand.blue)
                        Text("OPEN MILES")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.openMiles)
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                stackedBar.padding(.top, Space.s4)
                Text(vm.barCaption)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 136)
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 4) {
                Capsule().fill(LinearGradient.primary)
                    .frame(width: w * vm.committedFrac)
                Capsule().fill(Brand.blue.opacity(0.20))
                    .frame(width: w * vm.openFrac)
                Capsule().fill(Brand.hazmat.opacity(0.7))
                    .frame(width: max(8, w * vm.maintFrac))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Utilization \(vm.utilization)")
    }

    // MARK: 7-day availability heat-grid

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("7-DAY AVAILABILITY GRID")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.unitCount)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Group {
                if vm.days.isEmpty {
                    EusoEmptyState(
                        systemImage: "calendar",
                        title: loading ? "Loading availability…" : "No capacity calendar yet",
                        subtitle: loading ? "" : (loadError ?? "Your fleet's 7-day availability grid appears here once vehicles and loads are on file.")
                    )
                    .padding(.vertical, Space.s3)
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 0) {
                        ForEach(vm.days) { day in
                            VStack(spacing: 4) {
                                Text(day.dow)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(palette.textSecondary)
                                Text(day.date)
                                    .font(.system(size: 8))
                                    .foregroundStyle(palette.textTertiary)
                                VStack(spacing: 4) {
                                    ForEach(Array(day.cells.enumerated()), id: \.offset) { _, cell in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(cellStyle(cell))
                                            .frame(height: 12)
                                    }
                                }
                                .padding(.top, 2)
                                Text(day.countLabel)
                                    .font(.system(size: 9, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(day.countHot ? Brand.blue : palette.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s3)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func cellStyle(_ c: CapacityCell_402) -> AnyShapeStyle {
        switch c {
        case .committed:   return AnyShapeStyle(Brand.blue)
        case .open:        return AnyShapeStyle(Brand.blue.opacity(0.14))
        case .maintenance: return AnyShapeStyle(Brand.hazmat.opacity(0.7))
        }
    }

    // MARK: Open-window list

    private var openWindowSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("OPEN WINDOWS · SELLABLE NOW")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.openWindowHeader)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.openWindows.isEmpty {
                    EusoEmptyState(
                        systemImage: "truck.box",
                        title: loading ? "Loading open windows…" : "No open windows this week",
                        subtitle: loading ? "" : "Days with unsold truck capacity appear here so they can be posted or auto-matched."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.openWindows.enumerated()), id: \.element.id) { idx, w in
                        openRow(w)
                        if idx < vm.openWindows.count - 1 {
                            Rectangle().fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func openRow(_ w: OpenWindow_402) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm + 2)
                    .fill(Brand.blue.opacity(0.12))
                Text(w.unit)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.blue)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(w.window)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(w.match)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.blue)
            }
            Spacer(minLength: Space.s2)
            Text("OPEN")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.blue)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Brand.blue.opacity(0.14)))
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(w.title), open, \(w.match)")
    }

    // MARK: ESang insight row

    private var insightRow: some View {
        Button {
            actionError = nil
            showInsightSheet = true
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(
                        colors: [.white.opacity(0.75), .clear],
                        center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.insightTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                openPostTruckSheet()
            } label: {
                Text("Post open trucks")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            Button {
                openMatchSheet()
            } label: {
                Text("Auto-match")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    private var actionFeedback: some View {
        Group {
            if let actionError {
                Text(actionError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.hazmat)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.hazmat.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            } else if let actionMessage {
                Text(actionMessage)
                    .font(EType.caption)
                    .foregroundStyle(Brand.blue)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.blue.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    private var insightSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Capacity Insight")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(vm.insightTitle)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(vm.insightSub)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 0) {
                metricRow(label: "Utilization", value: vm.utilization)
                Divider().overlay(palette.borderFaint)
                metricRow(label: "Open slots", value: vm.openSlots)
                Divider().overlay(palette.borderFaint)
                metricRow(label: "Fleet", value: vm.unitCount)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var postTruckSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post Open Trucks")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Only vehicles with a live GPS fix can be posted.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if actionLoading {
                    ProgressView().tint(Brand.blue)
                }
            }
            ScrollView {
                VStack(spacing: Space.s3) {
                    if fleetRows.isEmpty && !actionLoading {
                        EusoEmptyState(
                            systemImage: "truck.box",
                            title: "No available trucks ready to post",
                            subtitle: "Available fleet rows appear here after vehicles report a live location."
                        )
                        .padding(.vertical, Space.s4)
                    }
                    ForEach(fleetRows) { truck in
                        postTruckRow(truck)
                    }
                    if !postingResults.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("RECENT POSTS")
                                .font(EType.micro).tracking(1.0)
                                .foregroundStyle(palette.textTertiary)
                            ForEach(postingResults, id: \.postingId) { result in
                                Text("Posting #\(result.postingId) · vehicle \(result.vehicleId) · \(result.offersSurfaced ?? 0) offers surfaced")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
                .padding(.bottom, Space.s4)
            }
        }
        .padding(Space.s5)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func postTruckRow(_ truck: TruckFleetVehicle) -> some View {
        let location = liveLocation(truck)
        let isBusy = postingBusyIds.contains(truck.id)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.blue)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Brand.blue.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(truckTitle(truck))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(truckSubtitle(truck))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text(location == nil ? "GPS fix required before posting" : "Live location ready")
                        .font(EType.caption)
                        .foregroundStyle(location == nil ? Brand.hazmat : Brand.blue)
                }
                Spacer()
                Button {
                    Task { await postTruck(truck) }
                } label: {
                    if isBusy {
                        ProgressView().tint(.white)
                            .frame(width: 72, height: 34)
                            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(LinearGradient.primary))
                    } else {
                        Text("Post")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 34)
                            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(LinearGradient.primary))
                    }
                }
                .buttonStyle(.plain)
                .disabled(location == nil || isBusy)
                .opacity(location == nil ? 0.45 : 1)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var matchSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Match")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Live inbound offers from posted trucks and the matching engine.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if actionLoading {
                    ProgressView().tint(Brand.blue)
                }
            }
            ScrollView {
                VStack(spacing: Space.s3) {
                    if inboundOffers.isEmpty && !actionLoading {
                        EusoEmptyState(
                            systemImage: "arrow.triangle.branch",
                            title: "No live offers yet",
                            subtitle: "Post an available truck, then auto-match will surface compatible broker loads here."
                        )
                        .padding(.vertical, Space.s4)
                    }
                    ForEach(inboundOffers) { offer in
                        offerRow(offer)
                    }
                }
                .padding(.bottom, Space.s4)
            }
        }
        .padding(Space.s5)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func offerRow(_ offer: CarrierTruckInboundOffer) -> some View {
        let busy = offerBusyIds.contains(offer.offerId)
        let load = offer.load
        let route = load.map { "\(placeLabel($0.origin)) → \(placeLabel($0.destination))" } ?? "Route unavailable"
        let title = load?.loadNumber ?? "Offer #\(offer.offerId)"
        let rate = offer.offeredRate.map { "$\(Int($0.rounded()))" } ?? "Rate pending"
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(route)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(rate) · \(offer.status.uppercased())")
                        .font(EType.caption)
                        .foregroundStyle(Brand.blue)
                }
                Spacer()
                if busy {
                    ProgressView().tint(Brand.blue)
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    Task { await acceptOffer(offer) }
                } label: {
                    Text("Accept")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(LinearGradient.primary))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Button {
                    Task { await declineOffer(offer) }
                } label: {
                    Text("Decline")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgElev))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
    }

    private func openPostTruckSheet() {
        actionError = nil
        actionMessage = nil
        showPostTruckSheet = true
        Task { await loadFleetAvailability() }
    }

    private func openMatchSheet() {
        actionError = nil
        actionMessage = nil
        showMatchSheet = true
        Task { await loadInboundOffers() }
    }

    private func loadFleetAvailability() async {
        actionLoading = true
        defer { actionLoading = false }
        do {
            fleetRows = try await EusoTripAPI.shared.truckPosting.getMyFleetAvailability(status: "available")
        } catch {
            actionError = "Couldn't load available trucks: \(surfaceMessage(error))"
        }
    }

    private func loadInboundOffers() async {
        actionLoading = true
        defer { actionLoading = false }
        do {
            let envelope = try await EusoTripAPI.shared.truckPosting.listInboundOffers(status: "pending", runMatcher: true)
            inboundOffers = envelope.offers
        } catch {
            actionError = "Couldn't run auto-match: \(surfaceMessage(error))"
        }
    }

    private func postTruck(_ truck: TruckFleetVehicle) async {
        actionError = nil
        guard let location = liveLocation(truck) else {
            actionError = "Vehicle \(truck.id) needs a live GPS fix before it can be posted."
            return
        }
        postingBusyIds.insert(truck.id)
        defer { postingBusyIds.remove(truck.id) }
        do {
            let result = try await EusoTripAPI.shared.truckPosting.postTruck(
                vehicleId: truck.id,
                currentLocation: location,
                availableDate: ISO8601DateFormatter().string(from: Date()),
                driverId: truck.currentDriverId,
                equipmentType: truck.vehicleType,
                notes: "Posted from Catalyst Capacity Planner"
            )
            postingResults.removeAll { $0.vehicleId == result.vehicleId }
            postingResults.insert(result, at: 0)
            actionMessage = "Truck \(truck.id) posted. \(result.offersSurfaced ?? 0) live offer\(result.offersSurfaced == 1 ? "" : "s") surfaced."
            await loadFleetAvailability()
            await loadInboundOffers()
        } catch {
            actionError = "Couldn't post truck \(truck.id): \(surfaceMessage(error))"
        }
    }

    private func acceptOffer(_ offer: CarrierTruckInboundOffer) async {
        actionError = nil
        offerBusyIds.insert(offer.offerId)
        defer { offerBusyIds.remove(offer.offerId) }
        do {
            let result = try await EusoTripAPI.shared.truckPosting.acceptOffer(offerId: offer.offerId)
            let confirmation = result.confirmationNumber ?? result.bookingId ?? "load \(result.loadId)"
            actionMessage = "Offer \(offer.offerId) booked: \(confirmation)."
            await loadInboundOffers()
            await loadAll_402()
        } catch {
            actionError = "Couldn't accept offer \(offer.offerId): \(surfaceMessage(error))"
        }
    }

    private func declineOffer(_ offer: CarrierTruckInboundOffer) async {
        actionError = nil
        offerBusyIds.insert(offer.offerId)
        defer { offerBusyIds.remove(offer.offerId) }
        do {
            _ = try await EusoTripAPI.shared.truckPosting.declineOffer(offerId: offer.offerId)
            actionMessage = "Offer \(offer.offerId) declined."
            await loadInboundOffers()
        } catch {
            actionError = "Couldn't decline offer \(offer.offerId): \(surfaceMessage(error))"
        }
    }

    private func liveLocation(_ truck: TruckFleetVehicle) -> TruckPostLocation? {
        guard let lat = truck.location?.lat,
              let lng = truck.location?.lng,
              let coordinate = LatLongParser.validatedCoordinate(
                  latitude: lat,
                  longitude: lng
              ) else {
            return nil
        }
        return TruckPostLocation(
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            city: nil,
            state: nil
        )
    }

    private func truckTitle(_ truck: TruckFleetVehicle) -> String {
        let pieces = [truck.year.map(String.init), truck.make, truck.model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pieces.isEmpty ? "Vehicle \(truck.id)" : pieces.joined(separator: " ")
    }

    private func truckSubtitle(_ truck: TruckFleetVehicle) -> String {
        let type = truck.vehicleType?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = truck.status?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plate = truck.licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [type, status, plate].compactMap { value in
            value.flatMap { $0.isEmpty ? nil : $0 }
        }
        return parts.isEmpty ? "Fleet vehicle" : parts.joined(separator: " · ")
    }

    private func placeLabel(_ place: CarrierTruckInboundOffer.OfferLoad.Place) -> String {
        let parts = [place.city, place.state].compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    private func surfaceMessage(_ error: Error) -> String {
        let localized = error.localizedDescription
        return localized.isEmpty ? String(describing: error) : localized
    }

    // MARK: - Network (LIVE — getCapacityDashboard + getCapacityCalendar)

    private struct CapacityDashWire_402: Decodable {
        let totalTrucks: Int
        let availableTrucks: Int
        let inUseTrucks: Int
        let maintenanceTrucks: Int
        let totalDrivers: Int
        let activeLoads: Int
        let pendingLoads: Int
        let utilizationPct: Int
        let demandTrend: String
        let capacityStatus: String
    }
    private struct CalendarSlotWire_402: Decodable {
        let date: String
        let dayOfWeek: String
        let availableTrucks: Int
        let status: String
    }
    private struct CalendarWeekWire_402: Decodable {
        let weekStart: String
        let weekEnd: String
        let totalAvailableTruckDays: Int
        let slots: [CalendarSlotWire_402]
    }
    private struct CalendarWire_402: Decodable {
        let carrierId: Int
        let companyName: String?
        let fleetSize: Int
        let weeks: [CalendarWeekWire_402]
    }
    private struct CalendarInput_402: Encodable { let carrierId: Int; let weeks: Int }
    private struct EmptyInput_402: Encodable {}

    private func loadAll_402() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let dash: CapacityDashWire_402 = try await EusoTripAPI.shared.query(
                "capacityPlanning.getCapacityDashboard", input: EmptyInput_402())

            var calendar: CalendarWire_402? = nil
            if let cidString = session.user?.companyId, let cid = Int(cidString) {
                calendar = try? await EusoTripAPI.shared.query(
                    "carrierCapacity.getCapacityCalendar",
                    input: CalendarInput_402(carrierId: cid, weeks: 1))
            }

            vm = buildVM_402(dash: dash, calendar: calendar)
        } catch {
            vm = .empty
            loadError = "Couldn't reach the capacity service - retry."
        }
    }

    private func buildVM_402(dash: CapacityDashWire_402, calendar: CalendarWire_402?) -> CapacityVM_402 {
        let total = max(0, dash.totalTrucks)
        let frac: (Int) -> Double = { total > 0 ? Double($0) / Double(total) : 0 }

        // 7-day grid from the REAL capacity calendar (proportional cell fill).
        var days: [CapacityDay_402] = []
        var openWindows: [OpenWindow_402] = []
        let week = calendar?.weeks.first
        if let week, let fleet = calendar?.fleetSize, fleet > 0 {
            let displayCells = min(fleet, 6)
            for slot in week.slots.prefix(7) {
                let available = max(0, min(fleet, slot.availableTrucks))
                let committed = fleet - available
                let committedCells = Int((Double(committed) / Double(fleet) * Double(displayCells)).rounded())
                var cells: [CapacityCell_402] = []
                for i in 0..<displayCells {
                    cells.append(i < committedCells ? .committed : .open)
                }
                let dayNum = String(slot.date.suffix(2))
                days.append(CapacityDay_402(
                    id: slot.date,
                    dow: String(slot.dayOfWeek.prefix(3)),
                    date: dayNum,
                    cells: cells,
                    countLabel: "\(available)/\(fleet)",
                    countHot: available > 0 && slot.status != "unavailable"
                ))
                if available > 0 && slot.status != "unavailable" {
                    openWindows.append(OpenWindow_402(
                        id: slot.date,
                        unit: dayNum,
                        title: "\(slot.dayOfWeek) \(String(slot.date.prefix(10)))",
                        window: "\(available) truck\(available == 1 ? "" : "s") open · \(slot.status)",
                        match: "post to the load board to fill"
                    ))
                }
            }
        }
        let openTruckDays = week?.totalAvailableTruckDays

        let softest = days.max { a, b in
            (Int(a.countLabel.split(separator: "/").first ?? "0") ?? 0)
                < (Int(b.countLabel.split(separator: "/").first ?? "0") ?? 0)
        }

        return CapacityVM_402(
            utilization: "\(dash.utilizationPct)%",
            openSlots: openTruckDays.map { "\($0) truck-days" } ?? "—",
            openMiles: "—",   // no open-mile rollup on any wired proc
            committedFrac: frac(dash.inUseTrucks),
            openFrac: frac(dash.availableTrucks),
            maintFrac: frac(dash.maintenanceTrucks),
            barCaption: total > 0
                ? "\(dash.inUseTrucks) in use · \(dash.availableTrucks) available · \(dash.maintenanceTrucks) maintenance · of \(total) trucks"
                : "No vehicles on file",
            unitCount: total > 0 ? "\(total) unit\(total == 1 ? "" : "s")" : "— units",
            openWindowHeader: openWindows.isEmpty ? "—" : "\(openWindows.count) of 7 days",
            days: days,
            openWindows: Array(openWindows.prefix(3)),
            insightTitle: softest.map { "Most open capacity: \($0.dow) · \($0.countLabel)" }
                ?? "Capacity \(dash.capacityStatus) · demand \(dash.demandTrend)",
            insightSub: "\(dash.activeLoads) active load\(dash.activeLoads == 1 ? "" : "s") · \(dash.pendingLoads) pending on the board"
        )
    }
}

// MARK: - Honest empty envelope (em-dash until a real hydrate)

private extension CapacityVM_402 {
    static let empty = CapacityVM_402(
        utilization: "—", openSlots: "—", openMiles: "—",
        committedFrac: 0, openFrac: 0, maintFrac: 0,
        barCaption: "—",
        unitCount: "— units",
        openWindowHeader: "—",
        days: [],
        openWindows: [],
        insightTitle: "No capacity insight yet",
        insightSub: "Live fleet and load data populate this board."
    )
}

// MARK: - Previews

#Preview("402 · Catalyst · Capacity · Night") {
    CatalystCapacityPlannerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("402 · Catalyst · Capacity · Afternoon") {
    CatalystCapacityPlannerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
