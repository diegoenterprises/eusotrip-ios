//
//  FleetBulkRegisterStep.swift
//  EusoTrip — onboarding step: bulk fleet register.
//
//  Shown after a CATALYST / RAIL_CATALYST / VESSEL_OPERATOR finishes
//  the company-info form. Lets the carrier add their fleet by VIN
//  scan (preferred — confirms make/model/year live via NHTSA) or
//  manual entry, then commits the batch via
//  `fleetRegistration.registerVehicleFleet` which seeds Zeun
//  maintenance schedules + DVIR baselines.
//
//  This is the operational difference between "you can use EusoTrip
//  now" and "your fleet is ready to dispatch."
//

import SwiftUI

/// One row in the local pending-fleet list. We hold these client-
/// side until the user taps Commit so the wizard supports add /
/// remove / edit per row before the batch fires.
struct PendingFleetVehicle: Identifiable, Hashable {
    let id: UUID = UUID()
    var vin: String
    var make: String?
    var model: String?
    var year: Int?
    var vehicleType: String        // one of vehicles.vehicleType enum
    var gvwrClass: String?
    var licensePlate: String = ""
    var unitNumber: String = ""
    var mileage: Int? = nil
}

struct FleetBulkRegisterStep: View {
    let vertical: String          // "truck" | "rail" | "vessel"
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    @Environment(\.palette) private var palette

    @State private var pending: [PendingFleetVehicle] = []
    @State private var showVinScanner: Bool = false
    @State private var inflight: Bool = false
    @State private var result: ResultSummary? = nil
    @State private var errorBanner: String? = nil

    init(
        vertical: String = "truck",
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.vertical = vertical
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                tipCard
                addRow
                if !pending.isEmpty {
                    pendingList
                }
                if let r = result { resultCard(r) }
                if let e = errorBanner {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }
                actionRail
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(palette.bgPage)
        .sheet(isPresented: $showVinScanner) {
            VINScannerSheet { r in
                appendFromScan(r)
            }
        }
    }

    // MARK: — Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FLEET REGISTRATION").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(headerTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(headerSubtitle)
                .font(EType.body).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerTitle: String {
        switch vertical {
        case "rail": return "Register your rolling stock"
        case "vessel": return "Register your vessels"
        default: return "Register your fleet"
        }
    }
    private var headerSubtitle: String {
        switch vertical {
        case "rail":
            return "Add each locomotive, intermodal chassis, or rail car by VIN. We auto-fill make/model/year via NHTSA and create AAR-compliant maintenance schedules + DVIR baselines."
        case "vessel":
            return "Add support vehicles and shore equipment by VIN. USCG-documented vessels are registered separately via the USCG vessel document scanner."
        default:
            return "Scan each truck's VIN or type it in. We auto-fill make/model/year via NHTSA, seed Zeun maintenance schedules, and queue a DVIR baseline so your drivers are ready on day one."
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 4) {
                Text("WHY THIS MATTERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Text("Each vehicle gets 8 Zeun maintenance schedule rows (oil, brakes, tires, transmission, DOT annual, coolant, fuel filter, air filter). DOT annual is flagged CRITICAL so it surfaces in the carrier safety dashboard immediately.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Button {
                showVinScanner = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 14, weight: .heavy))
                    Text("Scan VIN").font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                let blank = PendingFleetVehicle(
                    vin: "",
                    vehicleType: vertical == "rail" ? "intermodal_chassis"
                              : vertical == "vessel" ? "specialized"
                              : "tractor"
                )
                pending.append(blank)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Add manually").font(.system(size: 13, weight: .heavy))
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCardSoft)
                .overlay(Capsule().strokeBorder(palette.borderSoft))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var pendingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("PENDING · \(pending.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if pending.count > 0 {
                    Button { pending.removeAll() } label: {
                        Text("Clear all")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach($pending) { $row in
                pendingRow($row)
            }
        }
    }

    private func pendingRow(_ row: Binding<PendingFleetVehicle>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: iconForType(row.wrappedValue.vehicleType))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                if row.wrappedValue.vin.isEmpty {
                    Text("New vehicle").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                } else {
                    Text(row.wrappedValue.vin)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Button {
                    pending.removeAll(where: { $0.id == row.wrappedValue.id })
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            if row.wrappedValue.vin.isEmpty {
                TextField("17-character VIN", text: row.vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .font(.system(size: 13, design: .monospaced))
            } else {
                HStack(spacing: 6) {
                    if let y = row.wrappedValue.year { Text(verbatim: "\(y)").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let m = row.wrappedValue.make { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let m = row.wrappedValue.model { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let g = row.wrappedValue.gvwrClass {
                        Text(g)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .overlay(Capsule().strokeBorder(palette.borderSoft))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(humanType(row.wrappedValue.vehicleType))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.diagonal.opacity(0.2)))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            HStack(spacing: 8) {
                TextField("Unit #", text: row.unitNumber)
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .font(EType.caption)
                TextField("Plate", text: row.licensePlate)
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .font(EType.caption)
            }
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func resultCard(_ r: ResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("FLEET COMMITTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.success)
            }
            Text("\(r.accepted) added · \(r.zeunSchedules) Zeun rows · \(r.dvirBaselines) DVIR baselines pending")
                .font(EType.body).foregroundStyle(palette.textPrimary)
            if r.rejected.count > 0 {
                Text("\(r.rejected.count) rejected:")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                ForEach(r.rejected, id: \.vin) { rej in
                    Text("• \(rej.vin) — \(rej.reason)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.success.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionRail: some View {
        VStack(spacing: 8) {
            Button {
                Task { await commit() }
            } label: {
                HStack(spacing: 8) {
                    if inflight {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    Text(commitButtonTitle)
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(canCommit ? AnyView(LinearGradient.diagonal) : AnyView(Color.gray.opacity(0.4)))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            .opacity(canCommit ? 1.0 : 0.55)

            HStack(spacing: 8) {
                if let onSkip {
                    Button { onSkip() } label: {
                        Text("Skip for now")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(palette.textPrimary)
                            .background(palette.bgCardSoft)
                            .overlay(Capsule().strokeBorder(palette.borderSoft))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if result != nil {
                    Button { onContinue() } label: {
                        Text("Continue")
                            .font(.system(size: 13, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(LinearGradient.diagonal)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var canCommit: Bool {
        !inflight && pending.contains(where: { isLikelyVIN($0.vin) })
    }

    private var commitButtonTitle: String {
        let ready = pending.filter { isLikelyVIN($0.vin) }.count
        if inflight { return "Committing…" }
        if ready == 0 { return "Add at least one VIN" }
        return "Register \(ready) \(ready == 1 ? "vehicle" : "vehicles")"
    }

    // MARK: — Behavior

    private func appendFromScan(_ r: VINScanResult) {
        // Refuse duplicates against the local pending list — server
        // will reject them too with a friendlier message, but this
        // saves the round-trip.
        if pending.contains(where: { $0.vin == r.vin }) {
            errorBanner = "\(r.vin) is already in your pending list."
            return
        }
        errorBanner = nil
        pending.append(PendingFleetVehicle(
            vin: r.vin,
            make: r.decoded?.make,
            model: r.decoded?.model,
            year: r.decoded?.year,
            vehicleType: r.suggestedVehicleType ?? "tractor",
            gvwrClass: r.decoded?.gvwrClass
        ))
    }

    @MainActor
    private func commit() async {
        let valid = pending.filter { isLikelyVIN($0.vin) }
        guard !valid.isEmpty else { return }
        inflight = true
        defer { inflight = false }
        errorBanner = nil

        let inputs = valid.map { p in
            FleetRegistrationAPI.VehicleInput(
                vin: p.vin,
                unitNumber: p.unitNumber.isEmpty ? nil : p.unitNumber,
                licensePlate: p.licensePlate.isEmpty ? nil : p.licensePlate,
                mileage: p.mileage,
                vehicleType: p.vehicleType,
                make: p.make,
                model: p.model,
                year: p.year,
                capacity: nil,
                assignedDriverEmail: nil
            )
        }
        do {
            let resp = try await EusoTripAPI.shared.fleetRegistration.registerVehicleFleet(
                inputs,
                seedDvirBaseline: true,
                seedZeunSchedule: true
            )
            result = ResultSummary(
                accepted: resp.summary.accepted,
                rejected: resp.rejected,
                zeunSchedules: resp.summary.zeunSchedulesSeeded,
                dvirBaselines: resp.summary.dvirBaselinesSeeded
            )
            // Drop the accepted entries from pending; leave rejected
            // entries so the user can fix and resubmit.
            let acceptedVins = Set(resp.accepted.map { $0.vin })
            pending.removeAll { acceptedVins.contains($0.vin) }
        } catch let e {
            errorBanner = "Bulk register failed: \((e as? EusoTripAPIError)?.errorDescription ?? e.localizedDescription)"
        }
    }

    private func isLikelyVIN(_ s: String) -> Bool {
        let v = s.uppercased().filter { $0.isLetter || $0.isNumber }
        return v.count == 17 && !v.contains("I") && !v.contains("O") && !v.contains("Q")
    }

    private func iconForType(_ t: String) -> String {
        switch t {
        case "tractor", "box_truck": return "truck.box.fill"
        case "trailer", "dry_van", "reefer", "refrigerated": return "shippingbox.fill"
        case "tanker", "chemical_tanker": return "drop.fill"
        case "flatbed", "step_deck", "lowboy": return "rectangle.split.3x1"
        case "intermodal_chassis", "container_chassis": return "cube.box.fill"
        default: return "car.fill"
        }
    }
    private func humanType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private struct ResultSummary: Equatable {
        let accepted: Int
        let rejected: [FleetRegistrationAPI.RejectedVehicle]
        let zeunSchedules: Int
        let dvirBaselines: Int
    }
}

// MARK: - Previews

#Preview("Fleet Step · Truck · Dark") {
    FleetBulkRegisterStep(vertical: "truck", onContinue: {}, onSkip: {})
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Fleet Step · Rail · Light") {
    FleetBulkRegisterStep(vertical: "rail", onContinue: {}, onSkip: {})
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
