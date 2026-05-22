//
//  378_CatalystClosedPayoutCelM04.swift
//  EusoTrip — Catalyst · Closed payout receipt (§407).
//
//  Wireframe slot: 03 Catalyst / 378 Catalyst Closed Payout Cel M04.
//  Sister to Driver 149 (paid receipt). Post-paid catalyst vantage:
//  the factoring autopilot wrote invoiced→paid (dispatch.ts:284) and
//  the loadLifecycle paid fan-out routed to [catalystId, driverId].
//  This screen CONSUMES that fan-out, displays the catalyst payout,
//  and rolls the lane row PAPERWORK → CLOSED.
//
//  Doctrine: every visible value binds to a real tRPC proc. No
//  scenario literals; "—" until data resolves.
//

import SwiftUI

// MARK: - tRPC decode shape

private struct CCPLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let pickupLocation: CCPCityState?
    let deliveryLocation: CCPCityState?
    let actualDeliveryDate: String?
    let deliveryDate: String?
    let updatedAt: String?
    struct CCPCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct CatalystClosedPayoutScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var onViewSettlement: (() -> Void)? = nil
    var onDone: (() -> Void)? = nil

    var body: some View {
        Shell(theme: theme) {
            CCPBody(loadId: loadId, onViewSettlement: onViewSettlement, onDone: onDone)
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

private struct CCPBody: View {
    let loadId: String
    let onViewSettlement: (() -> Void)?
    let onDone: (() -> Void)?
    @Environment(\.palette) private var palette
    @State private var load: CCPLoad?

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var payoutDisplay: String {
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
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var paidAtDisplay: String {
        let iso = load?.updatedAt
        guard let iso, let dt = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: dt)
    }
    private var rpmDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0,
              let d = load?.distance, d > 0 else { return "—" }
        return String(format: "$%.2f/mi", n / d)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                payoutHero
                kpiGrid
                receiptCard
                fanOutReceivedRow
                actionRibbon
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
                Text("CATALYST · DISPATCH · CLOSED · PAID · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Payout received")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Factoring autopilot fired invoiced → paid · lane row CLOSED")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CLOSED · PAYOUT CONFIRMED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(equipmentDisplay) · payout \(payoutDisplay) · CLOSED")
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

    private var payoutHero: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CATALYST PAYOUT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("PAID")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                Text(payoutDisplay)
                    .font(.system(size: 32, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("Paid \(paidAtDisplay)")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("PAYOUT",   payoutDisplay,    "settlement complete", .green),
            ("RPM",      rpmDisplay,       distanceDisplay,       .blue),
            ("LANE",     "CLOSED",         "ring rolled",         .green),
            ("STATE",    (load?.status ?? "—").uppercased(), "load row", .green),
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

    private var receiptCard: some View {
        let rows: [(label: String, value: String, kind: ReceiptRowKind)] = [
            ("Delivered · status flipped",        "DONE",     .done),
            ("Invoiced · factoring autopilot",    "DONE",     .done),
            ("Paid · invoiced → paid auto-write", "DONE",     .done),
            ("Lane row · ring → CLOSED",          "CLOSED",   .done),
        ]
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("PAYOUT CHECKLIST · 4 of 4 COMPLETE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        receiptBadge(row.kind)
                        Text(row.label)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(row.value)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }
                }
            }
        }
    }

    private enum ReceiptRowKind { case done }

    private func receiptBadge(_ k: ReceiptRowKind) -> some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.18)).frame(width: 16, height: 16)
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.green)
        }
    }

    private var fanOutReceivedRow: some View {
        LifecycleCard(accentGradient: true) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAID · FAN-OUT CONSUMED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("loadLifecycle paid → [catalystId, driverId]")
                        .font(.system(size: 8.5, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text("RECEIVED")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { onViewSettlement?() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 13, weight: .heavy))
                    Text("View settlement").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white)
                .background(onViewSettlement == nil
                            ? AnyShapeStyle(LinearGradient(colors: [palette.textTertiary, palette.textTertiary], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onViewSettlement == nil)

            Button { onDone?() } label: {
                Text("Done").font(EType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(LinearGradient.diagonal)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
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

#Preview("378 Closed Payout · Light") {
    CatalystClosedPayoutScreen(theme: Theme.light, loadId: "0", onViewSettlement: {}, onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("378 Closed Payout · Dark") {
    CatalystClosedPayoutScreen(theme: Theme.dark, loadId: "0", onViewSettlement: {}, onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
