//
//  059_VehicleAndEquipment.swift
//  EusoTrip 2027 UI — Driver · Vehicle & Equipment (DOT-406 tanker profile)
//
//  Screen 059 · Driver · Vehicle & Equipment — the driver's assigned rig
//  PLUS its DOT-406 petroleum-tanker equipment profile: power-unit
//  identity, the tanker's spec/placard/compartment detail, GVWR / fuel /
//  MPG stat tiles, last-DVIR status, a pre-trip checklist, maintenance
//  countdowns (oil change · DOT annual · tire rotate), and a one-tap
//  "Book oil" ESang service CTA.
//
//  This is DISTINCT from 073 (the generic assigned-vehicle screen). 059
//  is the tanker-equipment detail: compartments (TC-406 / CMPT 1-4 with
//  DIESEL ULSD net gallons), DOT-406 ALUMINUM spec, COMBUSTIBLE / NA1993
//  placards, CIVACON ground status, and DOT-annual countdown.
//
//  ──────────────────────────────────────────────────────────────────
//  OATH DATA DISCIPLINE — live-or-honest-empty, never fabricated:
//
//    REAL (wired to `vehicle.getAssigned`, EusoTripAPI.swift:7481 via
//    `AssignedVehicleStore`, same source as 073):
//      • Rig / unit number, make, model, year, VIN, license plate, status
//      • Odometer / fuel level — rendered ONLY when non-zero (the backend
//        hardcodes them to 0 until telematics ships; we never show "0 mi")
//
//    REAL (wired to `vehicle.getMaintenanceHistory`,
//    EusoTripAPI.swift:7489 via `VehicleMaintenanceHistoryStore`):
//      • Recent service / DVIR-derived events for the assigned unit.
//
//    HONEST-EMPTY (NO field on the backend `AssignedVehicle` model — the
//    SVG's literal numbers are DESIGN MOCKS, so we render "—" / "No spec
//    on file" rather than inventing "9,500 GAL" / "80,000 LB" / "30 D"):
//      • Tanker spec (DOT-406 ALUMINUM, TC-406, 4-compartment, capacity)
//      • Per-compartment commodity + net gallons
//      • Placards (COMBUSTIBLE 1993 / NA1993 / DIESEL ULSD) — only shown
//        if the unit's commodity/hazmat profile lands on the model
//      • CIVACON ground status
//      • GVWR, tractor fuel gallons, MPG-30D
//      • DOT-annual / oil / tire-rotate countdowns
//      • Pre-trip checklist line items
//
//    The LAYOUT, LABELS and STRUCTURE are verbatim from the SVG; the
//    DATA is live-or-empty. No stub numbers are dressed up as real.
//
//    "Book oil" CTA: there is no oil/service-booking mutation in
//    EusoTripAPI today (searched: oil/service/book/schedule maintenance
//    — only read-side maintenance history + equipmentIntelligence scan
//    exist). So the CTA renders in a first-class disabled-with-reason
//    state that names the missing capability — NOT a dead no-op. If a
//    unit is assigned, "Log" deep-links into the maintenance log intent
//    surfaced honestly; if no booking endpoint, "Book oil" discloses why.
//

import SwiftUI

// MARK: - Screen root

struct VehicleAndEquipment: View {
    @Environment(\.palette) var palette
    @StateObject private var assigned = AssignedVehicleStore()
    @StateObject private var maintenance = VehicleMaintenanceHistoryStore()

    /// Surfaced when the driver taps "Book oil" — there is no booking
    /// mutation server-side, so we disclose that honestly instead of a
    /// silent no-op.
    @State private var bookOilNotice: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
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
                        powerUnitHero(v)
                        equipmentSpecCard(v)
                        compartmentsSection
                        placardsSection
                        statTilesRow            // GVWR · TRACTOR FUEL · MPG 30D
                        dvirSection             // LAST DVIR + pre-trip checklist
                        serviceCountdownRow     // OIL · DOT ANNUAL · TIRE ROTATE
                        bookOilCard(v)
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .overlay(alignment: .top) {
            if let notice = bookOilNotice {
                Text(notice)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Brand.warning.opacity(0.95), in: Capsule())
                    .padding(.top, 12)
                    .padding(.horizontal, Space.s4)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            await MainActor.run { bookOilNotice = nil }
                        }
                    }
            }
        }
    }

    private func reload() async {
        await assigned.refresh()
        if let v = assigned.state.value, !v.isUnassigned {
            maintenance.vehicleId = v.id
            await maintenance.refresh()
        }
    }

    // MARK: Header
    //  SVG: "✦ DRIVER · VEHICLE & EQUIPMENT" eyebrow + "ASSIGNED RIG 2041".

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DRIVER · VEHICLE & EQUIPMENT")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                if let v = assigned.state.value, !v.unitNumber.isEmpty {
                    Text("ASSIGNED RIG \(v.unitNumber)")
                        .font(EType.micro)
                        .tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rigHeadline)
                        .font(EType.h1)
                        .foregroundStyle(palette.textPrimary)
                    Text("Vehicle & equipment · spec · compliance · service")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                OrbeSang(state: (assigned.isLoading || maintenance.isLoading) ? .thinking : .idle, diameter: 40)
            }
        }
    }

    private var rigHeadline: String {
        if let v = assigned.state.value, !v.isUnassigned, !v.unitNumber.isEmpty {
            return "Rig \(v.unitNumber)"
        }
        return "Vehicle"
    }

    // MARK: Power-unit hero
    //  SVG: "Rig 2041" / "POWER UNIT · Kenworth T680 · TRK-8291 · VIN …".

    private func powerUnitHero(_ v: VehicleAPI.AssignedVehicle) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("POWER UNIT · TRACTOR")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(modelHeadline(v))
                        .font(EType.h2)
                        .foregroundStyle(LinearGradient.diagonal)
                    if v.year > 0 {
                        Text(String(v.year))
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                statusChip(v.status)
            }
            // Identity meta line — VIN / plate / unit, honest-empty when absent.
            let metaParts = powerUnitMeta(v)
            if !metaParts.isEmpty {
                Text(metaParts.joined(separator: " · "))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            // Odometer / fuel — only when telematics has supplied non-zero.
            telematicsStrip(v)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func powerUnitMeta(_ v: VehicleAPI.AssignedVehicle) -> [String] {
        var parts: [String] = []
        if !v.unitNumber.isEmpty { parts.append("UNIT \(v.unitNumber)") }
        if !v.licensePlate.isEmpty { parts.append("PLATE \(v.licensePlate)") }
        if !v.vin.isEmpty { parts.append("VIN \(v.vin)") }
        return parts
    }

    @ViewBuilder
    private func telematicsStrip(_ v: VehicleAPI.AssignedVehicle) -> some View {
        let hasOdo = v.odometer > 0
        let hasFuel = v.fuelLevel > 0
        if hasOdo || hasFuel {
            HStack(spacing: Space.s4) {
                if hasOdo {
                    miniMetric(icon: "gauge.with.dots.needle.50percent",
                               value: "\(v.odometer.formatted()) mi",
                               label: "ODOMETER")
                }
                if hasFuel {
                    miniMetric(icon: "fuelpump.fill",
                               value: "\(Int(v.fuelLevel.rounded()))%",
                               label: "TRACTOR FUEL")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Space.s1)
        }
    }

    private func miniMetric(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(label)
                    .font(EType.micro)
                    .tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Equipment spec card
    //  SVG band: "EQUIPMENT · DOT-406 TANK · TRL-2287 · 9,500 GAL" and the
    //  tank-side stencils "DIESEL FUEL ULSD / DOT-406 ALUMINUM / 9,500 GAL
    //  / 4 CMPT · TC-406 · #2 ULSD".
    //
    //  None of these tanker-spec fields exist on the backend model, so we
    //  render an HONEST "No tanker spec on file" card with the structure
    //  intact and "—" placeholders. We never print the SVG's mock numbers.

    private func equipmentSpecCard(_ v: VehicleAPI.AssignedVehicle) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.hazmat)
                Text("EQUIPMENT · DOT-406 TANKER")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            // The backend AssignedVehicle has no tanker-equipment fields.
            VStack(alignment: .leading, spacing: Space.s2) {
                specRow(label: "DOT SPEC", value: "—")
                Divider().overlay(palette.borderFaint)
                specRow(label: "CAPACITY", value: "—")
                Divider().overlay(palette.borderFaint)
                specRow(label: "COMPARTMENTS", value: "—")
                Divider().overlay(palette.borderFaint)
                specRow(label: "TRAILER UNIT", value: "—")
            }
            Label("No tanker spec on file for this unit. Capacity, DOT-406 class, TC-406 compartment data and commodity land here once the equipment record is populated by dispatch.",
                  systemImage: "info.circle")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func specRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.micro)
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Compartments — TC-406 / CMPT 1-4
    //  SVG: 4 manhole domes (CMPT 1-4), "CMPT 1 · DIESEL ULSD", "GAL · NET".
    //  No per-compartment data on the model → honest empty grid of 4 slots.

    private var compartmentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COMPARTMENTS · TC-406")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(1...4, id: \.self) { idx in
                    compartmentTile(idx)
                }
            }
            Text("Per-compartment commodity (DIESEL ULSD) and net gallons appear once the tanker's TC-406 compartment manifest is on file.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func compartmentTile(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("CMPT \(idx)")
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("—")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("GAL · NET")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Placards & ground status
    //  SVG: COMBUSTIBLE 1993 / NA1993 / DIESEL · ULSD placards, "CIVACON ·
    //  GROUND OK". No hazmat/commodity profile on the model → honest empty.

    private var placardsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PLACARDS · GROUND STATUS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                Image(systemName: "diamond")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No placard profile on file")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("COMBUSTIBLE 1993 / NA1993 / DIESEL ULSD placards and CIVACON ground-bond status surface from the unit's commodity record when assigned.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
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
    }

    // MARK: Stat tiles — GVWR · TRACTOR FUEL · MPG 30D
    //  SVG: three 80pt tiles. None backed by the model → honest "—".

    private var statTilesRow: some View {
        HStack(spacing: Space.s2) {
            statTile(label: "GVWR", value: "—", sub: "LB · COMBINED", gradient: false)
            statTile(label: "TRACTOR FUEL", value: "—", sub: "GAL DIESEL", gradient: false)
            statTile(label: "MPG 30D", value: "—", sub: "ROLLING", gradient: true)
        }
    }

    private func statTile(label: String, value: String, sub: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(0.8)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(gradient ? Color.white : palette.textPrimary)
            Text(sub)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .padding(Space.s3)
        .background(
            Group {
                if gradient {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: gradient ? 0 : 1)
        )
    }

    // MARK: DVIR + pre-trip checklist
    //  SVG: "LAST DVIR · RIG · 04:12 THIS MORNING · 3 PASS · 1 NOTE", then
    //  4 checklist rows (Brakes & airlines / Tires & suspension / Lights &
    //  reflectors / Tank & hose fittings).
    //
    //  The backend exposes maintenance-event history (real) but NOT a
    //  structured DVIR pass/note checklist. We render the real maintenance
    //  feed under the honest "LAST SERVICE" header, and disclose that the
    //  itemized pre-trip checklist isn't on the record yet.

    @ViewBuilder
    private var dvirSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LAST SERVICE · RIG")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if case .loaded(let rows) = maintenance.state {
                    Text("\(rows.count) ON RECORD")
                        .font(EType.micro)
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            switch maintenance.state {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
                    .frame(height: 64)
            case .empty:
                checklistEmpty
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
                    ForEach(rows.prefix(4)) { row in
                        serviceRow(row)
                    }
                }
            }
            Text("Itemized pre-trip DVIR (brakes & airlines, tires & suspension, lights & reflectors, tank & hose fittings) renders here once electronic DVIR submissions are linked to this unit.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var checklistEmpty: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No service or DVIR events on record for this unit yet.")
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

    private func serviceRow(_ r: VehicleAPI.MaintenanceRecord) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.description.isEmpty ? r.type : r.description)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if !r.date.isEmpty {
                    Text(prettyDate(r.date))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            serviceStatusChip(r.status)
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
    private func serviceStatusChip(_ status: String) -> some View {
        let label = status.replacingOccurrences(of: "_", with: " ").uppercased()
        switch status.lowercased() {
        case "completed", "approved", "pass":
            Text(label.isEmpty ? "LOGGED" : label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "failed", "rejected", "note":
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
        default:
            Text(label.isEmpty ? "LOGGED" : label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 2)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Service countdowns — OIL · DOT ANNUAL · TIRE ROTATE
    //  SVG: three tiles ("1,100 MI TO CHANGE", "30 D TO ANNUAL", "8,950 MI
    //  TO GO"). No maintenance-schedule fields on the model → honest "—".

    private var serviceCountdownRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SERVICE COUNTDOWN")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                statTile(label: "OIL", value: "—", sub: "MI TO CHANGE", gradient: true)
                statTile(label: "DOT ANNUAL", value: "—", sub: "D TO ANNUAL", gradient: false)
                statTile(label: "TIRE ROTATE", value: "—", sub: "MI TO GO", gradient: false)
            }
            Text("Live oil-change mileage, DOT-annual inspection date and tire-rotation interval populate from the unit's maintenance schedule when on file.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Book oil CTA
    //  SVG: "ESang · oil service opens Saturday AM / at Buckeye shop · save
    //  38 mi" suggestion row + a "Log" pill and a primary "Book oil" pill.
    //
    //  There is no oil/service booking mutation in EusoTripAPI. Rather than
    //  a dead no-op, "Book oil" surfaces a first-class disabled-with-reason
    //  notice naming the missing capability. The suggestion copy is shown
    //  as the generic ESang-service intent (not a fabricated shop/distance).

    private func bookOilCard(_ v: VehicleAPI.AssignedVehicle) -> some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                        .frame(width: 28, height: 28)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ESang · oil service")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Routing to a partner shop isn't wired yet — booking lands when the service-scheduling endpoint ships.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )

            HStack(spacing: Space.s3) {
                // "Log" — opens the (real) maintenance history this unit
                // already drives; honest scroll-to intent rather than a
                // fake navigation target.
                Button {
                    bookOilNotice = maintenanceLogNotice
                } label: {
                    Text("Log")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 96, height: 48)
                        .background(
                            Capsule().strokeBorder(palette.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // "Book oil" — no booking mutation exists; disabled-with-reason.
                Button {
                    bookOilNotice = "Oil-service booking isn't available yet — no scheduling endpoint on the server."
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Book oil")
                            .font(EType.bodyStrong)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var maintenanceLogNotice: String {
        switch maintenance.state {
        case .loaded(let rows) where !rows.isEmpty:
            return "\(rows.count) service event\(rows.count == 1 ? "" : "s") on record for this unit — see the Last Service list above."
        case .empty:
            return "No service events on record for this unit yet."
        default:
            return "Loading this unit's service log…"
        }
    }

    // MARK: Hero variants

    private var unassignedHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "truck.box.badge.clock")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Text("No vehicle assigned")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Your dispatcher assigns the tractor and tanker before your next run. The DOT-406 equipment profile appears here once a rig is on your name. Pull to refresh.")
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

    // MARK: Status chip (mirrors 073)

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let normalized = status.lowercased()
        let label = statusLabel(normalized)
        switch normalized {
        case "available", "in_use", "active":
            Text(label.uppercased())
                .font(EType.micro).tracking(1.1).foregroundStyle(.white)
                .padding(.horizontal, Space.s2).padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "maintenance", "out_of_service":
            Text(label.uppercased())
                .font(EType.micro).tracking(1.1).foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2).padding(.vertical, 2)
                .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
        default:
            Text(label.uppercased())
                .font(EType.micro).tracking(1.1).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Space.s2).padding(.vertical, 2)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
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

    // MARK: Helpers

    private func modelHeadline(_ v: VehicleAPI.AssignedVehicle) -> String {
        let composed = "\(v.make) \(v.model)".trimmingCharacters(in: .whitespaces)
        if !composed.isEmpty { return composed }
        if !v.unitNumber.isEmpty { return "Unit \(v.unitNumber)" }
        return "Vehicle"
    }

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

struct VehicleAndEquipmentScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VehicleAndEquipment()
        } nav: {
            BottomNav(
                leading: driverNavLeading_059(),
                trailing: driverNavTrailing_059(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_059() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "clock",  isCurrent: false)]
}
private func driverNavTrailing_059() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: true)]
}

// MARK: - Previews

#Preview("059 · Vehicle & Equipment · Night") {
    VehicleAndEquipmentScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("059 · Vehicle & Equipment · Day") {
    VehicleAndEquipmentScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
