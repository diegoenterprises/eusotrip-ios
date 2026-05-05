//
//  073_MeVehicle.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · assigned vehicle)
//
//  Screen 073 · Me · Vehicle — the driver's currently assigned truck,
//  with identifying numerics (VIN, plate, unit, year/make/model), live
//  status chip, and a recent maintenance-events list scoped to that
//  vehicle's work orders. No assignment? The view surfaces a
//  first-class "not assigned" hero card rather than a blank screen.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Vehicle identity comes from `vehicle.getAssigned` — MCP-verified
//      at `frontend/server/routers/vehicle.ts:125`. The server scopes
//      the query to the signed-in driver's `users.id` → `drivers.id`
//      lookup, so no explicit driver-id parameter is needed.
//      Un-assigned state surfaces as an empty-string `id` — the view
//      detects that and renders the "not assigned" branch.
//
//    • Maintenance history comes from `vehicle.getMaintenanceHistory`
//      (same router, line 144). The backend derives records from
//      `documents` rows whose `type` contains "maintenance", so
//      statuses track the document lifecycle (uploaded / approved /
//      archived). `vehicleId` is seeded after the assignment lands so
//      the list is scoped to the driver's truck.
//
//    • Odometer + fuel level are deliberately NOT rendered — the
//      backend hardcodes them to 0 today because the telematics
//      integration (OBD-II / ELD mileage feed) hasn't shipped. We
//      disclose this in the footer rather than surfacing "0 mi" /
//      "0% fuel" cells that would look like stale stub data.
//
//    • Empty history is server-confirmed. A truck with no maintenance
//      documents on record yields `records: []` and the section folds
//      to a subtle "No maintenance events on record yet" placeholder.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero make/model, stat-tile
//         numerics, and "In Service" status chip. Brand.warning on
//         out-of-service / maintenance statuses. Zero Brand.info/blue
//         flat fills.
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

struct MeVehicle: View {
    @Environment(\.palette) var palette
    @StateObject private var assigned = AssignedVehicleStore()
    @StateObject private var maintenance = VehicleMaintenanceHistoryStore()
    /// AI scan state — calls `equipmentIntelligence.scanVehicleIntelligence`
    /// with the assigned vehicle id and surfaces Gemini's analysis.
    @State private var aiScanInflight: Bool = false
    @State private var aiScanResult: VehicleScanResult? = nil
    @State private var aiScanError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch assigned.state {
                case .loading:
                    heroSkeleton
                case .empty:
                    unassignedHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let v):
                    if v.isUnassigned {
                        unassignedHero
                    } else {
                        heroCard(v)
                        identityStrip(v)
                        aiScanRibbon(v)
                        if let s = aiScanResult { aiScanResultCard(s) }
                        maintenanceSection
                    }
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .overlay(alignment: .top) {
            if let err = aiScanError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            await MainActor.run { aiScanError = nil }
                        }
                    }
            }
        }
    }

    private func aiScanRibbon(_ v: VehicleAPI.AssignedVehicle) -> some View {
        Button {
            Task { await runAIScan(v) }
        } label: {
            HStack(spacing: 10) {
                if aiScanInflight {
                    ProgressView().progressViewStyle(.circular)
                        .tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(aiScanInflight ? "Scanning…" : "AI scan with ESANG")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(aiScanInflight)
    }

    private func aiScanResultCard(_ s: VehicleScanResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESANG VEHICLE INTELLIGENCE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            if let summary = s.summary, !summary.isEmpty {
                Text(summary)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let recs = s.recommendations, !recs.isEmpty {
                Text("Recommendations").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(palette.textSecondary)
                        Text(r).font(EType.caption).foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let risks = s.risks, !risks.isEmpty {
                Text("Risk flags").font(EType.micro).tracking(0.6).foregroundStyle(Brand.warning)
                ForEach(Array(risks.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(r).font(EType.caption).foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    private func runAIScan(_ v: VehicleAPI.AssignedVehicle) async {
        guard !aiScanInflight else { return }
        aiScanInflight = true
        defer { Task { @MainActor in aiScanInflight = false } }
        struct In: Encodable { let vehicleId: Int }
        struct Out: Decodable {
            let summary: String?
            let recommendations: [String]?
            let risks: [String]?
            let aiAnalysis: String?
        }
        do {
            let id = Int(v.id) ?? 0
            guard id > 0 else { return }
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "equipmentIntelligence.scanVehicleIntelligence",
                input: In(vehicleId: id)
            )
            await MainActor.run {
                aiScanResult = VehicleScanResult(
                    summary: resp.summary ?? resp.aiAnalysis,
                    recommendations: resp.recommendations,
                    risks: resp.risks
                )
            }
        } catch {
            await MainActor.run {
                aiScanError = "Scan failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    private func reload() async {
        await assigned.refresh()
        // Only fetch maintenance once we know which vehicle to scope
        // to. When unassigned the list would return company-wide rows
        // (dispatch view) which isn't what the Me · Vehicle surface is
        // for — skip the call entirely in that case.
        if let v = assigned.state.value, !v.isUnassigned {
            maintenance.vehicleId = v.id
            await maintenance.refresh()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Vehicle")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Assigned truck · status · service history")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: (assigned.isLoading || maintenance.isLoading) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Hero — assigned

    private func heroCard(_ v: VehicleAPI.AssignedVehicle) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(modelHeadline(v))
                        .font(EType.h2)
                        .foregroundStyle(LinearGradient.diagonal)
                    if v.year > 0 {
                        Text("\(String(v.year))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                statusChip(v.status)
            }

            if !v.unitNumber.isEmpty {
                HStack(spacing: Space.s2) {
                    Image(systemName: "truck.box")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("Unit \(v.unitNumber)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private var unassignedHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "truck.box.badge.clock")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Text("No vehicle assigned")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Your dispatcher will assign you a truck before your next run. Check back or pull to refresh.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var heroSkeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.5))
                .frame(height: 120)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .frame(height: 80)
        }
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load vehicle")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await reload() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Identity strip — VIN / plate

    @ViewBuilder
    private func identityStrip(_ v: VehicleAPI.AssignedVehicle) -> some View {
        let hasVin = !v.vin.isEmpty
        let hasPlate = !v.licensePlate.isEmpty
        if hasVin || hasPlate {
            HStack(spacing: Space.s3) {
                if hasVin {
                    identityTile(label: "VIN", value: v.vin)
                }
                if hasPlate {
                    identityTile(label: "PLATE", value: v.licensePlate)
                }
            }
        }
    }

    private func identityTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Status chip

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let normalized = status.lowercased()
        let label = statusLabel(normalized)
        switch normalized {
        case "available", "in_use", "active":
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "maintenance", "out_of_service":
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1)
                )
        default:
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(
                    Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        }
    }

    private func statusLabel(_ normalized: String) -> String {
        switch normalized {
        case "available":        return "Available"
        case "in_use", "active": return "In Service"
        case "maintenance":      return "In Maintenance"
        case "out_of_service":   return "Out of Service"
        case "":                 return "Unknown"
        default:                 return normalized.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: Maintenance section

    @ViewBuilder
    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SERVICE HISTORY")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if case .loaded(let rows) = maintenance.state {
                    Text("\(rows.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            switch maintenance.state {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: 64)
            case .empty:
                maintenanceEmpty
            case .error(let e):
                Text(e.localizedDescription)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(palette.bgCard.opacity(0.6))
                    )
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        maintenanceRow(row)
                    }
                }
            }
        }
    }

    private var maintenanceEmpty: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No maintenance events on record yet.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    private func maintenanceRow(_ r: VehicleAPI.MaintenanceRecord) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.description)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(prettyDate(r.date))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            maintenanceStatusChip(r.status)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func maintenanceStatusChip(_ status: String) -> some View {
        let label = status.replacingOccurrences(of: "_", with: " ").uppercased()
        switch status.lowercased() {
        case "completed", "approved":
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "failed", "rejected":
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

    // MARK: Disclosure footer
    //
    // Honest note on the telematics gap — odometer + fuel level land
    // when the ELD integration ships. Better than a hardcoded "0 mi".

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Live odometer & fuel")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Real-time odometer and fuel-level readings land once the ELD / telematics integration ships. Until then, this screen shows the vehicle identifiers dispatch assigned — no stub numbers.")
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

    /// Compose the `{make} {model}` headline, falling back to the bare
    /// unit number when the server didn't populate model fields. Never
    /// invents a label — returns "Vehicle" only when every string is
    /// empty, which the unassigned hero already filters out upstream.
    private func modelHeadline(_ v: VehicleAPI.AssignedVehicle) -> String {
        let composed = "\(v.make) \(v.model)".trimmingCharacters(in: .whitespaces)
        if !composed.isEmpty { return composed }
        if !v.unitNumber.isEmpty { return "Unit \(v.unitNumber)" }
        return "Vehicle"
    }

    /// Parse "YYYY-MM-DD" → "Mon D, YYYY". Falls back to the raw server
    /// string on parse failure so we never drop data.
    private func prettyDate(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: raw) else { return raw }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "MMM d, yyyy"
        return outFmt.string(from: d)
    }
}

// MARK: - Screen wrapper

struct MeVehicleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeVehicle()
        } nav: {
            BottomNav(
                leading: driverNavLeading_073(),
                trailing: driverNavTrailing_073(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_073() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_073() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews never run `.task` — stores land in `.error` via
// `notConfigured` under the preview's no-baseURL runtime. No fixtures.

#Preview("073 · Me Vehicle · Night") {
    MeVehicleScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("073 · Me Vehicle · Afternoon") {
    MeVehicleScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

/// AI scan result envelope from `equipmentIntelligence.scanVehicleIntelligence`.
private struct VehicleScanResult: Hashable {
    let summary: String?
    let recommendations: [String]?
    let risks: [String]?
}
