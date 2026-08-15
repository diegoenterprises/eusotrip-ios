//
//  702_DispatchLoadAssignment.swift
//  EusoTrip — Dispatch · Unassigned loads → assign driver mutation.
//
//  Reshaped 2026-05-23 from a tap-row → sheet-driven driver picker
//  into a two-pane drag-to-pair surface (top carousel of unassigned
//  load cards · bottom vertical list of available drivers). Drop a
//  load card on a driver row to fire `dispatch.assignDriver` in
//  one gesture instead of three taps. The legacy sheet picker stays
//  wired to the same mutation as a tap fallback for accessibility +
//  small-screen users who prefer not to drag.
//

import SwiftUI
import CoreLocation

struct DispatchLoadAssignmentScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadAssignBody() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct UnassignedLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let origin: String?
    let destination: String?
    let pickupDate: String?
    let rate: Double?
    let mode: String?
    // 2026-05-17 — Multi-modal payload from the server.
    let transportMode: String?
    let multiVehicleCount: Int?
    // Real pickup coords (server getUnassignedLoads) for the Matrix ETA strip.
    let pickupLat: Double?
    let pickupLng: Double?
}

private struct DriverPick: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let hoursRemaining: Double?
}

private struct LoadAssignBody: View {
    @Environment(\.palette) private var palette
    // Sheet→push (NAV remediation 2026-05-30): the tap-fallback driver
    // picker now pushes in-stack via the surface's detail layer +
    // BespokeBackBar instead of presenting as a `.sheet`. Nil outside a
    // role surface that installs RoleDetailLayer.
    @Environment(\.rolePushDetail) private var pushDetail
    @State private var loads: [UnassignedLoad] = []
    @State private var drivers: [DriverPick] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var pickFor: UnassignedLoad? = nil
    @State private var assigning: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAssigned: String? = nil
    /// Driver id currently being hovered over by a dragged load card.
    /// Drives the gradient stroke + faint inner highlight so the
    /// dispatcher gets clear drop-target feedback before releasing.
    @State private var hoverDriverId: String? = nil
    /// Sticky reference to the load being dragged. Used to render the
    /// "dragging LD-1234" inline pill on the driver row hover state.
    @State private var draggingLoadId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let msg = lastAssigned {
                    LifecycleCard(accentGradient: true) {
                        Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if loading && loads.isEmpty && drivers.isEmpty {
                    LifecycleCard {
                        Text("Loading dispatch board…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    matrixStrip
                    loadsCarousel
                    driversList
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · ASSIGNMENT · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Drag-to-assign")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag an unassigned load onto an available driver to fire LOAD_ASSIGNED. Or tap a load card for the picker.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Dispatch Matrix ETA strip — unassigned loads ranked by truck-aware
    /// drive time from the dispatcher's position (HERE Matrix Routing). Honest:
    /// only loads carrying REAL pickup coords participate; hides when none do.
    @ViewBuilder private var matrixStrip: some View {
        let candidates: [DispatchMatrixCandidate] = loads.compactMap { l in
            guard let lat = l.pickupLat, let lng = l.pickupLng, !(lat == 0 && lng == 0) else { return nil }
            return DispatchMatrixCandidate(id: l.id, loadNumber: l.loadNumber,
                                           coord: CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        if !candidates.isEmpty {
            DispatchMatrixCandidatesStrip(candidates: candidates)
        }
    }

    // MARK: - Loads carousel (top, horizontal, draggable cards)

    private var loadsCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("UNASSIGNED LOADS")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Text("\(loads.count)")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                Spacer(minLength: 0)
                Text("DRAG ↓ ONTO A DRIVER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if loads.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.seal",
                    title: "Inbox at zero",
                    subtitle: "Every active load has a driver. New tenders will land here."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Space.s3) {
                        ForEach(loads) { l in
                            // NOT a Button: on iOS the Button's tap recognizer wins
                            // the gesture race and `.draggable` never starts a drag.
                            // Plain view + .onTapGesture keeps the tap and lets the
                            // drag own the long-press.
                            loadCard(l)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    pickFor = l
                                    pushDetail?("Assign driver") { AnyView(driverPickerSheet(for: l)) }
                                }
                                .draggable(l.id) {
                                    loadCard(l)
                                        .frame(maxWidth: 280)
                                        .opacity(0.92)
                                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                                        .onAppear { draggingLoadId = l.id }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func loadCard(_ l: UnassignedLoad) -> some View {
        // Per-load mode → speak this load's origin-window language
        // (truck "PICKUP" · rail "WANT DATE" · vessel "ERD").
        let mode = TransportMode(rawValue: l.transportMode ?? l.mode ?? "truck") ?? .truck
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LifecycleSection(label: l.loadNumber.uppercased(), icon: "shippingbox")
                    Spacer(minLength: 0)
                    LoadModeBadge(
                        modeRaw: l.transportMode ?? l.mode,
                        multiVehicleCount: l.multiVehicleCount,
                        compact: true
                    )
                }
                Text("\(dashIfEmpty(l.origin)) → \(dashIfEmpty(l.destination))")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                HStack {
                    if let r = l.rate {
                        Text(usd(r))
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Text("\(TransportLexicon.short(.originWindow, mode: mode).uppercased()) \(humanISO(l.pickupDate).uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(width: 280)
    }

    // MARK: - Drivers list (bottom, vertical, drop destinations)

    private var driversList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("AVAILABLE DRIVERS")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Text("\(drivers.count)")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                Spacer(minLength: 0)
                Text("DROP ZONE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if drivers.isEmpty {
                EusoEmptyState(
                    systemImage: "person.3",
                    title: "No drivers available",
                    subtitle: "All drivers are on a load or off-duty. New availability surfaces here on the next refresh."
                )
            } else {
                ForEach(drivers) { d in driverRow(d) }
            }
        }
    }

    private func driverRow(_ d: DriverPick) -> some View {
        let isHover = hoverDriverId == d.id
        let isAssigning = assigning == d.id
        return LifecycleCard(accentGradient: isHover) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    LifecycleSection(label: d.name.uppercased(), icon: "person.fill")
                    Spacer(minLength: 0)
                    Text(d.status.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(Color.green)
                }
                LifecycleRow(label: "HOS left", value: d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "-")
                if isHover, let dragId = draggingLoadId,
                   let l = loads.first(where: { $0.id == dragId }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Drop to assign \(l.loadNumber)")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.top, 4)
                }
                if isAssigning {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("ASSIGNING…")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }.padding(.top, 4)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let loadId = droppedIds.first else { return false }
            // Drop must reference a known unassigned-loads entry; ignore
            // stray drops (e.g. another draggable from elsewhere in the
            // app that happens to flow through this drop zone).
            guard loads.first(where: { $0.id == loadId }) != nil else { return false }
            Task { await assign(loadId: loadId, driverId: d.id) }
            return true
        } isTargeted: { hovering in
            hoverDriverId = hovering ? d.id : (hoverDriverId == d.id ? nil : hoverDriverId)
        }
    }

    // MARK: - Tap fallback (legacy sheet picker)

    private func driverPickerSheet(for l: UnassignedLoad) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Pick driver for \(l.loadNumber)")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, 6)
                Text("Or drag the card from the carousel onto a driver row.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.bottom, 6)
                if drivers.isEmpty {
                    EusoEmptyState(
                        systemImage: "person.3",
                        title: "No available drivers",
                        subtitle: "All drivers are on a load or off-duty."
                    )
                } else {
                    ForEach(drivers) { d in
                        Button {
                            Task { await assign(loadId: l.id, driverId: d.id) }
                        } label: {
                            LifecycleCard {
                                LifecycleSection(label: d.name.uppercased(), icon: "person")
                                LifecycleRow(label: "Status",   value: d.status.uppercased())
                                LifecycleRow(label: "HOS left", value: d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "-")
                                if assigning == d.id { ProgressView().padding(.top, 6) }
                            }
                        }.buttonStyle(.plain).disabled(assigning != nil)
                    }
                }
            }
            .padding(14)
        }.background(palette.bgPage)
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true; loadError = nil
        do {
            async let l: [UnassignedLoad] = EusoTripAPI.shared.queryNoInput("dispatch.getUnassignedLoads")
            async let d: [DriverPick] = EusoTripAPI.shared.queryNoInput("dispatch.getDriverStatuses")
            let (loadsRes, driversRes) = try await (l, d)
            loads = loadsRes
            drivers = driversRes.filter { $0.status == "available" }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assign(loadId: String, driverId: String) async {
        await MainActor.run { assigning = driverId; actionError = nil }
        struct In: Encodable { let loadId: String; let driverId: String }
        struct Out: Decodable { let success: Bool? }
        let pickedLabel = pickFor?.loadNumber ?? loads.first(where: { $0.id == loadId })?.loadNumber ?? loadId
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.assignDriver",
                input: In(loadId: loadId, driverId: driverId)
            )
            await MainActor.run {
                // If the assignment came from the pushed picker (pickFor
                // set), pop the in-stack detail layer back to the board.
                // The drag path leaves pickFor nil, so no spurious pop.
                if pickFor != nil {
                    NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
                }
                lastAssigned = "Assigned · driver \(driverId) → \(pickedLabel)"
                pickFor = nil
                draggingLoadId = nil
                hoverDriverId = nil
            }
            await loadAll()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                draggingLoadId = nil
                hoverDriverId = nil
            }
        }
        await MainActor.run { assigning = nil }
    }
}

#Preview("702 · Load assign · Night") { DispatchLoadAssignmentScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("702 · Load assign · Afternoon") { DispatchLoadAssignmentScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

// MARK: - Dispatch Matrix ETA strip (HERE Matrix Routing add-on)

struct DispatchMatrixCandidate: Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let coord: CLLocationCoordinate2D
    static func == (l: DispatchMatrixCandidate, r: DispatchMatrixCandidate) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
final class DispatchMatrixStore: ObservableObject {
    struct Ranked: Identifiable, Hashable {
        let id: String; let loadNumber: String; let etaSeconds: Int; let meters: Int
    }
    @Published private(set) var ranked: [Ranked] = []
    @Published private(set) var isLoading = false

    func refresh(candidates: [DispatchMatrixCandidate]) async {
        guard !isLoading, !candidates.isEmpty else { ranked = []; return }
        isLoading = true
        defer { isLoading = false }
        guard let origin = await DriverLocationResolver.shared.currentCoordinate() else { ranked = []; return }
        let response: HereMatrixResponse
        do {
            response = try await HereMatrixClient.shared.matrix(
                origins: [origin],
                destinations: candidates.map(\.coord),
                profile: .standardUSSemiEmpty
            )
        } catch { ranked = []; return }
        let times = response.matrix.travelTimes ?? []
        let dists = response.matrix.distances ?? []
        guard times.count == candidates.count else { ranked = []; return }
        var rows: [Ranked] = []
        for (idx, c) in candidates.enumerated() {
            rows.append(Ranked(id: c.id, loadNumber: c.loadNumber,
                               etaSeconds: times[idx], meters: idx < dists.count ? dists[idx] : 0))
        }
        ranked = rows.sorted { $0.etaSeconds < $1.etaSeconds }
    }
}

/// Unassigned loads ranked by truck-aware drive time from the dispatcher's
/// position (HERE Matrix Routing v8). Honest — hides cleanly when location is
/// denied, no candidates carry coords, or the Matrix call fails.
struct DispatchMatrixCandidatesStrip: View {
    let candidates: [DispatchMatrixCandidate]
    @Environment(\.palette) private var palette
    @StateObject private var store = DispatchMatrixStore()

    var body: some View {
        Group {
            if store.ranked.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    header
                    VStack(spacing: 6) {
                        ForEach(Array(store.ranked.prefix(4).enumerated()), id: \.element.id) { idx, r in
                            candidateRow(rank: idx + 1, r: r)
                        }
                    }
                }
            }
        }
        .task(id: candidates.map(\.id)) { await store.refresh(candidates: candidates) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.cross.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("CLOSEST TO COVER · MATRIX")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("EUSOTRIP · \(store.ranked.count)")
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func candidateRow(rank: Int, r: DispatchMatrixStore.Ranked) -> some View {
        HStack(spacing: 8) {
            Text("#\(rank)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 22, alignment: .leading)
            Text(r.loadNumber)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(milesLabel(r.meters))
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            Text(etaLabel(r.etaSeconds))
                .font(EType.bodyStrong)
                .foregroundStyle(rank == 1 ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.textPrimary))
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func milesLabel(_ meters: Int) -> String {
        let mi = Double(meters) / 1609.344
        return mi < 10 ? String(format: "%.1f mi", mi) : String(format: "%.0f mi", mi)
    }
    private func etaLabel(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        return mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h \(mins % 60)m"
    }
}
