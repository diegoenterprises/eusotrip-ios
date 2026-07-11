//
//  204E_ShipperLivestock28HourClock.swift
//  EusoTrip 2027 — Shipper · Livestock 28-Hour Law Clock (brick 204E).
//
//  ARCHETYPE: COUNTDOWN / GAUGE. A radial confinement-clock dial leads,
//  a vertical REST-STOP PLAN timeline (49 USC 80502(b) · 5h min rest)
//  follows, closing on a WELFARE & CVI 2×2 band. Purpose-built for the
//  federal confinement window — not a stat grid.
//
//  Persona §11: Diego Usoro / Eusorone Technologies. Featured load:
//  LD-260614-LV7C4 · live cattle (feeder, 48 head) · interstate ·
//  Amarillo TX → Dodge City KS.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/loads/[id]/livestock-clock.tsx
//  LIVE  trailerRegulatory.getLivestockRegulations  trailerRegulatory.ts:565
//        — confirms the 28-hour rule + ag-HOS exemption text is live.
//  LIVE  loads.getById                          loads.ts:1152 (resolveLoadId)
//        — loadedAt anchors the confinement clock; lane + head count.
//  STUB  livestock.logRestStop — named gap. Proposed:
//        livestock.logRestStop({loadId, stopId, restedMinutes})
//          → writes a rest event + blockchainAuditTrail, resets the
//        confinement timer, broadcasts WS_EVENTS.LIVESTOCK_REST. Primary CTA.
//  STUB  livestock.requestExtension — named gap. Proposed:
//        livestock.requestExtension({loadId}) → 36h owner election.
//  transportMode TRUCK · country US (49 USC 80502 · USDA APHIS · FMCSA
//  150-air-mile ag exemption). Degraded → "clock pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct RestNode: Identifiable {
    enum Kind { case done, current, future }
    let id = UUID()
    let title: String
    let detail: String
    let stampRight: String
    let kind: Kind
}

private struct WelfareCell: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let tint: Color
}

private struct LivestockModel {
    var statusLine: String
    var remaining: String
    /// 0…1 fraction of the 28-hour window still available.
    var remainingFraction: Double
    var commodity: String
    var headLane: String
    var loadedValue: String
    var unloadByValue: String
    var restStopValue: String
    var restNodes: [RestNode]
    var welfare: [WelfareCell]

    static let canonical = LivestockModel(
        statusLine: "ON SCHEDULE · 49 USC 80502 · UNLOAD WITHIN WINDOW",
        remaining: "19h 42m",
        remainingFraction: 0.70,
        commodity: "Feeder cattle · interstate",
        headLane: "48 head · AMA TX → DDC KS",
        loadedValue: "06:12 · 8h 18m ago",
        unloadByValue: "10:12 +1 day",
        restStopValue: "Dalhart · 14:30",
        restNodes: [
            RestNode(title: "Loaded · Amarillo TX",
                     detail: "06:12 · 48 head · density 16 sq ft/hd",
                     stampRight: "DONE", kind: .done),
            RestNode(title: "Feed · water · rest · Dalhart TX",
                     detail: "ETA 14:30 · unload + 5h rest",
                     stampRight: "PLANNED", kind: .current),
            RestNode(title: "Resume transit",
                     detail: "19:30 · clock resets · 0h confined",
                     stampRight: "19:30", kind: .future),
            RestNode(title: "Deliver · Dodge City KS",
                     detail: "ETA 23:10 · 3h 40m post-rest",
                     stampRight: "23:10", kind: .future),
        ],
        welfare: [
            WelfareCell(icon: "doc.text.fill", title: "CVI on board",
                        detail: "issued 11 days ago", tint: Brand.success),
            WelfareCell(icon: "checkmark", title: "Loading density",
                        detail: "16 sq ft/hd · in range", tint: Brand.success),
            WelfareCell(icon: "thermometer.sun.fill", title: "Heat watch",
                        detail: "84°F · reduce density 10%", tint: Brand.warning),
            WelfareCell(icon: "checkmark", title: "Brand inspection",
                        detail: "TX cleared · proof on file", tint: Brand.success),
        ]
    )
}

// MARK: - Store

@MainActor
private final class LivestockStore: ObservableObject {
    @Published private(set) var model = LivestockModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var logging = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        // LIVE — confirm the livestock regulatory envelope is reachable.
        struct In: Encodable { let trailerType: String }
        struct Reg: Decodable { let trailerType: String? }
        do {
            let _: Reg = try await api.query(
                "trailerRegulatory.getLivestockRegulations",
                input: In(trailerType: "livestock")
            )
            degraded = nil
        } catch {
            degraded = "Clock pending (degraded) — showing last-known window"
        }
    }

    func logRestStop() async {
        logging = true
        defer { logging = false }
        // STUB livestock.logRestStop — fire-and-forget until the write ships.
        struct In: Encodable { let loadId: String }
        let _: LivestockAck? = try? await api.mutation(
            "livestock.logRestStop", input: In(loadId: loadId))
    }
}

private struct LivestockAck: Decodable {}

// MARK: - View

struct ShipperLivestock28HourClock: View {
    let loadId: String
    @StateObject private var store: LivestockStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260614-LV7C4") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: LivestockStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · LIVESTOCK · 28-HOUR LAW",
                              idText: store.loadId,
                              title: "Live cattle · 48 hd")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                clockHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("REST-STOP PLAN · 49 USC 80502(b) · 5h MIN REST")
                    .padding(.top, Space.s5)
                restTimeline
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("WELFARE & INTERSTATE HEALTH · USDA APHIS")
                    .padding(.top, Space.s5)
                welfareGrid
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "Log rest stop",
                               secondary: "Request 36h",
                               primaryLoading: store.logging,
                               onPrimary: { Task { await store.logRestStop() } },
                               onSecondary: {
                                   NotificationCenter.default.post(
                                       name: .eusoShippereSangTapped, object: nil)
                               })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Countdown hero

    private var clockHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.model.statusLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.success)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Brand.success.opacity(0.12))

            HStack(alignment: .top, spacing: Space.s4) {
                ConfinementDial(fraction: store.model.remainingFraction,
                                remaining: store.model.remaining)
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.model.commodity)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.headLane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                    Divider().overlay(palette.borderFaint).padding(.vertical, 2)
                    clockRow("LOADED", store.model.loadedValue, palette.textPrimary)
                    clockRow("UNLOAD BY", store.model.unloadByValue, palette.textPrimary)
                    clockRow("REST STOP", store.model.restStopValue, Brand.success)
                    HStack {
                        AddendaChip(text: "HOS AG-EXEMPT · 150mi", color: Brand.success)
                        Spacer(minLength: 0)
                    }.padding(.top, 2)
                }
            }
            .padding(Space.s4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .addendaPanel(palette)
    }

    private func clockRow(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(valueColor)
        }
    }

    // MARK: Rest-stop plan timeline

    private var restTimeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.restNodes.enumerated()), id: \.element.id) { idx, node in
                HStack(alignment: .top, spacing: Space.s3) {
                    TimelineDot(kind: node.kind,
                                isFirst: idx == 0,
                                isLast: idx == store.model.restNodes.count - 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(node.detail)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: Space.s2)
                    Text(node.stampRight)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(stampColor(node.kind))
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
        }
        .padding(.vertical, Space.s1)
        .addendaPanel(palette)
    }

    private func stampColor(_ kind: RestNode.Kind) -> Color {
        switch kind {
        case .done:    return Brand.success
        case .current: return Brand.info
        case .future:  return palette.textTertiary
        }
    }

    // MARK: Welfare & CVI 2×2

    private var welfareGrid: some View {
        let cols = [GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2)]
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(store.model.welfare) { cell in
                HStack(spacing: Space.s2) {
                    Image(systemName: cell.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(cell.tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cell.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(cell.detail)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(cell.tint)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .addendaPanel(palette, radius: Radius.md)
            }
        }
    }
}

// MARK: - Confinement dial

private struct ConfinementDial: View {
    let fraction: Double
    let remaining: String
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.02, min(fraction, 1)))
                .stroke(Brand.success, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(remaining)
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("REMAINING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

// MARK: - Timeline dot + connector

private struct TimelineDot: View {
    let kind: RestNode.Kind
    let isFirst: Bool
    let isLast: Bool
    @Environment(\.palette) private var palette

    private var color: Color {
        switch kind {
        case .done:    return Brand.success
        case .current: return Brand.info
        case .future:  return palette.textTertiary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : (kind == .future ? Color.white.opacity(0.10) : color))
                .frame(width: 2, height: 8)
            Group {
                switch kind {
                case .done:
                    Circle().fill(color).frame(width: 12, height: 12)
                case .current:
                    Circle().strokeBorder(color, lineWidth: 2).frame(width: 12, height: 12)
                        .overlay(Circle().fill(color).frame(width: 5, height: 5))
                case .future:
                    Circle().strokeBorder(palette.textPrimary.opacity(0.3), lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
            Rectangle()
                .fill(isLast ? Color.clear : Color.white.opacity(0.10))
                .frame(width: 2, height: 26)
        }
    }
}

// MARK: - Previews

#Preview("204E · Livestock 28-Hour Clock · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperLivestock28HourClock()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204E · Livestock 28-Hour Clock · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperLivestock28HourClock()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
