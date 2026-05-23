//
//  532_DispatcherAssignDriverM05.swift
//  EusoTrip — Dispatcher · Assign driver to an awarded load (§418).
//
//  Wireframe slot: 04 Dispatcher / 532 Dispatcher Assign Driver M05.
//  Opens the M-05 dispatcher consumer surface immediately after the
//  shipper-vantage AWARD-COMMIT (§415 · shippers.acceptBid). The
//  dispatcher picks a driver from the carrier's fleet roster and
//  fires `dispatch.assignDriver` (dispatch.ts:1033) — the
//  compliance-gated commit verb that:
//    · requireAccess(DISPATCH, UPDATE, LOAD)
//    · company.isActive + FMCSA getOOSStatus
//    · hazmat insurance minimum (when hazmat)
//    · CDL document-expiration gate
//
//  On success the load row flips to "assigned" and loadLifecycle
//  fans the AWARDED·driver-assigned envelope out to the driver
//  vantage (§419 consumer). No mock data — driver list comes from
//  `dispatch.getAvailableDrivers`, recommendations from
//  `dispatch.getRecommendations`.
//
//  Reshaped 2026-05-23 with drag-to-assign — the AWARDED citation
//  pill at the top doubles as a .dropDestination labeled with the
//  load context. Drag a driver row from the available list up onto
//  it to fire dispatch.assignDriver in one gesture. Same DnD shape
//  as 310_CarrierAssignDriver (per-load context, many candidates).
//  Tap-to-select + bottom Assign button preserved as fallback.
//

import SwiftUI

// MARK: - tRPC decode shapes

private struct ADLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let distance: Double?
    let rate: String?
    let cargoType: String?
    let equipmentType: String?
    let pickupLocation: ADCityState?
    let deliveryLocation: ADCityState?
    struct ADCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

private struct ADDriver: Decodable, Hashable, Identifiable {
    let id: Int
    let userId: Int?
    let status: String?
    let hazmatEndorsement: Bool?
    let licenseNumber: String?
    let licenseState: String?
    let userName: String?
    let phone: String?
    let email: String?
}

// MARK: - Screen

struct DispatcherM05AssignDriverScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            ADBody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct ADBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: ADLoadCtx?
    @State private var drivers: [ADDriver] = []
    @State private var selectedDriverId: Int?
    @State private var inFlight = false
    @State private var ack: String?
    @State private var err: String?
    /// True while a driver row is hovering over the citation pill
    /// drop zone. Drives the gradient stroke + label flip so the
    /// dispatcher sees the impending commit target before release.
    @State private var dropHover: Bool = false
    /// Sticky reference to the driver currently being dragged.
    @State private var draggingDriverId: Int? = nil

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city else { return nil }
        return "\(p) → \(d)"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "—"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var selectedDriver: ADDriver? {
        drivers.first { $0.id == selectedDriverId }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                loadFactsRow
                driverListSection
                if let d = selectedDriver { selectedDriverCard(d) }
                if let ack = ack {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = err {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                assignButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await loadCtx()
            await loadDrivers()
        }
        .refreshable {
            await loadCtx()
            await loadDrivers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BOARD · AWARDED · ASSIGN DRIVER · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Assign driver")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Pick a driver from your fleet. Compliance gates run on commit.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        let hoveringDriver = draggingDriverId.flatMap { id in drivers.first(where: { $0.id == id }) }
        return LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AWARDED · COMMIT VERB · dispatch.assignDriver")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if inFlight {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: dropHover ? "checkmark.circle.fill" : "arrow.up.circle")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                    }
                }
                Text("\(loadNumberDisplay) · \(equipmentDisplay) · \(rateDisplay)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text("\(lane) · \(distanceDisplay)")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
                if dropHover, let d = hoveringDriver {
                    Text("Release to commit \(d.userName ?? "driver #\(d.id)") to \(loadNumberDisplay)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.top, 4)
                } else {
                    Text("Drag a driver row up here to assign + run compliance gates.")
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 4)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: dropHover ? 2 : 0
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let raw = droppedIds.first, let driverIdInt = Int(raw) else { return false }
            guard drivers.contains(where: { $0.id == driverIdInt }) else { return false }
            Task { await assign(driverIdOverride: driverIdInt) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
        }
    }

    private var loadFactsRow: some View {
        let facts: [(String, String, Color)] = [
            ("RATE",       rateDisplay,         .green),
            ("DISTANCE",   distanceDisplay,     .blue),
            ("EQUIPMENT",  equipmentDisplay,    .blue),
            ("STATE",      load?.status ?? "—", .orange),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.0)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(f.1)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(f.2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(f.2.opacity(0.3)))
            }
        }
    }

    private var driverListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVAILABLE DRIVERS · \(drivers.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 2)
            if drivers.isEmpty {
                LifecycleCard {
                    Text("No drivers available — pull to refresh.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(drivers) { d in
                        Button { selectedDriverId = d.id } label: {
                            driverRow(d, selected: d.id == selectedDriverId)
                        }
                        .buttonStyle(.plain)
                        .draggable(String(d.id)) {
                            driverRow(d, selected: false)
                                .frame(maxWidth: 320)
                                .opacity(0.92)
                                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                        }
                        .onDrag {
                            draggingDriverId = d.id
                            return NSItemProvider(object: String(d.id) as NSString)
                        }
                    }
                }
            }
        }
    }

    private func driverRow(_ d: ADDriver, selected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selected ? LinearGradient.diagonal : LinearGradient(colors: [palette.bgCard, palette.bgCard], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(LinearGradient.diagonal.opacity(selected ? 0 : 0.4), lineWidth: 1))
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(selected ? Color.white : palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.userName ?? "Driver #\(d.id)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                let lic = [d.licenseNumber, d.licenseState].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                let status = d.status ?? "—"
                let suffix = (d.hazmatEndorsement ?? false) ? " · HAZMAT" : ""
                Text("\(status)\(lic.isEmpty ? "" : " · " + lic)\(suffix)")
                    .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(selected ? Color.clear : palette.textTertiary.opacity(0.15), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(selected ? 0.55 : 0), lineWidth: 1.5)
        )
    }

    private func selectedDriverCard(_ d: ADDriver) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SELECTED · COMMIT TARGET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(d.userName ?? "Driver #\(d.id)")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                if let phone = d.phone, !phone.isEmpty {
                    Text(phone)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
                if let email = d.email, !email.isEmpty {
                    Text(email)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
                Text("Compliance gates fire on commit: company.isActive · FMCSA OOS · insurance min · CDL expiry.")
                    .font(.caption2).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var assignButton: some View {
        Button {
            Task { await assign() }
        } label: {
            HStack(spacing: 8) {
                if inFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text(inFlight ? "Assigning…" : "Assign driver")
                    .font(EType.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(
                selectedDriverId == nil
                    ? LinearGradient(colors: [palette.textTertiary, palette.textTertiary], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient.diagonal
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedDriverId == nil || inFlight)
    }

    // MARK: data

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated; UI shows "—" */ }
    }

    private func loadDrivers() async {
        struct In: Encodable {
            let loadId: String?
            let hazmatRequired: Bool?
            let equipmentType: String?
        }
        do {
            drivers = try await EusoTripAPI.shared.query(
                "dispatch.getAvailableDrivers",
                input: In(loadId: loadId,
                          hazmatRequired: nil,
                          equipmentType: load?.equipmentType)
            )
        } catch { /* tolerated; UI shows empty */ }
    }

    /// Two entry points — bottom CTA uses selectedDriverId, drag-to-pill
    /// uses driverIdOverride. Same wire + same commit semantics either way.
    private func assign(driverIdOverride: Int? = nil) async {
        guard let driverId = driverIdOverride ?? selectedDriverId else { return }
        await MainActor.run { inFlight = true; ack = nil; err = nil }
        struct In: Encodable {
            let loadId: String
            let driverId: String
        }
        struct Out: Decodable {
            let success: Bool?
            let loadId: String?
            let driverId: String?
            let message: String?
        }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.assignDriver",
                input: In(loadId: loadId, driverId: String(driverId))
            )
            if resp.success != false {
                let name = drivers.first(where: { $0.id == driverId })?.userName ?? "driver #\(driverId)"
                await MainActor.run {
                    ack = "Assigned · \(name) committed · compliance gates passed · loadLifecycle fan-out fired."
                    draggingDriverId = nil
                }
                await loadCtx()
            } else {
                await MainActor.run { err = resp.message ?? "Assignment returned no success flag." }
            }
        } catch let e {
            await MainActor.run { err = (e as? LocalizedError)?.errorDescription ?? "Assign failed: \(e)" }
        }
        await MainActor.run { inFlight = false }
    }
}

// MARK: - Previews

#Preview("532 Assign Driver · Light") {
    DispatcherM05AssignDriverScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("532 Assign Driver · Dark") {
    DispatcherM05AssignDriverScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
