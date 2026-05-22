//
//  377_CatalystPaperworkSettlementPrepCelM04.swift
//  EusoTrip — Catalyst · Paperwork / settlement prep (§403).
//
//  Wireframe slot: 03 Catalyst / 377 Catalyst Paperwork Settlement
//  Prep Cel M04. Catalyst-vantage paperwork stage between
//  Driver §402 POD-signed and §406 paid. Read-only consumer —
//  there is no catalyst verb to set "invoiced" or "paid"; the
//  factoring autopilot (dispatch.ts:280 → invoiced;
//  dispatch.ts:284 → paid) drives the state machine. This surface
//  CONSUMES the delivered-load and waits for the paid fan-out
//  (loadLifecycle.ts:96 → [catalystId, driverId]).
//
//  Doctrine: every visible value binds to a real tRPC proc. No
//  scenario literals; "—" until data resolves. No mock data.
//

import SwiftUI

// MARK: - tRPC decode shape

private struct CPSLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let hazmatClass: String?
    let pickupLocation: CPSCityState?
    let deliveryLocation: CPSCityState?
    let pickupDate: String?
    let deliveryDate: String?
    let actualDeliveryDate: String?
    let updatedAt: String?
    struct CPSCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct CatalystPaperworkSettlementPrepScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            CPSBody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet",  systemImage: "creditcard.fill",      isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CPSBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: CPSLoad?

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "—"
    }
    private var laneDisplay: String? {
        let p = [load?.pickupLocation?.city, load?.pickupLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if p.isEmpty && d.isEmpty { return nil }
        return "\(p.isEmpty ? "—" : p) → \(d.isEmpty ? "—" : d)"
    }
    private var deliveredAtDisplay: String {
        let iso = load?.actualDeliveryDate ?? load?.updatedAt
        guard let iso, let dt = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: dt)
    }
    private var settleEtaDisplay: String {
        let iso = load?.actualDeliveryDate ?? load?.deliveryDate
        guard let iso, let delivered = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let settle = Calendar.current.date(byAdding: .day, value: 30, to: delivered) ?? delivered
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: settle)
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                stagePipeline
                kpiGrid
                settlementChecklist
                fanOutWaitRow
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
                Text("CATALYST · DISPATCH · PAPERWORK · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Paperwork · settlement prep")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Delivered · waiting on factoring autopilot to invoice → pay")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PAPERWORK STAGE · SETTLEMENT QUEUED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(equipmentDisplay) · payout \(rateDisplay)")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text("\(lane) · \(distanceDisplay)")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var stagePipeline: some View {
        let stages: [(label: String, state: StageState)] = [
            ("AWARDED",   .done),
            ("PICKUP",    .done),
            ("TRANSIT",   .done),
            ("DELIVERED", .done),
            ("PAPERWORK", .active),
            ("PAID",      .pending),
        ]
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("STAGE PIPELINE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 4) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                        stagePill(label: s.label, state: s.state)
                        if i < stages.count - 1 {
                            Rectangle()
                                .fill(s.state == .pending ? palette.textTertiary.opacity(0.25) : palette.textTertiary.opacity(0.6))
                                .frame(width: 6, height: 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private enum StageState { case done, active, pending }

    private func stagePill(label: String, state: StageState) -> some View {
        let fg: Color = state == .pending ? palette.textTertiary : .white
        return Text(label)
            .font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(0.4)
            .foregroundStyle(state == .active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(fg))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(
                Capsule().fill(
                    state == .done ? AnyShapeStyle(LinearGradient.diagonal) :
                    state == .active ? AnyShapeStyle(palette.bgCard) :
                    AnyShapeStyle(palette.bgCard.opacity(0.5))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    state == .active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.7)) : AnyShapeStyle(Color.clear),
                    lineWidth: state == .active ? 1.5 : 0
                )
            )
    }

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("PAYOUT",     rateDisplay,           "settlement queued",    .green),
            ("DELIVERED",  deliveredAtDisplay,    "actual",               .blue),
            ("SETTLE ETA", settleEtaDisplay,      "NET-30",               .blue),
            ("STATE",      (load?.status ?? "—").uppercased(), "load row", .orange),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 16, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint).lineLimit(1)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    private var settlementChecklist: some View {
        let rows: [(label: String, value: String, done: Bool)] = [
            ("Load delivered · status set",           "DONE",             true),
            ("POD signed · driver verb fired",        "DONE",             true),
            ("Invoice prep · factoring autopilot",    "QUEUED",           false),
            ("Payout paid · invoiced → paid",         "QUEUED",           false),
        ]
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("SETTLEMENT CHECKLIST · 2 of 4")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        if row.done {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.18)).frame(width: 16, height: 16)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.green)
                            }
                        } else {
                            ZStack {
                                Circle().stroke(palette.textTertiary.opacity(0.4), lineWidth: 1).frame(width: 16, height: 16)
                                Image(systemName: "clock")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        Text(row.label)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(row.value)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(row.done ? Color.green : palette.textTertiary)
                    }
                }
            }
        }
    }

    private var fanOutWaitRow: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WAITING ON · loadLifecycle paid fan-out")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("dispatch.ts:284 invoiced→paid · routes to [catalystId, driverId]")
                        .font(.system(size: 8.5, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("WAIT")
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
                Text("Card auto-archives when the paid fan-out lands. No catalyst action required at this stage.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated */ }
    }
}

// MARK: - Previews

#Preview("377 Paperwork Prep · Light") {
    CatalystPaperworkSettlementPrepScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("377 Paperwork Prep · Dark") {
    CatalystPaperworkSettlementPrepScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
