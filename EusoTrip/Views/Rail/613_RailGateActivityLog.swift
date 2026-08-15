//
//  613_RailGateActivityLog.swift
//  EusoTrip — Rail Engineer · Gate Activity Log (carrier-side event feed).
//
//  A slim LIVE counter tape (gate-in / gate-out / flags / turn-time) over a
//  vertical spine timeline whose nodes are individual railcar gate moves, each
//  tagged IN / OUT / FLAG. An AEI tag-swap anomaly (physical seal or AEI tag
//  disagrees with the EDI-322 seal of record) is raised inline in a danger
//  callout so the suspect car is read at a glance and HELD before interchange.
//
//  Live wiring: railGate.getGateActivity (events + counts + avgTurnMinutes),
//  tenant-scoped. Honest: no events in the window → an honest empty state.
//

import SwiftUI

struct RailGateActivityLogScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailGateActivityLogBody() } nav: {
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

// MARK: - Decodable model (matches railGate.getGateActivity)

private struct GateEvent613: Decodable, Identifiable {
    let id: String
    let railcarNumber: String?
    let trainId: String?
    let gateType: String     // gate_in | gate_out | flag
    let site: String?
    let sealNumber: String?
    let ediSeal: String?
    let aeiTag: String?
    let anomaly: Bool
    let anomalyReason: String?
    let occurredAt: String?
}

private struct GateCounts613: Decodable {
    let gateIn: Int
    let gateOut: Int
    let flags: Int
    let anomalies: Int
}

private struct GateActivity613: Decodable {
    let events: [GateEvent613]?
    let counts: GateCounts613?
    let avgTurnMinutes: Int?
}

// MARK: - Body

private struct RailGateActivityLogBody: View {
    @Environment(\.palette) private var palette
    @State private var data: GateActivity613? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var events: [GateEvent613] { data?.events ?? [] }
    private var counts: GateCounts613? { data?.counts }

    private func kind(_ e: GateEvent613) -> (label: String, color: Color, icon: String) {
        if e.anomaly { return ("FLAG", Brand.danger, "exclamationmark.triangle.fill") }
        switch e.gateType {
        case "gate_in":  return ("IN",   Brand.info,          "arrow.down.to.line")
        case "gate_out": return ("OUT",  palette.textSecondary, "arrow.up.right")
        default:          return ("FLAG", Brand.danger,        "flag.fill")
        }
    }

    private func shortTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading gate activity…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    counterTape
                    if (counts?.anomalies ?? 0) > 0 { anomalyBanner }
                    if events.isEmpty {
                        LifecycleCard { Text("No gate moves in the last 24h.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        timeline
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · GATE ACTIVITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Gate activity")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Counter tape

    private var counterTape: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "IN",    value: "\(counts?.gateIn ?? 0)",  accent: Brand.info)
            MetricTile(label: "OUT",   value: "\(counts?.gateOut ?? 0)", gradientNumeral: true)
            MetricTile(label: "FLAGS", value: "\(counts?.flags ?? 0)",   accent: Brand.warning)
            MetricTile(label: "TURN",  value: data?.avgTurnMinutes.map { "\($0)m" } ?? "—")
        }
    }

    // MARK: Anomaly banner

    private var anomalyBanner: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(counts?.anomalies ?? 0) AEI tag-swap anomal\(counts?.anomalies == 1 ? "y" : "ies")")
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("Seal / AEI read disagrees with the EDI-322 seal. Hold for re-read before interchange.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("GATE MOVES · newest first")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
                    eventNode(e, isLast: idx == events.count - 1)
                }
            }
        }
    }

    private func eventNode(_ e: GateEvent613, isLast: Bool) -> some View {
        let k = kind(e)
        return HStack(alignment: .top, spacing: Space.s3) {
            // Spine + node dot
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(k.color.opacity(0.16)).frame(width: 28, height: 28)
                    Image(systemName: k.icon).font(.system(size: 11, weight: .heavy)).foregroundStyle(k.color)
                }
                if !isLast {
                    Rectangle().fill(palette.borderFaint).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(k.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(k.color.opacity(0.14)))
                    Text(e.railcarNumber ?? "—")
                        .font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(shortTime(e.occurredAt))
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(palette.textTertiary)
                }
                Text("\(e.site ?? "gate")\(e.trainId != nil ? " · train \(e.trainId!)" : "")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)

                // Inline anomaly callout — the suspect tag, held.
                if e.anomaly, let reason = e.anomalyReason {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                        Text(reason)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.danger)
                    }
                    .padding(Space.s2)
                    .background(Brand.danger.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Brand.danger.opacity(0.30)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            .padding(.bottom, Space.s3)
        }
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        struct Input: Encodable { let windowHours: Int; let limit: Int }
        do {
            self.data = try await EusoTripAPI.shared.query("railGate.getGateActivity", input: Input(windowHours: 24, limit: 200))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("613 · Rail Gate Activity · Night") { RailGateActivityLogScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("613 · Rail Gate Activity · Light") { RailGateActivityLogScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
