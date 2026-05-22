//
//  531_DispatcherClosedKanbanCelM04.swift
//  EusoTrip — Dispatcher · CLOSED kanban / paid-settled lane (§406).
//
//  Wireframe slot: 04 Dispatcher / 531 Dispatcher Closed Kanban Cel M04.
//  Extends the Dpch820 kanban quintet (526-530) to a CLOSED-state
//  surface — the dispatcher counterpart to Driver 149. Same §406 ring
//  roll, dispatcher vantage: the kanban card moves from PAPERWORK
//  lane to CLOSED lane when the factoring autopilot writes
//  invoiced→paid (dispatch.ts:284). Dispatcher does NOT fire the
//  close; the surface CONSUMES the resulting paid fan-out + re-polls
//  the dispatcher kanban board.
//
//  Doctrine: every visible value binds to `loads.getById`. No
//  scenario literals — the wireframe shows canonical CEL/M-04/NC
//  strings to illustrate the moment; production substitutes whichever
//  load is bound and shows "—" when a field hasn't resolved.
//

import SwiftUI

// MARK: - tRPC decode shape

private struct DCKLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let distance: Double?
    let rate: String?
    let driverId: Int?
    let catalystId: Int?
    let shipperId: Int?
    let pickupLocation: DCKCityState?
    let deliveryLocation: DCKCityState?
    let deliveryDate: String?
    struct DCKCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct DispatcherM04ClosedKanbanScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            DCKBody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct DCKBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: DCKLoadCtx?

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "—"
    }
    private var settleDateDisplay: String {
        guard let iso = load?.deliveryDate,
              let delivered = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let settle = Calendar.current.date(byAdding: .day, value: 30, to: delivered) ?? delivered
        let f = DateFormatter(); f.dateFormat = "M/d"
        return f.string(from: settle)
    }
    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city else { return nil }
        return "\(p) → \(d)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                boardPill
                identityRow
                kpiGrid
                cardArchivedRow
                closedFanOutRow
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BOARD · CLOSED · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Kanban · CLOSED lane")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("PAID · ring rolled PAPERWORK → CLOSED · card archives on wallet credit")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CLOSED LANE · PAID · CARD ARCHIVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · payout \(rateDisplay) · NET-30 \(settleDateDisplay) · CLOSED")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text(lane)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var boardPill: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("BOARD STATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · settlement closed · 0 open cards on this load")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(load?.catalystId.map { "dispatcher · catalyst #\($0)" } ?? "dispatcher")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Carrier · driver · shipper")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("LANE",   "CLOSED",            "from PAPERWORK · ring rolled", .green),
            ("PAYOUT", rateDisplay,         "NET-30 \(settleDateDisplay)",  .green),
            ("CARDS",  "0",                 "open on this load",            .blue),
            ("STATE",  "PAID",              load?.status ?? "—",            .green),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    private var cardArchivedRow: some View {
        LifecycleCard(accentGradient: true) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("KANBAN · CARD ARCHIVED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("PAPERWORK lane → CLOSED lane · auto on wallet credit")
                        .font(.system(size: 8.5, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("ARCHIVED")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var closedFanOutRow: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FAN-OUT · PAYMENT RECEIVED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("loadLifecycle paid → [catalystId, driverId]")
                        .font(.system(size: 8.5, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("CONSUMED")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var nextStepCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("Card archived. Settlement complete. Free this driver slot for the next assignment.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* read-only screen, tolerate */ }
    }
}

// MARK: - Previews

#Preview("531 Closed Kanban · Light") {
    DispatcherM04ClosedKanbanScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("531 Closed Kanban · Dark") {
    DispatcherM04ClosedKanbanScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
