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
    let id: String
    let userId: Int?
    let status: String?
    let hazmatEndorsement: Bool?
    let licenseNumber: String?
    let licenseState: String?
    let name: String?
    let phone: String?
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
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
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
    @State private var hosEvidence: [HOSFleetDriver] = []
    @State private var selectedDriverId: String?
    @State private var inFlight = false
    @State private var ack: String?
    @State private var err: String?
    /// True while a driver row is hovering over the citation pill
    /// drop zone. Drives the gradient stroke + label flip so the
    /// dispatcher sees the impending commit target before release.
    @State private var dropHover: Bool = false
    /// Sticky reference to the driver currently being dragged.
    @State private var draggingDriverId: String? = nil

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city else { return nil }
        return "\(p) → \(d)"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "-"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
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
        .eusoRefreshable {
            await loadCtx()
            await loadDrivers()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12)
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
                    Text("AWARDED · COMMIT · assign driver")
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
                    Text("Release to commit \(d.name ?? "driver #\(d.id)") to \(loadNumberDisplay)")
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
            guard let driverId = droppedIds.first,
                  let driver = drivers.first(where: { $0.id == driverId }),
                  isHOSEligible(driver) else { return false }
            Task { await assign(driverIdOverride: driverId) }
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
            ("STATE",      load?.status ?? "-", .orange),
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
            Text("HOS-ELIGIBLE DRIVERS · \(drivers.filter(isHOSEligible).count) OF \(drivers.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 2)
            if drivers.isEmpty {
                LifecycleCard {
                    Text("No drivers available, pull to refresh.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(drivers) { d in
                        // NOT a Button: on iOS the Button's tap recognizer wins the
                        // gesture race and `.draggable` never starts a drag. Plain
                        // view + .onTapGesture keeps the tap and lets the drag own
                        // the long-press.
                        if isHOSEligible(d) {
                            driverRow(d, selected: d.id == selectedDriverId)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedDriverId = d.id }
                                .draggable(String(d.id)) {
                                    driverRow(d, selected: false)
                                        .frame(maxWidth: 320)
                                        .opacity(0.92)
                                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                                        .onAppear { draggingDriverId = d.id }
                                }
                        } else {
                            driverRow(d, selected: false)
                                .opacity(0.62)
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
                Text(d.name ?? "Driver #\(d.id)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                let lic = [d.licenseNumber, d.licenseState].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                let status = d.status ?? "-"
                let suffix = (d.hazmatEndorsement ?? false) ? " · HAZMAT" : ""
                Text("\(status)\(lic.isEmpty ? "" : " · " + lic)\(suffix)")
                    .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                Text(hosEvidenceLine(d))
                    .font(.caption2)
                    .foregroundStyle(isHOSEligible(d) ? Brand.blue : Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text(d.name ?? "Driver #\(d.id)")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                if let phone = d.phone, !phone.isEmpty {
                    Text(phone)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
                Text("Compliance gates fire on commit: active authority · FMCSA OOS · insurance min · CDL expiry.")
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
        .disabled(selectedDriver.map { isHOSEligible($0) } != true || inFlight)
    }

    // MARK: data

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch {
            await MainActor.run {
                err = assignFailureCopy_532(error, noun: "load details")
            }
        }
    }

    private func loadDrivers() async {
        struct In: Encodable {
            let loadId: String?
            let hazmatRequired: Bool?
            let equipmentType: String?
        }
        do {
            let driverRows: [ADDriver] = try await EusoTripAPI.shared.query(
                "dispatch.getAvailableDrivers",
                input: In(loadId: loadId,
                          hazmatRequired: nil,
                          equipmentType: load?.equipmentType)
            )
            let evidenceRows: [HOSFleetDriver] = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            drivers = driverRows
            hosEvidence = evidenceRows
            if let selectedDriver, !isHOSEligible(selectedDriver) { selectedDriverId = nil }
        } catch {
            await MainActor.run {
                err = assignFailureCopy_532(error, noun: "available drivers")
                drivers = []
                hosEvidence = []
                selectedDriverId = nil
            }
        }
    }

    /// Two entry points — bottom CTA uses selectedDriverId, drag-to-pill
    /// uses driverIdOverride. Same wire + same commit semantics either way.
    private func assign(driverIdOverride: String? = nil) async {
        guard let driverId = driverIdOverride ?? selectedDriverId else { return }
        await MainActor.run { inFlight = true; ack = nil; err = nil }
        struct Assignment: Encodable { let loadId: Int; let driverId: Int }
        struct In: Encodable { let assignments: [Assignment] }
        struct Result: Decodable { let loadId: Int; let success: Bool; let error: String? }
        struct Out: Decodable { let assigned: Int; let failed: Int; let results: [Result] }
        do {
            let refreshedEvidence: [HOSFleetDriver] = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            await MainActor.run { hosEvidence = refreshedEvidence }
            guard let driver = drivers.first(where: { $0.id == driverId }),
                  isHOSEligible(driver),
                  let numericLoadId = Int(loadId),
                  let numericDriverId = Int(driverId) else {
                throw AssignmentEvidenceError_532.unavailable
            }
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.smartBulkAssign",
                input: In(assignments: [Assignment(loadId: numericLoadId, driverId: numericDriverId)])
            )
            if resp.assigned == 1,
               resp.failed == 0,
               resp.results.count == 1,
               let result = resp.results.first,
               result.loadId == numericLoadId,
               result.success {
                let name = drivers.first(where: { $0.id == driverId })?.name ?? "the selected driver"
                await MainActor.run {
                    ack = "Assigned · \(name) is on this load · compliance gates passed · dispatch, driver and shipper all notified."
                    draggingDriverId = nil
                    dropHover = false
                }
                await loadCtx()
            } else {
                await MainActor.run {
                    let reason = resp.results.first?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
                    err = reason?.isEmpty == false
                        ? reason
                        : "The server held this assignment after evidence revalidation."
                    draggingDriverId = nil
                    dropHover = false
                }
            }
        } catch let e {
            await MainActor.run {
                err = assignFailureCopy_532(e, noun: "driver assignment")
                draggingDriverId = nil
                dropHover = false
            }
        }
        await MainActor.run { inFlight = false }
    }

    private func evidence(for driver: ADDriver) -> HOSFleetDriver? {
        hosEvidence.first { evidence in
            evidence.driverId == driver.id || driver.userId.map { String($0) } == evidence.driverId
        }
    }

    private func isHOSEligible(_ driver: ADDriver) -> Bool {
        evidence(for: driver)?.assignmentEligibility() == .eligible
    }

    private func hosEvidenceLine(_ driver: ADDriver) -> String {
        guard let evidence = evidence(for: driver) else { return "HOS observation unavailable · assignment held" }
        if evidence.assignmentEligibility() == .eligible {
            let source = evidence.source?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceLabel = source.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "HOS"
            return "\(sourceLabel) · current ≤15m"
        }
        return evidence.assignmentEligibility().reason ?? "HOS evidence unavailable"
    }
}

private enum AssignmentEvidenceError_532: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "Current, complete HOS evidence is unavailable. Refresh before assigning this load."
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

// MARK: - Operator-facing failure copy

/// Operator-language reason a dispatch assignment step failed.
///
/// The caught error is still available for logging; the dispatcher sees a
/// sentence they can act on rather than a raw `NSError` description.
/// `noun` names what failed ("driver assignment", "available drivers") so
/// the line stays specific.
fileprivate func assignFailureCopy_532(_ error: Error, noun: String) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired. Sign in again before you assign this load."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account isn't cleared to assign drivers on this load."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The \(noun) was rejected. Refresh this load and try again."
                : trimmed
        case .httpStatus(let code, _):
            return "The \(noun) didn't go through (code \(code)). Refresh before you tell the driver."
        case .decodingFailed:
            return "The \(noun) came back in a form this build can't read. Update the app, then retry."
        case .empty:
            return "Nothing came back for the \(noun). Refresh this load and try again."
        case .notConfigured, .badURL:
            return "This device isn't set up for live dispatch yet. Restart the app and try again."
        case .queuedForOfflineReplay:
            return "You're offline — the \(noun) is queued and sends when you reconnect. Don't tell the driver until it confirms."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection right now. The \(noun) didn't complete — retry once you have signal."
    }
    return "The \(noun) didn't complete. Refresh this load and try again."
}
