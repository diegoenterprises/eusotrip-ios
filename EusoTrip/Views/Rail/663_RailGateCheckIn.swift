//
//  663_RailGateCheckIn.swift
//  EusoTrip — Rail Engineer · Gate Check-In (Dark + Light · verbatim port of
//  "05 Rail / 663 Rail Gate Check-In.svg").
//
//  ARCHETYPE = GATE-LANE CONSOLE: a live lane-board hero (GATE OPEN pill + a
//  row of lane tiles reading IN / OUT / OPEN with an inline IN-today /
//  OUT-today / avg-turn flow line — never one big stat), a GATE QUEUE live
//  feed of the last gate moves (flow-arrow chip + container + lane/appt mono
//  sub + IN/OUT pill + timestamp), a tri-country credential band, and a
//  Check-in / Check-out CTA pair.
//
//  WIRING (grep-confirmed · frontend/server/routers):
//    • lane board + queue → railGate.getGateActivity (query · railGate.ts:102)
//        input { windowHours, limit }; { events[{ railcarNumber, gateType,
//        site, occurredAt, anomaly }], counts{ gateIn, gateOut, flags },
//        avgTurnMinutes }. Lane tiles derive from the most recent moves.
//    • Check-in            → yardManagement.checkInTrailer  (mutation · :823)
//    • Check-out           → yardManagement.checkOutTrailer (mutation · :897)
//    HONEST NOTE: check-in/out commit through a location + trailer + seal
//    intake; this monitor surfaces the next queued container and the commit
//    endpoint rather than firing with a fabricated locationId. Tri-country
//    credential band (US TWIC · CA FAST · MX CTPAT) is a presentation toggle
//    pending the per-country gate data source (handed to the-oath).
//
//  RBAC: protectedProcedure. transportMode=rail · US domestic.
//  NAV (RailEngineerNavController): current = SHIPMENTS.
//

import SwiftUI

struct RailGateCheckInScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailGateCheckInBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodables (railGate.getGateActivity)

private struct GateEvent663: Decodable, Identifiable {
    let id: String
    let railcarNumber: String?
    let trainId: String?
    let gateType: String       // gate_in | gate_out | flag
    let site: String?
    let anomaly: Bool
    let occurredAt: String?
}
private struct GateCounts663: Decodable {
    let gateIn: Int
    let gateOut: Int
    let flags: Int
}
private struct GateActivity663: Decodable {
    let events: [GateEvent663]?
    let counts: GateCounts663?
    let avgTurnMinutes: Int?
}

private enum GateCredential663: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var title: String { self == .us ? "US · TWIC" : (self == .ca ? "CA · FAST" : "MX · CTPAT") }
    var sub: String { self == .us ? "SCAC · driver ID" : (self == .ca ? "CBSA · driver ID" : "VUCEM · pedimento") }
}

// MARK: - Body

private struct RailGateCheckInBody: View {
    @Environment(\.palette) private var palette

    @State private var data: GateActivity663? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var credential: GateCredential663 = .us
    @State private var ack: String? = nil

    private var events: [GateEvent663] { data?.events ?? [] }
    private var counts: GateCounts663? { data?.counts }

    private struct Lane: Identifiable { let id: Int; let dir: String } // IN/OUT/OPEN

    /// Six lane tiles derived from the most recent gate moves — real activity,
    /// padded with OPEN lanes when the window has fewer than six moves.
    private var lanes: [Lane] {
        var out: [Lane] = []
        let recent = Array(events.prefix(6))
        for i in 0..<6 {
            if i < recent.count {
                let dir: String
                switch recent[i].gateType {
                case "gate_in":  dir = "IN"
                case "gate_out": dir = "OUT"
                default:          dir = "FLAG"
                }
                out.append(Lane(id: i + 1, dir: dir))
            } else {
                out.append(Lane(id: i + 1, dir: "OPEN"))
            }
        }
        return out
    }

    private var nextContainer: String? { events.first?.railcarNumber }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    laneBoard
                    gateQueue
                    credentialBand
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · GATE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("RAMP · ICTF-LGB")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Gate check-in")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
    }

    // MARK: Lane board hero

    private var laneBoard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("LIVE GATE · ICTF · LGB · 6 LANES")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Brand.success).frame(width: 6, height: 6)
                        Text("OPEN")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.success)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Brand.success.opacity(0.12)).clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    ForEach(lanes) { lane in
                        laneTile(lane)
                    }
                }

                HStack {
                    flowStat("IN today", "\(counts?.gateIn ?? 0)", Color(hex: 0x2BD9A4))
                    Spacer()
                    flowStat("OUT today", "\(counts?.gateOut ?? 0)", Brand.rail)
                    Spacer()
                    flowStat("avg turn", data?.avgTurnMinutes.map { "\($0)m" } ?? "—", palette.textPrimary)
                }
            }
        }
    }

    private func laneTile(_ lane: Lane) -> some View {
        let (color, bg): (Color, Color) = {
            switch lane.dir {
            case "IN":   return (Color(hex: 0x2BD9A4), Brand.success.opacity(0.12))
            case "OUT":  return (Brand.rail, Brand.rail.opacity(0.14))
            case "FLAG": return (Brand.danger, Brand.danger.opacity(0.14))
            default:      return (palette.textTertiary, Color.white.opacity(0.05))
            }
        }()
        return VStack(spacing: 5) {
            Text("L\(lane.id)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(lane.dir)
                .font(.system(size: 9, weight: .bold)).tracking(0.3)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func flowStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(color)
        }
    }

    // MARK: Gate queue feed

    private var gateQueue: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("GATE QUEUE · LIVE FEED")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if events.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "arrow.left.arrow.right"),
                    title: "No gate moves in the window",
                    subtitle: "The live feed streams gate-in / gate-out moves from railGate.getGateActivity.",
                    comingSoon: false
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(6).enumerated()), id: \.element.id) { idx, e in
                        queueRow(e)
                        if idx < min(events.count, 6) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                    if let next = nextContainer {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.vertical, Space.s3)
                        HStack(spacing: 6) {
                            Circle().fill(Brand.blue).frame(width: 8, height: 8)
                            Text("Next queued")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textSecondary)
                            Text(next)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func queueRow(_ e: GateEvent663) -> some View {
        let isIn = e.gateType == "gate_in"
        let flag = e.anomaly || e.gateType == "flag"
        let (color, label, icon): (Color, String, String) = {
            if flag { return (Brand.danger, "FLAG", "exclamationmark.triangle.fill") }
            if isIn { return (Color(hex: 0x2BD9A4), "IN", "arrow.right.to.line") }
            return (Brand.rail, "OUT", "arrow.up.right")
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.railcarNumber ?? "—")
                    .font(.system(size: 14, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Text("\(e.site ?? "gate")\(e.trainId != nil ? " · train \(e.trainId!)" : "")")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(color)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(color.opacity(0.14)).clipShape(Capsule())
                Text(shortTime(e.occurredAt))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Credential band

    private var credentialBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("GATE CHECK-IN · CREDENTIAL BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(GateCredential663.allCases) { c in
                    let active = c == credential
                    Button { credential = c } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(active ? Color.white : palette.textPrimary)
                            Text(c.sub)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(minHeight: 44)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { checkIn() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.to.line").font(.system(size: 13, weight: .bold))
                    Text("Check in").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)

            RailSecondaryActionButton(
                title: "Check out",
                sheetTitle: "Gate check-out",
                lines: [
                    "Endpoint: yardManagement.checkOutTrailer",
                    "IN today: \(counts?.gateIn ?? 0) · OUT today: \(counts?.gateOut ?? 0)",
                    "Avg turn: \(data?.avgTurnMinutes.map { "\($0)m" } ?? "—")",
                    "Commit needs: location + trailer + seal + driver",
                    nextContainer.map { "Last move: \($0)" } ?? "No recent moves"
                ],
                systemImage: "arrow.up.right"
            )
        }
    }

    private func checkIn() {
        if let next = nextContainer {
            ack = "Ready to gate \(next) (yardManagement.checkInTrailer) — commit with location + trailer + seal + driver on the intake."
        } else {
            ack = "No queued container. Check-in commits through yardManagement.checkInTrailer with location + trailer + seal."
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 300)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Helpers

    private func shortTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        struct Input: Encodable { let windowHours: Int; let limit: Int }
        do {
            self.data = try await EusoTripAPI.shared.query(
                "railGate.getGateActivity", input: Input(windowHours: 24, limit: 200))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("663 · Rail Gate Check-In · Night") {
    RailGateCheckInScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("663 · Rail Gate Check-In · Light") {
    RailGateCheckInScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
