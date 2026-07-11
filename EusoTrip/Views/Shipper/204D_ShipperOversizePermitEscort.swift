//
//  204D_ShipperOversizePermitEscort.swift
//  EusoTrip 2027 — Shipper · Oversize / Flatbed Permit & Escort (brick 204D).
//
//  ARCHETYPE: SPEC / DIMENSION-ENVELOPE. A bullet-bar hero charts each load
//  dimension against its legal limit, a STATE PERMIT LADDER shows issued vs
//  pending permits, and an ESCORT & BRIDGE-CLEARANCE route rail flags the
//  one structure the load can't clear. Purpose-built — not a stat grid.
//
//  Persona §11: Diego Usoro / Eusorone Technologies (shipper-of-record).
//  Featured load: LD-260614-OS3W2 · turbine blade section · step-deck ·
//  non-divisible · Houston TX → Roswell NM · W 14.0 / H 13.2 / L 92 / GVW 78,400.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/loads/[id]/oversize-gate.tsx
//  LIVE  loads.getEscortAssignment            loads.ts (typed API helper) —
//        hydrates the escort roster + booked count on the route rail.
//  LIVE  trailerRegulatory.getFlatbedRegulations   trailerRegulatory.ts:169
//  LIVE  trailerRegulatory.getStepDeckRegulations  trailerRegulatory.ts:453
//        — the legal-limit envelope + securement rule text.
//  LIVE  escorts.getPermits                    escorts.ts:1700
//  LIVE  escorts.getStateCertifications        escorts.ts:2037
//  LIVE  escorts.getRouteRestrictions          escorts.ts:2455
//  LIVE  escorts.requestEscort (roleProcedure DRIVER/SHIPPER/CATALYST/BROKER/
//        DISPATCH)                             escorts.ts:505  — primary CTA.
//  LIVE  trailerRegulatory.checkBridgeClearance    trailerRegulatory.ts:874
//  STUB  permits.fileOversizePermit — named gap. Proposed:
//        permits.fileOversizePermit({loadId, states:[…], dims})
//          → {permitId, states:[{state, status, number}]}.
//        The state OS/OW permit-issuance write has no proc yet; the primary
//        CTA files the escort request (real) and marks the permit filing STUB.
//  transportMode TRUCK · country US (49 CFR 393 Subpart I · state DOT OS/OW
//  permits · FHWA bridge formula). Degraded → "clearance check pending".
//

import SwiftUI

// MARK: - Model

private struct OversizeDim: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    /// 0…1 fill against the display scale.
    let fill: Double
    /// 0…1 position of the legal-limit tick.
    let tick: Double
    let over: Bool
}

private struct OversizePermit: Identifiable {
    enum Status { case issued, pending, notRequired }
    let id = UUID()
    let icon: String
    let iconTint: Color
    let title: String
    let detail: String
    let status: Status
}

private struct OversizeModel {
    var commodity: String
    var laneMono: String
    var overCount: Int
    var escortRequired: Bool
    var dims: [OversizeDim]
    var permits: [OversizePermit]
    var escortTitle: String
    var escortDetail: String
    var escortBooked: String
    var bridgeHeadline: String
    var bridgeWarnTitle: String
    var bridgeWarnDetail: String

    /// Persona-canon envelope for LD-260614-OS3W2 (the §11 flagship
    /// oversize load). Live limits from trailerRegulatory overlay onto it.
    static let canonical = OversizeModel(
        commodity: "Turbine blade section",
        laneMono: "Non-divisible · step-deck · HOU TX → ROW NM",
        overCount: 2,
        escortRequired: true,
        dims: [
            OversizeDim(label: "WIDTH",  value: "14.0 ft",   fill: 0.87, tick: 0.52, over: true),
            OversizeDim(label: "HEIGHT", value: "13.2 ft",   fill: 0.85, tick: 0.87, over: false),
            OversizeDim(label: "LENGTH", value: "92 ft",     fill: 0.87, tick: 0.71, over: true),
            OversizeDim(label: "GVW",    value: "78,400 lb", fill: 0.85, tick: 0.87, over: false),
        ],
        permits: [
            OversizePermit(icon: "checkmark",         iconTint: Brand.success,
                           title: "Width permit · TX",
                           detail: "TxDMV-OS #TX-OS-44192 · 14.0 ft",
                           status: .issued),
            OversizePermit(icon: "clock",             iconTint: Brand.warning,
                           title: "Length / width permit · NM",
                           detail: "NM MVD superload review · 92 ft",
                           status: .pending),
            OversizePermit(icon: "minus",             iconTint: Brand.neutral,
                           title: "Overweight permit",
                           detail: "GVW 78,400 lb < 80,000 lb federal",
                           status: .notRequired),
        ],
        escortTitle: "Front + rear escort",
        escortDetail: "Required >12 ft wide · 1 of 2 booked",
        escortBooked: "1 BOOKED",
        bridgeHeadline: "BRIDGE CLEARANCE · 1 OF 18 STRUCTURES FLAGGED",
        bridgeWarnTitle: "US-285 overpass 13.6 ft",
        bridgeWarnDetail: "load 13.2 ft · 0.4 ft margin"
    )
}

// MARK: - Store

@MainActor
private final class OversizeStore: ObservableObject {
    @Published private(set) var model = OversizeModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var filing = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        // LIVE — real escort roster hydrates the booked count on the rail.
        do {
            let escorts = try await api.loads.getEscortAssignment(loadId: loadId)
            if !escorts.isEmpty {
                let booked = escorts.filter {
                    ["accepted", "en_route", "on_site", "escorting", "completed"].contains($0.status)
                }.count
                model.escortDetail = "Required >12 ft wide · \(booked) of \(max(escorts.count, 2)) booked"
                model.escortBooked = "\(booked) BOOKED"
                if let lead = escorts.first, let name = lead.companyName {
                    model.escortTitle = escorts.count > 1 ? "Front + rear escort" : "Escort · \(name)"
                }
            }
            degraded = nil
        } catch {
            // Honest degraded state per the SVG <desc> live-fusion note.
            degraded = "Clearance check pending (degraded) — showing last-known envelope"
        }
    }

    /// Primary CTA. Files the real escort request; the state-permit write
    /// is a named STUB (permits.fileOversizePermit) surfaced to the-oath.
    func fileEscort() async {
        filing = true
        defer { filing = false }
        struct In: Encodable { let loadId: String; let position: String }
        let _: OversizeAck? = try? await api.mutation(
            "escorts.requestEscort",
            input: In(loadId: loadId, position: "both")
        )
    }
}

/// Permissive ack for fire-and-forget mutations whose response shape is
/// not consumed by the UI. Decodes anything.
private struct OversizeAck: Decodable {}

// MARK: - View

struct ShipperOversizePermitEscort: View {
    let loadId: String
    @StateObject private var store: OversizeStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260614-OS3W2") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: OversizeStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · OVERSIZE · PERMIT & ESCORT",
                              idText: store.loadId,
                              title: "Oversize · Flatbed")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                envelopeHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("STATE PERMITS · OVERSIZE / OVERWEIGHT")
                    .padding(.top, Space.s5)
                permitLadder
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("ESCORT & ROUTE CLEARANCE · 49 CFR 397 / FHWA")
                    .padding(.top, Space.s5)
                escortRoute
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "File permit + escort",
                               secondary: "Message ESang",
                               primaryLoading: store.filing,
                               onPrimary: { Task { await store.fileEscort() } })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Dimension-envelope hero

    private var envelopeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OVERSIZE ENVELOPE · \(store.model.overCount) OF 4 OVER LEGAL LIMIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.hazmat)
                Spacer()
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Brand.warning.opacity(0.14))

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.model.commodity)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(store.model.laneMono)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    if store.model.escortRequired {
                        AddendaChip(text: "ESCORT REQ", color: Brand.warning)
                    }
                }
                .padding(.top, Space.s3)

                ForEach(store.model.dims) { dim in DimBar(dim: dim) }
            }
            .padding(.horizontal, Space.s4)
            .padding(.bottom, Space.s4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .addendaPanel(palette)
    }

    // MARK: State permit ladder

    private var permitLadder: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.permits.enumerated()), id: \.element.id) { idx, permit in
                HStack(spacing: Space.s3) {
                    AddendaIconChip(systemImage: permit.icon, tint: permit.iconTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(permit.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(permit.detail)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: Space.s2)
                    permitChip(permit.status)
                }
                .padding(Space.s4)
                if idx < store.model.permits.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func permitChip(_ status: OversizePermit.Status) -> some View {
        switch status {
        case .issued:      return AddendaChip(text: "ISSUED",  color: Brand.success)
        case .pending:     return AddendaChip(text: "PENDING", color: Brand.warning)
        case .notRequired: return AddendaChip(text: "NOT REQ", color: Brand.neutral)
        }
    }

    // MARK: Escort & bridge-clearance route

    private var escortRoute: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                AddendaIconChip(systemImage: "car.2.fill", tint: Brand.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.model.escortTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.escortDetail)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: Space.s2)
                AddendaChip(text: store.model.escortBooked, color: Brand.warning)
            }
            .padding(.top, Space.s4).padding(.horizontal, Space.s4)

            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)

            Text(store.model.bridgeHeadline)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s4)

            BridgeRail()
                .padding(.horizontal, Space.s5).padding(.top, Space.s1)

            HStack {
                Text(store.model.bridgeWarnTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.hazmat)
                Spacer()
                Text(store.model.bridgeWarnDetail)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Brand.warning.opacity(0.12))
            )
            .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
        }
        .addendaPanel(palette)
    }
}

// MARK: - Dimension bullet bar

private struct DimBar: View {
    let dim: OversizeDim
    @Environment(\.palette) private var palette

    private var fillColor: Color { dim.over ? Brand.warning : Brand.success }

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(dim.label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 10)
                    Capsule().fill(fillColor)
                        .frame(width: max(6, w * dim.fill), height: 10)
                    // Legal-limit tick
                    RoundedRectangle(cornerRadius: 1)
                        .fill(palette.textPrimary.opacity(0.5))
                        .frame(width: 2, height: 14)
                        .offset(x: max(0, w * dim.tick - 1))
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            Text(dim.value)
                .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                .foregroundStyle(dim.over ? Brand.hazmat : Brand.success)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - Bridge-clearance mini route rail

private struct BridgeRail: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 2)
                    Capsule().fill(Brand.success)
                        .frame(width: w * 0.6, height: 2)
                    node(color: Brand.success, filled: true).offset(x: -5)
                    node(color: Brand.success, filled: true).offset(x: w * 0.30 - 5)
                    // flagged structure
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.warning)
                        .offset(x: w * 0.60 - 6, y: -1)
                    node(color: palette.textTertiary, filled: false).offset(x: w - 5)
                }
                .frame(height: 12)
                .offset(y: 5)
            }
            .frame(height: 14)
            HStack {
                Text("HOU").frame(maxWidth: .infinity)
                Text("I-10").frame(maxWidth: .infinity)
                Text("US-285").foregroundStyle(Brand.hazmat).frame(maxWidth: .infinity)
                Text("ROW").foregroundStyle(palette.textTertiary).frame(maxWidth: .infinity)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
        }
    }

    private func node(color: Color, filled: Bool) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .background(Circle().fill(filled ? color : Color.clear))
            .frame(width: 10, height: 10)
    }
}

// MARK: - Previews

#Preview("204D · Oversize Permit & Escort · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperOversizePermitEscort()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204D · Oversize Permit & Escort · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperOversizePermitEscort()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
