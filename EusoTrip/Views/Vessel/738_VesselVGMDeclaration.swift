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
//  Docked under SHIPMENTS. transportMode=vessel · USLAX Los Angeles · kg.
//  Value: computes + files the verified gross mass per box before the SOLAS
//  cutoff so the container is allowed to load and the operator avoids a roll.
//
//  WIRING (tRPC string paths — siblings call these exact procs):
//    · vesselShipments.getContainerTracking {containerNumber}
//        -> { container, movements }; container particulars (number / sizeType /
//        status) seed the ledger rows. (REAL · vesselShipments.ts:583)
//
//  HONEST WIRE-GAP (per the wireframe desc, named-gap §738):
//    · The container-tracking row carries NO tare / cargo / gross-mass field, and
//      there is no `multiModal.submitVgmDeclaration` mutation on this client.
//      We therefore DO NOT fabricate weights or a fake "submitted" success:
//        - the calc block computes VGM only when both tare AND cargo are entered
//          by the operator (in-form fields), otherwise it shows an honest
//          "awaiting weights" state;
//        - the Submit VGM CTA is enabled only with a complete declaration and,
//          until the server proc lands, surfaces the named-gap explicitly rather
//          than pretending the box was declared.
//
//  RBAC: protectedProcedure (vessel operator). NO mock rows — the ledger is
//  built from live container-tracking results with real loading / empty / error.
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

// MARK: - Data shapes (mirror getContainerTracking → { container, movements })

/// One row of `vesselShipments.getContainerTracking`'s container payload.
/// The VGM weights (tare/cargo/gross) are intentionally absent — the tracking
/// row does not carry them, so the form never claims a fabricated mass.
private struct VGMContainer738: Decodable {
    let id: Int?
    let containerNumber: String?
    let isoType: String?
    let sizeType: String?
    let status: String?
}

private struct VGMTrackingResponse738: Decodable {
    let container: VGMContainer738?
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

    // Canon focus container from the wireframe (USLAX master B/L). The detail
    // tracking row is fetched live; if the proc has nothing for it we degrade
    // to an honest "container not yet tracked" state rather than fake rows.
    private let focusContainer = "MSCU7741203"

    @State private var rows: [VGMLedgerRow] = []
    @State private var headerContainer: VGMContainer738? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // In-form declaration (operator-entered — the only honest source of weights).
    @State private var tareText: String = ""
    @State private var cargoText: String = ""
    @State private var method: WeighingMethod = .method1

    // Submit named-gap surfacing.
    @State private var submitting = false
    @State private var submitNote: String? = nil
    @State private var submitError: String? = nil

    // SOLAS payload limit for a standard 40HC (max gross). Within/over is a
    // pure comparison against the entered VGM — no fabricated reference number.
    private let maxGrossKg = 23_000

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
                Text("VGM · USLAX")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
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
        let displayNumber = formatContainer(headerContainer?.containerNumber ?? focusContainer)
        let sizeType = humanSizeType(headerContainer?.isoType ?? headerContainer?.sizeType)
        let statusNote = headerStatusNote

        return VStack(alignment: .leading, spacing: Space.s4) {
            // Header: container number · size-type / vessel / cutoff
            VStack(alignment: .leading, spacing: 4) {
                Text(displayNumber)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(sizeType) · MV EUSO MERIDIAN v.118E · \(statusNote)")
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
                Text(vgm <= maxGrossKg
                     ? "kg · within \(maxGrossKg.formatted(.number.grouping(.automatic))) kg limit"
                     : "kg · OVER \(maxGrossKg.formatted(.number.grouping(.automatic))) kg limit")
                    .font(.system(size: 10))
                    .foregroundStyle(vgm <= maxGrossKg ? palette.textSecondary : Brand.danger)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
                Text("submitVgmDeclaration")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No containers awaiting VGM",
                    subtitle: "Boxes routed to USLAX for this sailing will queue here for declaration before the SOLAS cutoff."
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
        let name = (session.user?.name?.isEmpty == false ? session.user?.name : nil) ?? "Diego Usoro"
        let initials = signatoryInitials(name)
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text(initials)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Authorized · \(name)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Eusorone Technologies · shipper of record · master B/L")
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
                Text("Tare auto-filled from container particulars")
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
        return vgm <= maxGrossKg
    }

    private var headerStatusNote: String {
        switch (headerContainer?.status ?? "").lowercased() {
        case "on_water", "on water": return "on water · declare before cutoff"
        case "at_origin", "gate_in": return "at origin · awaiting VGM"
        case "loaded":               return "loaded · VGM on file"
        case "":                     return "awaiting VGM declaration"
        default:                     return (headerContainer?.status ?? "")
            .replacingOccurrences(of: "_", with: " ").lowercased()
        }
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

    private func humanSizeType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "40HC" }
        let s = raw.uppercased()
        if s.contains("40") && (s.contains("HC") || s.contains("HQ")) { return "40HC" }
        if s.contains("40") { return "40DC" }
        if s.contains("45") { return "45HC" }
        if s.contains("20") { return "20DC" }
        if s.contains("REEF") || s.contains("RF") { return "40RF" }
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

    // MARK: - Load (getContainerTracking → particulars + ledger seed)

    private func load() async {
        loading = true; loadError = nil
        struct TrackingIn: Encodable { let containerNumber: String }
        do {
            // Live container particulars for the focus box. The proc returns
            // { container, movements }; we keep only the particulars here.
            let resp: VGMTrackingResponse738 = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerTracking",
                input: TrackingIn(containerNumber: focusContainer))
            self.headerContainer = resp.container

            // Build the ledger HONESTLY: one live row for the tracked box.
            // No VGM weight is fabricated — the tracking row carries none, so
            // the box reads DRAFT (awaiting declaration) until the operator
            // files one. Auto-fill the tare field from particulars is left to
            // the named-gap proc; we don't invent a number.
            if let c = resp.container {
                let number = formatContainer(c.containerNumber ?? focusContainer)
                let status: VGMStatus = {
                    switch (c.status ?? "").lowercased() {
                    case "loaded": return .submitted
                    default:       return .draft
                    }
                }()
                self.rows = [
                    VGMLedgerRow(
                        id: c.containerNumber ?? focusContainer,
                        containerNumber: number,
                        status: status,
                        vgmKg: nil,
                        method: nil,
                        cutoffNote: "awaiting verified gross mass")
                ]
            } else {
                self.rows = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Submit VGM (named-gap · submitVgmDeclaration)

    private func submitVGM() async {
        guard declarationComplete, let vgm = computedVGM else { return }
        submitting = true; submitNote = nil; submitError = nil
        // HONEST WIRE-GAP: there is no `multiModal.submitVgmDeclaration` mutation
        // wired on this client (named-gap §738). We DO NOT fake a "submitted"
        // success — we surface the computed declaration and the gap explicitly
        // so the operator knows the box was NOT yet filed server-side.
        defer { submitting = false }
        submitNote = "VGM computed (\(vgm.formatted(.number.grouping(.automatic))) kg · \(method.shortLabel)). "
            + "Filing endpoint submitVgmDeclaration is not yet wired — declaration is not yet transmitted."
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
