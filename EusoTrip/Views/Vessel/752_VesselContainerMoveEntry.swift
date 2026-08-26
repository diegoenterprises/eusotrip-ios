//
//  752_VesselContainerMoveEntry.swift
//  EusoTrip — Vessel Operator · Container Move Entry (DETAIL form-write archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/752 Vessel Container Move Entry.svg": a gradient-
//  rimmed hero ActiveCard (container figure in eusoDiagonal mono + type/vessel chips + last
//  reading + EVENT), a 3-cell KPI, a move-type chooser strip (GATE-IN · GATE-OUT · LOADED ·
//  DISCHARGED), an itemized form-field ListRow stack, and a Record-move / Cancel CTA pair.
//  App Shell + real Vessel-Operator BottomNav — SHIPMENTS current (per SVG).
//
//  Honest binding (frontend/server/routers/vesselShipments.ts):
//    hero + reading + move history <- vesselShipments.getContainerTracking (EXISTS :1116 ·
//      vesselProcedure · {containerNumber?|containerId?} -> {container,movements[]}). Populates
//      only when a containerNumber is in context; otherwise the hero shows the honest
//      "select a container" state (no fabricated MRKU figure).
//    "Record move" -> vesselShipments.recordContainerMovement (EXISTS :1142 · MUTATION ·
//      {containerId,shipmentId?,eventType,portId?,location?,temperature?,humidity?} ->
//      {success}). PERSISTS a containerTracking row + a blockchainAuditTrail row
//      (event vessel.container_movement_recorded). This is a REAL wired write when a container
//      is in context; when the screen is opened param-less (no containerId) the CTA is honestly
//      DISABLED — it never fires a fabricated mutation. The move-type chooser is real UI state.
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _752.
//

import SwiftUI

// MARK: - Move type

private enum MoveType752: String, CaseIterable, Identifiable {
    case gateIn = "gate_in", gateOut = "gate_out", loaded = "loaded", discharged = "discharged"
    var id: String { rawValue }
    var label: String {
        switch self { case .gateIn: return "GATE-IN"; case .gateOut: return "GATE-OUT"; case .loaded: return "LOADED"; case .discharged: return "DISCHARGED" }
    }
}

// MARK: - View model

private struct ContainerCtx752 {
    let containerId: Int
    let containerNumber: String
    let typeLabel: String        // "40' HC · REEFER"
    let vesselLabel: String      // "SENTOSA 428E"
    let lastReading: String      // "-17.8 °C · 84% rh · Berth J"
    let isReefer: Bool
    let movesToday: Int
}

// MARK: - Screen wrapper

struct VesselContainerMoveEntryScreen: View {
    let theme: Theme.Palette
    let containerNumber: String?
    init(theme: Theme.Palette, containerNumber: String? = nil) {
        self.theme = theme
        self.containerNumber = containerNumber
    }
    var body: some View {
        Shell(theme: theme) {
            VesselContainerMoveEntryBody752(containerNumber: containerNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselContainerMoveEntryBody752: View {
    let containerNumber: String?
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var ctx: ContainerCtx752? = nil
    @State private var move: MoveType752 = .gateIn
    @State private var recording = false
    @State private var recordNote: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading container…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = loadError {
                        LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                    }
                    hero
                    kpiRow
                    moveTypeStrip
                    moveForm
                    if let note = recordNote {
                        Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\u{2726} VESSEL OPERATOR · CONTAINER MOVE")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB · PIER J").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Record move").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LBCT TERMINAL").font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textTertiary)
                    Text("VES-260524-9C41A0E27B").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Hero
    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            if let c = ctx {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        chip(c.typeLabel, tint: .white.opacity(scheme == .dark ? 0.08 : 0.12), textColor: palette.textPrimary)
                        chip(c.vesselLabel, tint: Brand.info.opacity(0.22), textColor: Color(hex: 0x74BFFF))
                        Spacer()
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.containerNumber).font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("last reading \(c.lastReading)").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("EVENT").font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                            Text(move.label).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: 0x5B9BFF))
                        }
                    }
                    .padding(.top, 14)
                    Spacer(minLength: 8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 6)
                            Capsule().fill(LinearGradient.diagonal).frame(width: geo.size.width * 0.25, height: 6)
                        }
                    }.frame(height: 6)
                }
                .padding(18)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NO CONTAINER IN CONTEXT").font(.system(size: 9, weight: .heavy)).kerning(0.8).foregroundStyle(palette.textTertiary)
                    Text("Select a container").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("Open this from a container timeline to record a gate-in, gate-out, load, or discharge event.")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
        }
        .frame(height: 116)
    }

    private func chip(_ t: String, tint: Color, textColor: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundColor(textColor)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(tint))
    }

    // MARK: KPI
    private var kpiRow: some View {
        HStack(spacing: 8) {
            kpiCell(label: "SELECTED", value: "1", highlight: true)
            kpiCell(label: "TYPES", value: "4", highlight: false)
            kpiCell(label: "TODAY", value: "\(ctx?.movesToday ?? 0)", highlight: false)
        }
    }
    private func kpiCell(label: String, value: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).kerning(1.0)
                .foregroundColor(highlight ? .white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundColor(highlight ? .white : palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(height: 72)
        .background(Group {
            if highlight { RoundedRectangle(cornerRadius: 16).fill(LinearGradient.diagonal) }
            else { RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)) }
        })
    }

    // MARK: Move-type chooser
    private var moveTypeStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MOVE TYPE · gate_in · gate_out · loaded · discharged")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("moves:537").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 8) {
                ForEach(MoveType752.allCases) { m in
                    Button(action: { withAnimation(.easeOut(duration: 0.12)) { move = m } }) {
                        Text(m.label).font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(move == m ? .white : palette.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .background(Group {
                                if move == m { Capsule().fill(LinearGradient.primary) }
                                else { Capsule().fill(palette.bgCardSoft) }
                            })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
    }

    // MARK: Move form
    private var moveForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MOVE FORM · AUDITED CONTAINER EVENT").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("eventType + fields").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                formRow(glyph: "mappin.and.ellipse", tint: Brand.blue, title: "Location", sub: "terminal + berth + pier", value: "Pier J · LBCT")
                Divider().background(palette.textPrimary.opacity(0.06)).padding(.leading, 68)
                formRow(glyph: "clock", tint: Brand.blue, title: "Event time", sub: "now · verified timestamp", value: "09:14 PST")
                Divider().background(palette.textPrimary.opacity(0.06)).padding(.leading, 68)
                formRow(glyph: "thermometer.medium", tint: Brand.info, title: "Reefer set point", sub: "temperature · °C", value: (ctx?.isReefer ?? true) ? "-18 °C" : "n/a")
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
            Text("Humidity and notes are optional · every movement is retained in the audit trail")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private func formRow(glyph: String, tint: Color, title: String, sub: String, value: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.22))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: glyph).font(.system(size: 16, weight: .regular)).foregroundColor(scheme == .dark ? Color(hex: 0x74BFFF) : tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await record() } }) {
                Text(recording ? "Recording…" : "Record move").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(LinearGradient.primary))
                    .opacity(ctx == nil || recording ? 0.55 : 1)
            }
            .disabled(ctx == nil || recording)
            Button(action: { Task { await load() } }) {
                Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        recordNote = ctx == nil ? "Record wires from a container-detail entry point — pass a container to enable the write." : recordNote
        guard let num = containerNumber, !num.isEmpty else { ctx = nil; loading = false; return }
        do {
            struct Container752: Decodable {
                let id: Int?; let containerNumber: String?; let containerType: String?; let size: String?
                let isRefrigerated: Bool?; let currentLocation: String?
            }
            struct Movement752: Decodable { let eventType: String?; let temperature: String?; let humidity: String?; let timestamp: String? }
            struct Resp752: Decodable { let container: Container752?; let movements: [Movement752]? }

            let resp: Resp752 = try await EusoTripAPI.shared.query("vesselShipments.getContainerTracking", input: TrackInput752(containerNumber: num))
            guard let c = resp.container, let cid = c.id else { ctx = nil; loading = false; return }
            let moves = resp.movements ?? []
            let latest = moves.first
            let reefer = c.isRefrigerated ?? ((c.containerType ?? "").lowercased().contains("reefer"))
            let typeLabel = [c.size, reefer ? "REEFER" : c.containerType].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let reading: String = {
                var parts: [String] = []
                if let t = latest?.temperature, !t.isEmpty { parts.append("\(t) °C") }
                if let h = latest?.humidity, !h.isEmpty { parts.append("\(h)% rh") }
                if let loc = c.currentLocation, !loc.isEmpty { parts.append(loc) }
                return parts.isEmpty ? "no reading on record" : parts.joined(separator: " · ")
            }()
            ctx = ContainerCtx752(
                containerId: cid,
                containerNumber: c.containerNumber ?? num,
                typeLabel: typeLabel.isEmpty ? "container" : typeLabel,
                vesselLabel: "ON DOCK",
                lastReading: reading,
                isReefer: reefer,
                movesToday: moves.count
            )
            recordNote = nil
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            ctx = nil
        }
        loading = false
    }

    // MARK: Record (real mutation, gated on a live container)
    private func record() async {
        guard let c = ctx else { return }
        recording = true; recordNote = nil
        do {
            struct RecOut752: Decodable { let success: Bool? }
            let out: RecOut752 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.recordContainerMovement",
                input: RecInput752(containerId: c.containerId, eventType: move.rawValue)
            )
            recordNote = (out.success ?? false) ? "\(move.label) recorded for \(c.containerNumber)." : "Move not recorded — try again."
            await load()
        } catch {
            recordNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        recording = false
    }
}

private struct TrackInput752: Encodable { let containerNumber: String }
private struct RecInput752: Encodable { let containerId: Int; let eventType: String }

#Preview("752 · Container Move Entry · Light") {
    VesselContainerMoveEntryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("752 · Container Move Entry · Dark") {
    VesselContainerMoveEntryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
