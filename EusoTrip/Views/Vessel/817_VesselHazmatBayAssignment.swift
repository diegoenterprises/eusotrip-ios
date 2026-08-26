//
//  817_VesselHazmatBayAssignment.swift
//  EusoTrip — Vessel Operator · Hazmat Bay Assignment.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/817 Vessel Hazmat Bay Assignment.svg" (Light + Dark),
//  built on the canonical DesignSystem at the golden-era bar. Archetype = TERMINAL HAZMAT-APRON
//  ASSIGNMENT CONSOLE (carried by no other screen): a top-down bay RACK BOARD + a pending-DG-to-bay
//  ledger + an IMDG segregation strip. Hazmat gets the most stringent lens — the bay compatibility
//  and 49 CFR 177.848 safety gate are real, never cosmetic. Role VESSEL_OPERATOR. Nav COMPLIANCE
//  inked (a hazmat-safety surface).
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    appointments.getHazmatBays   EXISTS frontend/server/routers/appointments.ts:610 · query ·
//      input {facilityId?, hazmatClass?, date?} · returns {facilityId, bays:[{bayId, bayNumber, type,
//      certLevel, allowedClasses:[String], equipment:[], deconCapable, maxWeight, specialFeatures:[],
//      compatible, status, nextAvailable}], compatibleBays, totalBays, availableForClass,
//      recommendation}. Drives the apron RACK BOARD live — real certified bay types
//      (HAZMAT_A/B/C · TANKER · CRYO), real allowedClasses, real deconCapable, real compatibility for
//      the threaded class. No fabricated bays.
//    appointments.assignHazmatBay EXISTS appointments.ts:708 · mutation · input {appointmentId, bayId,
//      hazmatClass, requiresDecon:Bool, deconType?, previousProduct?, nextProduct?} · returns
//      {success, assignedAt, decon:{estimatedMinutes, checklist[]}, safetyReminders[]}. Wired to
//      "Assign bay" — fires ONLY with a real threaded appointment + a selected bay; the SAFETY GATE
//      rejects an incompatible class (49 CFR 177.848) and its message is surfaced verbatim.
//      DECON_TIMES: standard_wash 45 · chemical_decon 90 · vapor_purge 60 · cryogenic_warmup 120 ·
//      full_decon 180 min. Persists appointments.dockNumber + blockchainAuditTrail +
//      WS_CHANNELS.TERMINAL fan-out. RBAC isolatedProcedure.
//    STUB · named-gap handed to the-oath: getPendingHazmatUnits({facilityId}) -> [{containerId,
//      unClass, unNumber, properShippingName, weightKg, gateCutoff, recommendedBayId, requiresDecon,
//      deconType}] — the inbound-DG intake queue is not modelled; the ledger renders the honest empty
//      state until it lands, never a fabricated container.
//    Tri-country port-facility hazmat authority band = published regulatory reference (US USCG 33 CFR
//      126 · CA TC Marine MTSR · MX SEMAR API concession) — constants, not tenant data.
//
//  HazmatBay817 is a file-scoped bespoke type suffixed by the screen number. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shape (mirrors appointments.getHazmatBays.bays rows)

private struct HazmatBay817: Decodable, Identifiable {
    let bayId: String
    let bayNumber: Int?
    let type: String?
    let certLevel: String?
    let allowedClasses: [String]?
    let deconCapable: Bool?
    let compatible: Bool?
    let status: String?
    var id: String { bayId }
}

private struct HazmatBaysResponse817: Decodable {
    let facilityId: String?
    let bays: [HazmatBay817]?
    let availableForClass: Int?
    let totalBays: Int?
}

private struct AssignAck817: Decodable { let success: Bool? ; let assignedAt: String? }

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselHazmatBayAssignmentScreen: View {
    let theme: Theme.Palette
    /// The DG class to place (drives the real compatibility highlight). Empty = show the whole apron.
    var hazmatClass: String
    /// The inbound appointment being assigned. Empty = read-only reference; Assign stays disabled.
    var appointmentId: String
    var facilityId: String

    init(theme: Theme.Palette, hazmatClass: String = "", appointmentId: String = "", facilityId: String = "") {
        self.theme = theme; self.hazmatClass = hazmatClass
        self.appointmentId = appointmentId; self.facilityId = facilityId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselHazmatBayBody817(hazmatClass: hazmatClass, appointmentId: appointmentId, facilityId: facilityId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselHazmatBayBody817: View {
    @Environment(\.palette) private var palette
    let hazmatClass: String
    let appointmentId: String
    let facilityId: String

    @State private var bays: [HazmatBay817] = []
    @State private var facility: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var selectedBayId: String? = nil
    @State private var assigning = false
    @State private var assignDone: String? = nil
    @State private var assignError: String? = nil

    // Derived (all read one real load) ------------------------------------
    private var openBays: [HazmatBay817] { bays.filter { ($0.status ?? "available") == "available" } }
    private var openCount: Int { openBays.count }
    private var deconCount: Int { bays.filter { $0.deconCapable ?? false }.count }
    private var compatibleForClass: [HazmatBay817] {
        hazmatClass.isEmpty ? [] : bays.filter { ($0.compatible ?? false) }
    }
    /// The single best bay for the threaded class: compatible + decon-capable, first available.
    private var bestFitId: String? {
        guard !hazmatClass.isEmpty else { return nil }
        return compatibleForClass.first(where: { $0.deconCapable ?? false })?.bayId
            ?? compatibleForClass.first?.bayId
    }
    private var blocked: Bool { !hazmatClass.isEmpty && compatibleForClass.isEmpty && !bays.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    apronBoard
                    assignmentLedger
                    segregationStrip
                    authorityBand
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · HAZMAT BAYS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text(facility ?? (facilityId.isEmpty ? "APRON" : facilityId))
                .font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hazmat bays").font(.system(size: 26, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(hazmatClass.isEmpty ? "Terminal apron · certified bays"
                                         : "Placing Class \(hazmatClass) · certified bays")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("BAYS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("\(openCount)/\(bays.count) open")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Brand.success)
            }
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft).frame(height: 92)
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft).frame(height: 120)
        }.padding(.top, Space.s2)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apron feed degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero (apron status · danger-wash only on a real block)

    private var heroCard: some View {
        let wash = blocked
        return HStack(alignment: .center, spacing: Space.s4) {
            Rectangle().fill(wash ? Brand.danger : Brand.success).frame(width: 4).cornerRadius(2)
            VStack(alignment: .leading, spacing: 4) {
                Text(wash ? "SEGREGATION HOLD" : "APRON READY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(wash ? Brand.danger : Brand.success)
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text("\(hazmatClass.isEmpty ? openCount : compatibleForClass.count)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                        .foregroundStyle(wash ? Brand.danger : palette.textPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hazmatClass.isEmpty ? "bays open" : "bays certified")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(hazmatClass.isEmpty ? "\(deconCount) decon-capable"
                                                 : "for Class \(hazmatClass) · \(deconCount) decon")
                            .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
                if blocked {
                    Text("No certified bay for Class \(hazmatClass) at this facility · 49 CFR 177.848")
                        .font(EType.mono(.micro)).foregroundStyle(Brand.danger)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background((wash ? Brand.danger : palette.bgCardSoft).opacity(wash ? 0.10 : 1))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(wash ? Brand.danger.opacity(0.32) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Apron rack board (real bays)

    private var apronBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("TERMINAL HAZMAT APRON")
                Spacer()
                Text("LIVE HAZMAT BAY STATUS").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(bays) { bay in bayCard(bay) }
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            HStack(spacing: Space.s3) {
                Text("QUAY EDGE").font(.system(size: 8)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("decon-capable").font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func bayCard(_ bay: HazmatBay817) -> some View {
        let isBest = bay.bayId == bestFitId
        let compatible = bay.compatible ?? true
        let naClass = !hazmatClass.isEmpty && !compatible
        let selected = bay.bayId == selectedBayId
        return Button(action: { if !naClass { selectedBayId = bay.bayId } }) {
            VStack(spacing: 6) {
                Text(bayLabel(bay))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(naClass ? palette.textTertiary : palette.textPrimary)
                Text(classChip(bay.allowedClasses))
                    .font(.system(size: 7.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(compatible ? palette.textSecondary : Brand.danger)
                    .padding(.horizontal, 4).padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background((naClass ? Brand.danger.opacity(0.12) : Color.white.opacity(0.06)))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                HStack(spacing: 3) {
                    Circle().stroke((bay.deconCapable ?? false) ? Brand.success : palette.textTertiary, lineWidth: 1.2)
                        .background(Circle().fill((bay.deconCapable ?? false) ? Brand.success : .clear))
                        .frame(width: 6, height: 6)
                    Text((bay.deconCapable ?? false) ? "decon" : "no decon")
                        .font(.system(size: 7.5)).foregroundStyle(palette.textTertiary)
                }
                Text(statusText(bay, isBest: isBest, naClass: naClass))
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(statusColor(isBest: isBest, naClass: naClass))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(statusBg(isBest: isBest, naClass: naClass))
                    .clipShape(Capsule())
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(
                ZStack {
                    palette.bgCard
                    if isBest { LinearGradient.diagonal.opacity(0.12) }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isBest ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(selected ? Brand.blue : palette.borderFaint),
                              lineWidth: isBest ? 2 : (selected ? 1.5 : 1)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bay \(bayLabel(bay)), \(statusText(bay, isBest: isBest, naClass: naClass))")
    }

    // MARK: Assignment ledger (STUB · honest empty)

    private var assignmentLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("PENDING DG UNITS → RECOMMENDED BAY")
                Spacer()
                Text("PENDING HAZMAT UNITS UNAVAILABLE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                           title: "No inbound DG in the terminal feed",
                           subtitle: "Pending dangerous-goods containers and their recommended bays surface here the moment the terminal DG-intake queue is wired.")
                .padding(Space.s4)
                .frame(maxWidth: .infinity)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Segregation strip (derived from real bay allowedClasses)

    private var segregationStrip: some View {
        let cleared = !blocked
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text("IMDG SEGREGATION · 7.2").font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(hazmatClass.isEmpty
                     ? "Select a class to check bay segregation"
                     : "Class \(hazmatClass) placed on a certified, decon-ready bay")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(cleared ? "CLEAR" : "HOLD")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(cleared ? Brand.success : Brand.danger)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill((cleared ? Brand.success : Brand.danger).opacity(0.16)))
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Tri-country authority band (regulatory reference)

    private var authorityBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("PORT FACILITY HAZMAT AUTHORITY · BY COUNTRY")
                Spacer()
                Text("US active").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                authorityCell(active: true,  code: "US · USCG", detail: "33 CFR 126 · active")
                authorityCell(active: false, code: "CA · TC",   detail: "Marine MTSR")
                authorityCell(active: false, code: "MX · SEMAR",detail: "API concession")
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func authorityCell(active: Bool, code: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
            Text(detail).font(EType.mono(.micro)).foregroundStyle(active ? palette.textSecondary : palette.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, 8)
        .background(active ? Brand.info.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = assignError { Text(e).font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true) }
            if let d = assignDone { Text(d).font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: assigning ? "Assigning…" : assignTitle,
                          action: { Task { await assign() } },
                          isLoading: assigning || !canAssign)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Segregation")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 144)
            }
            if !canAssign {
                Text(appointmentId.isEmpty
                     ? "Open from an inbound appointment, pick a bay, to assign."
                     : "Pick a certified bay above to assign.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var canAssign: Bool { !appointmentId.isEmpty && !hazmatClass.isEmpty && selectedBayId != nil }
    private var assignTitle: String {
        if let id = selectedBayId, let bay = bays.first(where: { $0.bayId == id }) { return "Assign \(bayLabel(bay))" }
        return "Assign bay"
    }

    // MARK: Load + assign

    private func load() async {
        loading = true; loadError = nil
        struct In817: Encodable { let facilityId: String?; let hazmatClass: String? }
        do {
            let resp: HazmatBaysResponse817 = try await EusoTripAPI.shared.query(
                "appointments.getHazmatBays",
                input: In817(facilityId: facilityId.isEmpty ? nil : facilityId,
                             hazmatClass: hazmatClass.isEmpty ? nil : hazmatClass))
            bays = resp.bays ?? []
            facility = resp.facilityId
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assign() async {
        guard canAssign, let bayId = selectedBayId else { return }
        guard let bay = bays.first(where: { $0.bayId == bayId }) else { return }
        assigning = true; assignError = nil; assignDone = nil
        struct In817: Encodable {
            let appointmentId: String
            let bayId: String
            let hazmatClass: String
            let requiresDecon: Bool
        }
        do {
            let ack: AssignAck817 = try await EusoTripAPI.shared.mutation(
                "appointments.assignHazmatBay",
                input: In817(appointmentId: appointmentId, bayId: bayId, hazmatClass: hazmatClass,
                             requiresDecon: bay.deconCapable ?? false))
            if ack.success == true { assignDone = "Class \(hazmatClass) assigned to \(bayLabel(bay)) · safety brief issued." }
            await load()
        } catch {
            // 49 CFR 177.848 safety-gate rejection (or any server error) surfaced verbatim.
            assignError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = false
    }

    // MARK: Helpers

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private func bayLabel(_ bay: HazmatBay817) -> String {
        let initial: String
        switch bay.type {
        case "HAZMAT_A": initial = "A"
        case "HAZMAT_B": initial = "B"
        case "HAZMAT_C": initial = "C"
        case "TANKER":   initial = "T"
        case "CRYO":     initial = "K"
        default:         initial = String((bay.type ?? "B").prefix(1))
        }
        return "\(initial)-\(bay.bayNumber ?? 0)"
    }
    private func classChip(_ classes: [String]?) -> String {
        guard let c = classes, !c.isEmpty else { return "—" }
        if c.count > 10 { return "1.1–9 ALL" }
        return c.prefix(4).joined(separator: "·")
    }
    private func statusText(_ bay: HazmatBay817, isBest: Bool, naClass: Bool) -> String {
        if naClass { return "N/A CLASS" }
        if isBest { return "BEST FIT" }
        return (bay.status ?? "available") == "available" ? "OPEN" : (bay.status ?? "OPEN").uppercased()
    }
    private func statusColor(isBest: Bool, naClass: Bool) -> Color {
        if isBest { return .white }
        if naClass { return palette.textTertiary }
        return Brand.info
    }
    private func statusBg(isBest: Bool, naClass: Bool) -> some ShapeStyle {
        if isBest { return AnyShapeStyle(LinearGradient.primary) }
        if naClass { return AnyShapeStyle(Color.white.opacity(0.05)) }
        return AnyShapeStyle(Brand.info.opacity(0.18))
    }
}

// MARK: - Previews

#Preview("817 · Vessel Hazmat Bay · Night") {
    VesselHazmatBayAssignmentScreen(theme: Theme.dark, hazmatClass: "3")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("817 · Vessel Hazmat Bay · Light") {
    VesselHazmatBayAssignmentScreen(theme: Theme.light, hazmatClass: "3")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
