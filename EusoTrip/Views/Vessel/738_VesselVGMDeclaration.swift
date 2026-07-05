//
//  738_VesselVGMDeclaration.swift
//  EusoTrip — Vessel Operator · VGM Declaration (SOLAS VI/2 verified gross mass).
//
//  Verbatim bespoke port of canonical wireframe 738 "Vessel VGM Declaration".
//  This is the purpose-built SOLAS VGM DECLARATION FORM — NOT a stat-hero stamp:
//    · container particulars header (number / size-type / vessel / cutoff)
//    · tare + cargo = VERIFIED GROSS MASS calc block (within the box's limit)
//    · weighing-method selector (Method 1 whole-container weighbridge ·
//      Method 2 sum-of-packages + tare, per SOLAS VI/2)
//    · per-container SUBMIT LEDGER with DRAFT / SUBMITTED / OVERDUE states
//    · signatory card (shipper-of-record on the master B/L)
//
//  Docked under SHIPMENTS. transportMode=vessel · kg.
//  Value: computes + files the verified gross mass per box before the SOLAS
//  cutoff so the container is allowed to load and the operator avoids a roll.
//
//  REAL WIRING (tRPC — re-verified against the live router 2026-06-10):
//    · vesselShipments.getContainerPositions {limit}
//        -> { containers, total }; LIVE shipping_containers rows (number /
//        isoType / sizeType / status / tareWeightKg / maxPayloadKg /
//        ownerCompany) seed the ledger + the particulars header. The focus box
//        is the first live row — never a hardcoded canon container.
//        (vesselShipments.ts:1405)
//    · TARE auto-fill is REAL: shipping_containers.tareWeightKg pre-fills the
//      tare field when the live row carries it; the box's gross limit is
//      tareWeightKg + maxPayloadKg from the same row. When either column is
//      null we render the honest "enter weights / no limit on record" state —
//      no invented 40HC defaults.
//
//  VGM filing:
//    · vesselShipments.submitVgmDeclaration records the declaration as an
//      auditable vessel event + container tracking row. The container table has
//      tare/payload columns but no VGM column, so the filing ledger is the
//      shipment event stream.
//
//  RBAC: vesselProcedure. NO mock rows — the ledger is built from live
//  container rows with real loading / empty / error states.
//
//  De-fab salvage 2026-06-10 (from PR #50): killed the hardcoded canon
//  container (MSCU7741203), the fabricated vessel string (MV EUSO MERIDIAN
//  v.118E), the seeded USLAX port, the "Diego Usoro"/"Eusorone Technologies"
//  signatory fallback, the invented 40HC size + 23,000 kg limit, and the
//  decorative back chevron; wired tare/limit to the real columns.
//

import SwiftUI

struct VesselVGMDeclarationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselVGMDeclarationBody() } nav: {
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

// MARK: - Data shapes (mirror getContainerPositions → { containers, total })

/// One live `shipping_containers` row. tareWeightKg / maxPayloadKg are the
/// REAL weight columns — when present they drive the tare auto-fill and the
/// box's gross-mass limit; when null the form stays honestly blank.
private struct VGMContainer738: Decodable {
    let id: Int?
    let containerNumber: String?
    let isoType: String?
    let sizeType: String?
    let status: String?
    let tareWeightKg: Int?
    let maxPayloadKg: Int?
    let ownerCompany: String?
    let assignedShipmentId: Int?
}

private struct VGMPositionsResponse738: Decodable {
    let containers: [VGMContainer738]
    let total: Int?
}

// MARK: - Weighing method (SOLAS VI/2)

private enum WeighingMethod: Int, CaseIterable, Identifiable {
    case method1   // whole-container weighbridge
    case method2   // sum of packages + tare
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .method1: return "Method 1 · whole-container weighbridge"
        case .method2: return "Method 2 · sum of packages + tare"
        }
    }
    var detail: String {
        switch self {
        case .method1: return "certified scale · ticket on file"
        case .method2: return "calculated · requires registered weighing procedure"
        }
    }
    var shortLabel: String {
        switch self {
        case .method1: return "method 1"
        case .method2: return "method 2"
        }
    }
    var apiValue: String {
        switch self {
        case .method1: return "method1"
        case .method2: return "method2"
        }
    }
    var contextLabel: String {
        switch self {
        case .method1: return "container weighbridge"
        case .method2: return "calculated"
        }
    }
}

// MARK: - Ledger status (per the SVG badge states)

private enum VGMStatus {
    case draft, submitted, overdue

    var label: String {
        switch self {
        case .draft:     return "DRAFT"
        case .submitted: return "SUBMITTED"
        case .overdue:   return "OVERDUE"
        }
    }
    func color(_ palette: Theme.Palette) -> Color {
        switch self {
        case .draft:     return Brand.warning
        case .submitted: return Brand.success
        case .overdue:   return Brand.danger
        }
    }
}

/// A live container row in the submit ledger. `vgmKg` is non-nil only once the
/// operator has filed a verified gross mass for that box — never fabricated.
private struct VGMLedgerRow: Identifiable {
    let id: String
    let containerNumber: String
    let status: VGMStatus
    let vgmKg: Int?
    let method: WeighingMethod?
    let cutoffNote: String?   // shown when no VGM yet (e.g. "cutoff in 2h 10m")
}

// MARK: - Body

private struct VesselVGMDeclarationBody: View {
    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette

    @State private var rows: [VGMLedgerRow] = []
    @State private var headerContainer: VGMContainer738? = nil
    @State private var tareAutoFilled = false
    @State private var loading = true
    @State private var loadError: String? = nil

    // In-form declaration. Tare pre-fills from the live row's tareWeightKg
    // when the column is populated; cargo is always operator-entered.
    @State private var tareText: String = ""
    @State private var cargoText: String = ""
    @State private var method: WeighingMethod = .method1

    // Submit named-gap surfacing.
    @State private var submitting = false
    @State private var submitNote: String? = nil
    @State private var submitError: String? = nil

    /// The focused box's REAL max gross mass (tareWeightKg + maxPayloadKg from
    /// the live row) — nil when the columns aren't populated, in which case we
    /// make no within/over claim at all.
    private var maxGrossKg: Int? {
        guard let t = headerContainer?.tareWeightKg, t > 0,
              let p = headerContainer?.maxPayloadKg, p > 0 else { return nil }
        return t + p
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        particularsCard
                        weighingMethodSection
                        ledgerSection
                        signatoryCard
                        esangAssistRow
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back chevron + headline + meta)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · VGM SOLAS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("VGM · SOLAS VI/2")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("VGM declaration")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Container particulars + VGM calc block (gradient-rim card)

    private var particularsCard: some View {
        let displayNumber = headerContainer?.containerNumber.map(formatContainer) ?? "—"
        let statusNote = headerStatusNote

        return VStack(alignment: .leading, spacing: Space.s4) {
            // Header: container number · size-type / owner / status — all from
            // the live row; no fabricated vessel/voyage string.
            VStack(alignment: .leading, spacing: 4) {
                Text(displayNumber)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(particularsSubline(statusNote: statusNote))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            // tare + cargo = VERIFIED GROSS MASS
            HStack(alignment: .top, spacing: Space.s2) {
                weightField(label: "TARE", text: $tareText, unit: "kg")
                Text("+")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 14)
                weightField(label: "CARGO", text: $cargoText, unit: "kg")
                Text("=")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 14)
                vgmReadout
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func weightField(label: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var vgmReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VERIFIED GROSS MASS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let vgm = computedVGM {
                Text(vgm.formatted(.number.grouping(.automatic)))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let limit = maxGrossKg {
                    Text(vgm <= limit
                         ? "kg · within \(limit.formatted(.number.grouping(.automatic))) kg limit"
                         : "kg · OVER \(limit.formatted(.number.grouping(.automatic))) kg limit")
                        .font(.system(size: 10))
                        .foregroundStyle(vgm <= limit ? palette.textSecondary : Brand.danger)
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    // No tare/payload columns on the live row — make no
                    // within/over claim against an invented limit.
                    Text("kg · no gross limit on record for this box")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("enter tare + cargo")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Weighing method · SOLAS VI/2

    private var weighingMethodSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("WEIGHING METHOD · SOLAS VI/2")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(method.contextLabel)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                methodRow(.method1)
                Divider().overlay(palette.borderFaint)
                    .padding(.horizontal, Space.s4)
                methodRow(.method2)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func methodRow(_ m: WeighingMethod) -> some View {
        let selected = method == m
        return Button {
            method = m
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? AnyShapeStyle(LinearGradient.primary)
                                               : AnyShapeStyle(palette.textTertiary),
                                      lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if selected {
                        Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(m.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? palette.textSecondary : palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Containers to declare · submit ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONTAINERS TO DECLARE · \(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("VGM event ledger")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No containers awaiting VGM",
                    subtitle: "Live boxes from the container pool will queue here for declaration before the SOLAS cutoff."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        ledgerRow(row)
                        if idx < rows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func ledgerRow(_ row: VGMLedgerRow) -> some View {
        let color = row.status.color(palette)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.containerNumber)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(ledgerSubline(row))
                    .font(EType.mono(.caption))
                    .foregroundStyle(row.status == .overdue ? Brand.danger : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(row.status.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                .foregroundStyle(color)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.14)))
        }
        .padding(Space.s4)
    }

    private func ledgerSubline(_ row: VGMLedgerRow) -> String {
        if let vgm = row.vgmKg {
            var s = "\(vgm.formatted(.number.grouping(.automatic))) kg"
            if let m = row.method { s += " · \(m.shortLabel)" }
            return s
        }
        return row.cutoffNote ?? "awaiting verified gross mass"
    }

    // MARK: - Signatory (shipper-of-record on master B/L)

    private var signatoryCard: some View {
        // The signed-in operator IS the signatory — no seeded identity.
        let name = (session.user?.name?.isEmpty == false ? session.user?.name : nil)
        let initials = name.map(signatoryInitials) ?? "—"
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text(initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.map { "Authorized · \($0)" } ?? "Authorized signatory")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("shipper of record · master B/L")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func signatoryInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "DU" : combined
    }

    // MARK: - ESang assist row (push-nav assist, NOT a slide-up)

    private var esangAssistRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                         center: .topLeading, startRadius: 0, endRadius: 14))
                    .frame(width: 26, height: 26)
                    .offset(x: -3, y: -3)
            }
            VStack(alignment: .leading, spacing: 2) {
                // Honest assist copy: the auto-fill claim renders ONLY when the
                // tare actually came off the live row.
                Text(tareAutoFilled
                     ? "Tare auto-filled from container particulars"
                     : "Enter tare and cargo weights to compute VGM")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("ESang · verify cargo weight before the SOLAS cutoff")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA row (Submit VGM · Method)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let note = submitNote {
                LifecycleCard(accentWarning: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(note).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            if let err = submitError {
                LifecycleCard(accentDanger: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    Task { await submitVGM() }
                } label: {
                    HStack(spacing: 6) {
                        if submitting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        }
                        Text(submitting ? "Submitting…" : "Submit VGM")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(submitting || !declarationComplete)
                .opacity(declarationComplete ? 1.0 : 0.55)

                Button {
                    method = (method == .method1) ? .method2 : .method1
                } label: {
                    Text("Method")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 128)
                        .frame(minHeight: 48)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Derived

    private var computedTare: Int? { Int(tareText.trimmingCharacters(in: .whitespaces)) }
    private var computedCargo: Int? { Int(cargoText.trimmingCharacters(in: .whitespaces)) }
    private var computedVGM: Int? {
        guard let t = computedTare, let c = computedCargo, t > 0, c > 0 else { return nil }
        return t + c
    }
    private var declarationComplete: Bool {
        guard let vgm = computedVGM else { return false }
        // Block only against the box's REAL limit; when the row carries none
        // the declaration is complete on entered weights alone.
        if let limit = maxGrossKg { return vgm <= limit }
        return true
    }

    /// Status note keyed off the REAL shipping_containers status enum
    /// (empty · loaded · in_transit · at_port · at_depot · in_repair ·
    /// at_shipper · at_consignee).
    private var headerStatusNote: String {
        switch (headerContainer?.status ?? "").lowercased() {
        case "in_transit":   return "in transit · declare before cutoff"
        case "at_port":      return "at port · awaiting VGM"
        case "at_shipper":   return "at shipper · awaiting VGM"
        case "at_depot":     return "at depot"
        case "at_consignee": return "at consignee"
        case "in_repair":    return "in repair"
        case "loaded":       return "loaded · VGM on file"
        case "empty":        return "empty"
        case "":             return "awaiting VGM declaration"
        default:             return (headerContainer?.status ?? "")
            .replacingOccurrences(of: "_", with: " ").lowercased()
        }
    }

    /// "{sizeType} · {ownerCompany} · {status}" from live columns only.
    private func particularsSubline(statusNote: String) -> String {
        var parts: [String] = []
        if let st = humanSizeType(headerContainer?.isoType ?? headerContainer?.sizeType) {
            parts.append(st)
        }
        if let owner = headerContainer?.ownerCompany, !owner.isEmpty {
            parts.append(owner)
        }
        parts.append(statusNote)
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    /// "MSCU7741203" → "MSCU 7741203" (owner prefix · serial).
    private func formatContainer(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard clean.count > 4 else { return clean }
        let prefix = String(clean.prefix(4))
        let rest = String(clean.dropFirst(4))
        return "\(prefix) \(rest)"
    }

    /// Maps ISO codes AND the schema's sizeType enum (20ft · 40ft · 40ft_hc ·
    /// 45ft · 20ft_reefer · 40ft_reefer) to trade shorthand. nil when the row
    /// carries neither — no invented 40HC default.
    private func humanSizeType(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.uppercased()
        if s.contains("REEF") || s.contains("RF") {
            return s.contains("20") ? "20RF" : "40RF"
        }
        if s.contains("40") && (s.contains("HC") || s.contains("HQ")) { return "40HC" }
        if s.contains("45") { return "45HC" }
        if s.contains("40") { return "40DC" }
        if s.contains("20") { return "20DC" }
        return s
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 132)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 168)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (getContainerPositions → particulars + ledger seed)

    private func load() async {
        loading = true; loadError = nil
        struct PositionsIn: Encodable { let limit: Int }
        do {
            // LIVE shipping_containers rows — the ledger and the focus box both
            // come straight off the table; nothing is seeded.
            let resp: VGMPositionsResponse738 = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions",
                input: PositionsIn(limit: 6))
            let containers = resp.containers.filter { ($0.containerNumber ?? "").isEmpty == false }
            self.headerContainer = containers.first

            // REAL tare auto-fill: shipping_containers.tareWeightKg, when the
            // row carries it. Only pre-fill an untouched field.
            if let tare = containers.first?.tareWeightKg, tare > 0,
               tareText.trimmingCharacters(in: .whitespaces).isEmpty {
                tareText = "\(tare)"
                tareAutoFilled = true
            }

            // Ledger rows: one per live box. No VGM mass is fabricated — the
            // table carries no filed-VGM column, so a box reads DRAFT until
            // declared. SOLAS inference: a box the table marks loaded /
            // in_transit could only have loaded with a VGM on file, so those
            // read SUBMITTED.
            self.rows = containers.map { c in
                let number = c.containerNumber ?? ""
                let status: VGMStatus = {
                    switch (c.status ?? "").lowercased() {
                    case "loaded", "in_transit": return .submitted
                    default:                     return .draft
                    }
                }()
                return VGMLedgerRow(
                    id: number,
                    containerNumber: formatContainer(number),
                    status: status,
                    vgmKg: nil,
                    method: nil,
                    cutoffNote: status == .submitted ? "VGM on file at load" : "awaiting verified gross mass")
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Submit VGM

    private func submitVGM() async {
        guard declarationComplete,
              let vgm = computedVGM,
              let container = headerContainer,
              let number = container.containerNumber,
              number.isEmpty == false else { return }
        submitting = true; submitNote = nil; submitError = nil
        defer { submitting = false }
        struct VGMIn: Encodable {
            let shipmentId: Int?
            let containerId: Int?
            let containerNumber: String?
            let vgmKg: Int
            let tareKg: Int?
            let cargoKg: Int?
            let method: String
            let signatoryName: String?
            let notes: String?
        }
        struct VGMOut: Decodable {
            let success: Bool
            let eventId: Int?
            let shipmentId: Int?
            let containerId: Int?
            let containerNumber: String?
            let vgmKg: Int?
            let method: String?
            let submittedAt: String?
        }
        do {
            let out: VGMOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.submitVgmDeclaration",
                input: VGMIn(
                    shipmentId: container.assignedShipmentId,
                    containerId: container.id,
                    containerNumber: number,
                    vgmKg: vgm,
                    tareKg: computedTare,
                    cargoKg: computedCargo,
                    method: method.apiValue,
                    signatoryName: session.user?.name,
                    notes: "SOLAS VI/2 VGM submitted from Vessel VGM Declaration"
                )
            )
            guard out.success else {
                submitError = "VGM was not accepted by the server."
                return
            }
            let filedKg = out.vgmKg ?? vgm
            rows = rows.map { row in
                guard row.id == number else { return row }
                return VGMLedgerRow(
                    id: row.id,
                    containerNumber: row.containerNumber,
                    status: .submitted,
                    vgmKg: filedKg,
                    method: method,
                    cutoffNote: out.eventId.map { "VGM event #\($0)" } ?? "VGM submitted"
                )
            }
            submitNote = "VGM submitted for \(formatContainer(out.containerNumber ?? number)) · \(filedKg.formatted(.number.grouping(.automatic))) kg · \(method.shortLabel)."
        } catch {
            submitError = error.eusoUserCopy
        }
    }
}

#Preview("738 · Vessel VGM Declaration · Night") {
    VesselVGMDeclarationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("738 · Vessel VGM Declaration · Light") {
    VesselVGMDeclarationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
